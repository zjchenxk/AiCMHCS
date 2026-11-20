// 高危因素互斥规则 API 链路冒烟脚本：走真实 HTTP + 信封加密，覆盖动作式
// 路由 query/add/update/delete 的完整链路（先建两条高危因素字典，再建
// 互斥规则、验证无序组合判重、第三项修改，最后清理）。
// 用法：后端启动后 cd server && dart run tool/high_risk_factor_exclusion_api_smoke.dart
import 'dart:convert';

import 'package:common/utils/security_helper.dart';
import 'package:http/http.dart' as http;

const baseUrl = 'http://localhost:8080';

Future<void> main() async {
  final client = http.Client();

  // 1. 明文登录拿 token + sessionKey（登录须携带所选角色 ID——主键为
  // UUID v7，先经白名单明文接口 /api/auth/roles 拉取该用户角色列表）
  final rolesResp = await client.get(
    Uri.parse('$baseUrl/api/auth/roles?usercode=admin'),
  );
  final roles = ((jsonDecode(rolesResp.body) as Map<String, dynamic>)['data'] as Map<String, dynamic>)['roles'] as List<dynamic>;
  if (roles.isEmpty) {
    throw StateError('admin 无可选角色，请先执行 seed_demo_data');
  }
  final roleId = (roles.first as Map<String, dynamic>)['id'] as String;
  final loginResp = await client.post(
    Uri.parse('$baseUrl/api/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'usercode': 'admin', 'password': 'Admin@123', 'role': roleId}),
  );
  final loginData = _unwrapPlain(loginResp);
  final token = loginData['token'] as String;
  final sessionKey = loginData['sessionKey'] as String;
  print('1. 登录成功 token=${token.substring(0, 8)}...');

  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {bool allowFailure = false}) async {
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
      if (allowFailure) return json;
      throw StateError('接口失败: ${json['message']}');
    }
    return (json['data'] as Map<String, dynamic>?) ?? const {};
  }

  final suffix = DateTime.now().millisecondsSinceEpoch.toString().substring(5);
  final factorIds = <String>[];
  try {
    // 2. 建三条高危因素（冒烟用，末尾清理）
    for (final (code, name, color) in [
      ('SMK$suffix-1', '冒烟互斥因素一', '黄色'),
      ('SMK$suffix-2', '冒烟互斥因素二', '橙色'),
      ('SMK$suffix-3', '冒烟互斥因素三', '红色'),
    ]) {
      final created = await post('/api/highRiskFactor/add', {
        'riskFactorCode': code,
        'riskFactorName': name,
        'riskColor': color,
      });
      factorIds.add((created['factor'] as Map<String, dynamic>)['id'] as String);
    }
    print('2. 已建三条高危因素: $factorIds');

    // 3. 新增两项互斥规则
    final created = await post('/api/highRiskFactorExclusion/add', {
      'firstRiskFactorId': factorIds[0],
      'secondRiskFactorId': factorIds[1],
    });
    final rule = created['exclusion'] as Map<String, dynamic>;
    final ruleId = rule['id'] as String;
    final hospId = rule['hospId'] as String;
    print('3. 新增互斥规则 $ruleId（医院 $hospId）');

    // 4. 列表回读包含新规则
    final list = (await post('/api/highRiskFactorExclusion/query', {}))['exclusions'] as List<dynamic>;
    final hit = list.any((e) => (e as Map<String, dynamic>)['id'] == ruleId);
    print('4. 列表 ${list.length} 条，包含新规则: $hit');

    // 5. 无序组合判重：B+A 应被拒绝
    final dup = await post(
      '/api/highRiskFactorExclusion/add',
      {'firstRiskFactorId': factorIds[1], 'secondRiskFactorId': factorIds[0]},
      allowFailure: true,
    );
    final dupRejected = dup['code'] != 0;
    print('5. 无序组合判重生效: $dupRejected');

    // 6. 修改：第二项改为第三因素，同时补第三项
    final updated =
        (await post('/api/highRiskFactorExclusion/update', {
              'id': ruleId,
              'secondRiskFactorId': factorIds[2],
              'thirdRiskFactorId': factorIds[1],
            }))['exclusion']
            as Map<String, dynamic>;
    print('6. 修改成功 second=${updated['secondRiskFactorId']} third=${updated['thirdRiskFactorId']}');

    // 7. 清空第三项（null 语义）
    final cleared =
        (await post('/api/highRiskFactorExclusion/update', {
              'id': ruleId,
              'thirdRiskFactorId': null,
            }))['exclusion']
            as Map<String, dynamic>;
    print('7. 第三项清空: ${cleared['thirdRiskFactorId'] == null}');

    if (!hit || !dupRejected || updated['secondRiskFactorId'] != factorIds[2] || updated['thirdRiskFactorId'] != factorIds[1] || cleared['thirdRiskFactorId'] != null) {
      throw StateError('链路断言失败');
    }
  } finally {
    // 8. 清理：先删涉及冒烟因素的规则，再删高危因素
    final exclusions = (await post('/api/highRiskFactorExclusion/query', {}))['exclusions'] as List<dynamic>;
    for (final e in exclusions) {
      final rule = e as Map<String, dynamic>;
      final ids = [rule['firstRiskFactorId'], rule['secondRiskFactorId'], rule['thirdRiskFactorId']];
      if (ids.any(factorIds.contains)) {
        await post('/api/highRiskFactorExclusion/delete', {'id': rule['id']}, allowFailure: true);
      }
    }
    for (final id in factorIds) {
      await post('/api/highRiskFactor/delete', {'id': id}, allowFailure: true);
    }
    print('8. 清理完成');
    client.close();
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
