// 行政区划 API 链路冒烟脚本（临时排查用）：走真实 HTTP + 信封加密，
// 复现「添加下级行政区划后未刷新」的完整链路。
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

  Map<String, String> headers() => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> sealed(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$baseUrl$path');
    final http.Response resp;
    if (body == null) {
      final req = http.Request(method, uri)..headers.addAll(headers());
      resp = await http.Response.fromStream(await client.send(req));
    } else {
      final sealedBody = await SecurePayload.seal(sessionKey, body);
      final req = http.Request(method, uri)
        ..headers.addAll(headers())
        ..body = jsonEncode(sealedBody);
      resp = await http.Response.fromStream(await client.send(req));
    }
    var json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (json.containsKey('payload')) {
      json = await SecurePayload.open(sessionKey, json);
    }
    print('   $method $path -> HTTP ${resp.statusCode} code=${json['code']} message=${json['message']}');
    if (json['code'] != 0) {
      throw StateError('接口失败: ${json['message']}');
    }
    return (json['data'] as Map<String, dynamic>?) ?? const {};
  }

  // 2. 查询省级列表，取第一个省作为父级
  final provinces = (await sealed('GET', '/api/admin-divisions'))['divisions'] as List<dynamic>;
  final parent = provinces.first as Map<String, dynamic>;
  print('2. 省级列表 ${provinces.length} 条，父级=${parent['code']} ${parent['name']} hasChildren=${parent['hasChildren']}');

  // 3. 查询该省当前子级（展开前的状态）
  final before = (await sealed('GET', '/api/admin-divisions?parentCode=${parent['code']}'))['divisions'] as List<dynamic>;
  print('3. ${parent['name']} 子级 ${before.length} 条');

  // 4. 新增下级（复现用户操作：选中省 → 添加下级）
  final testCode = '99${DateTime.now().millisecondsSinceEpoch}'.substring(0, 12).padRight(12, '0');
  final created = await sealed('POST', '/api/admin-divisions', {
    'code': testCode,
    'name': '冒烟测试区划',
    'parentCode': parent['code'],
  });
  print('4. 新增成功: ${(created['division'] as Map<String, dynamic>)['code']}');

  // 5. 再查子级：必须包含新节点（未刷新问题的核心验证点）
  final after = (await sealed('GET', '/api/admin-divisions?parentCode=${parent['code']}'))['divisions'] as List<dynamic>;
  final hit = after.any((d) => (d as Map<String, dynamic>)['code'] == testCode);
  print('5. 重新查询子级 ${after.length} 条，包含新节点: $hit');

  // 6. 改名 + 子树统计
  await sealed('PUT', '/api/admin-divisions/$testCode', {'name': '冒烟测试区划（改名）'});
  final detail = await sealed('GET', '/api/admin-divisions/$testCode');
  print('6. 改名+详情 OK subtreeCount=${detail['subtreeCount']}');

  // 7. 清理：级联删除
  final deleted = await sealed('DELETE', '/api/admin-divisions/$testCode');
  print('7. 删除成功 deleted=${deleted['deleted']}');

  client.close();
  if (!hit) {
    throw StateError('新增后查询未包含新节点——复现了「未刷新」问题');
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
