// 行政区划 API 链路冒烟脚本：走真实 HTTP + 信封加密，覆盖动作式路由
// query/add/update/delete 的完整链路（新增后回读、改名、级联删除）。
// 用法：后端启动后 cd server && dart run tool/admin_division_api_smoke.dart
import 'dart:convert';

import 'package:common/utils/security_util.dart';
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

  // 2. 查询省级列表（parentCode 缺省），取第一个省作为父级
  final provinces = (await post('/api/adminDivisions/query', {}))['divisions'] as List<dynamic>;
  final parent = provinces.first as Map<String, dynamic>;
  print('2. 省级列表 ${provinces.length} 条，父级=${parent['code']} ${parent['name']} hasChildren=${parent['hasChildren']}');

  // 3. 查询该省当前子级
  final before = (await post('/api/adminDivisions/query', {'parentCode': parent['code']}))['divisions'] as List<dynamic>;
  print('3. ${parent['name']} 子级 ${before.length} 条');

  // 4. 新增下级
  final testCode = '99${DateTime.now().millisecondsSinceEpoch}'.substring(0, 12).padRight(12, '0');
  await post('/api/adminDivisions/add', {
    'code': testCode,
    'name': '冒烟测试区划',
    'parentCode': parent['code'],
  });
  print('4. 新增成功: $testCode');

  // 5. 再查子级：必须包含新节点（新增后回读验证）
  final after = (await post('/api/adminDivisions/query', {'parentCode': parent['code']}))['divisions'] as List<dynamic>;
  final hit = after.any((d) => (d as Map<String, dynamic>)['code'] == testCode);
  print('5. 重新查询子级 ${after.length} 条，包含新节点: $hit');

  // 6. 改名 + 按代码查详情与子树规模
  await post('/api/adminDivisions/update', {'code': testCode, 'name': '冒烟测试区划（改名）'});
  final detail = await post('/api/adminDivisions/query', {'code': testCode});
  print('6. 改名+详情 OK subtreeCount=${detail['subtreeCount']}');

  // 7. 清理：级联删除
  final deleted = await post('/api/adminDivisions/delete', {'code': testCode});
  print('7. 删除成功 deleted=${deleted['deleted']}');

  client.close();
  if (!hit) {
    throw StateError('新增后查询未包含新节点——链路异常');
  }
  print('全部链路正常');
}

Map<String, dynamic> _unwrapPlain(http.Response resp) {
  final json = jsonDecode(resp.body) as Map<String, dynamic>;
  if (json['code'] != 0) {
    throw StateError('登录失败: ${json['message']}');
  }
  return json['data'] as Map<String, dynamic>;
}
