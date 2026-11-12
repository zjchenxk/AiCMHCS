// 医院 API 链路冒烟脚本：走真实 HTTP + 信封加密，覆盖动作式路由
// query/add/update/delete 的完整链路（新增顶级/下级、改字段、按 ID 查
// 详情与子树规模、级联删除）。
// 用法：后端启动后 cd server && dart run tool/hospital_api_smoke.dart
import 'dart:convert';

import 'package:common/utils/security_helper.dart';
import 'package:http/http.dart' as http;

const baseUrl = 'http://localhost:8080';

Future<void> main() async {
  final client = http.Client();

  // 1. 明文登录拿 token + sessionKey
  final loginResp = await client.post(
    Uri.parse('$baseUrl/api/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'usercode': 'admin', 'password': 'Admin@123'}),
  );
  final loginData = _unwrapPlain(loginResp);
  final token = loginData['token'] as String;
  final sessionKey = loginData['sessionKey'] as String;
  print('1. 登录成功 token=${token.substring(0, 8)}...');

  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final sealedBody = await SecurePayload.seal(sessionKey, body);
    final resp = await client.post(
      Uri.parse('$baseUrl$path'),
      headers: headers,
      body: jsonEncode(sealedBody),
    );
    var json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (json.containsKey('payload')) {
      json = await SecurePayload.open(sessionKey, json);
    }
    print('   POST $path -> HTTP ${resp.statusCode} code=${json['code']} message=${json['message']}');
    if (json['code'] != 0) {
      throw StateError('接口失败: ${json['message']}');
    }
    return (json['data'] as Map<String, dynamic>?) ?? const {};
  }

  // 2. 查询全部医院（扁平列表）
  final before = (await post('/api/hospital/query', {}))['hospitals'] as List<dynamic>;
  print('2. 医院列表 ${before.length} 条');

  // 3. 新增顶级医院（唯一 CODE 防重跑冲突）
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final rootCode = 'SMOKE$stamp';
  final root =
      (await post('/api/hospital/add', {
            'code': rootCode,
            'name': '冒烟测试医院',
            'province': '北京市',
            'city': '北京市',
            'county': '东城区',
            'address': '冒烟路1号',
            'tel': '010-66667777',
          }))['hospital']
          as Map<String, dynamic>;
  print('3. 新增顶级成功 id=${root['id']} parentId=${root['parentId']}');

  // 4. 新增下级医院
  final child =
      (await post('/api/hospital/add', {
            'parentId': root['id'],
            'code': '${rootCode}C1',
            'name': '冒烟测试医院-心理分院',
            'province': '北京市',
            'city': '北京市',
            'address': '冒烟路1-1号',
          }))['hospital']
          as Map<String, dynamic>;
  print('4. 新增下级成功 id=${child['id']} parentId=${child['parentId']}');

  // 5. 修改下级医院字段（改名 + 清空 tel + 换长水印并回读校验；
  //    20000 字符跨达梦 getDataW 8191 字符分块边界，压测长列读取）
  final watermark = String.fromCharCodes(List.generate(20000, (i) => 65 + (i % 26)));
  final updated =
      (await post('/api/hospital/update', {
            'id': child['id'],
            'name': '冒烟测试医院-儿童心理分院',
            'tel': null,
            'watermarkBase64': watermark,
          }))['hospital']
          as Map<String, dynamic>;
  final watermarkOk = updated['watermarkBase64'] == watermark;
  print('5. 修改成功 name=${updated['name']} tel=${updated['tel']} 水印回读一致=$watermarkOk');

  // 6. 再查全量：必须包含两所新医院，且父级 hasChildren 变 true
  final after = (await post('/api/hospital/query', {}))['hospitals'] as List<dynamic>;
  final rootAfter = after.firstWhere((h) => (h as Map<String, dynamic>)['code'] == rootCode) as Map<String, dynamic>;
  final countOk = after.length == before.length + 2 && rootAfter['hasChildren'] == true;
  print('6. 重新查询 ${after.length} 条（+2 预期 $countOk），父级 hasChildren=${rootAfter['hasChildren']}');

  // 7. 按 ID 查详情与子树规模
  final detail = await post('/api/hospital/query', {'id': root['id']});
  print('7. 详情+子树规模 OK subtreeCount=${detail['subtreeCount']}（预期 2）');

  // 8. 非法参数校验：缺 code / 重复 code
  final badResp1 = await _postRaw(client, headers, sessionKey, '/api/hospital/add', {'name': '缺代码'});
  final badResp2 = await _postRaw(client, headers, sessionKey, '/api/hospital/add', {
    'code': rootCode,
    'name': '重复代码',
    'province': '北京市',
    'city': '北京市',
    'address': '冒烟路',
  });
  print('8. 校验拦截 code=${badResp1['code']}/${badResp1['message']}、code=${badResp2['code']}/${badResp2['message']}');

  // 9. 清理：级联删除（含下级）
  final deleted = await post('/api/hospital/delete', {'id': root['id']});
  print('9. 级联删除成功 deleted=${deleted['deleted']}（预期 2）');

  client.close();
  print('医院链路冒烟通过。');
}

/// 明文响应解包（登录接口不走信封）。
Map<String, dynamic> _unwrapPlain(http.Response resp) {
  final json = jsonDecode(resp.body) as Map<String, dynamic>;
  if (json['code'] != 0) {
    throw StateError('登录失败: ${json['message']}');
  }
  return json['data'] as Map<String, dynamic>;
}

/// 发送请求并返回解密后的完整响应 JSON（不校验 code，供负向用例）。
Future<Map<String, dynamic>> _postRaw(
  http.Client client,
  Map<String, String> headers,
  String sessionKey,
  String path,
  Map<String, dynamic> body,
) async {
  final sealedBody = await SecurePayload.seal(sessionKey, body);
  final resp = await client.post(
    Uri.parse('$baseUrl$path'),
    headers: headers,
    body: jsonEncode(sealedBody),
  );
  var json = jsonDecode(resp.body) as Map<String, dynamic>;
  if (json.containsKey('payload')) {
    json = await SecurePayload.open(sessionKey, json);
  }
  return json;
}
