// 孤独症初筛记录 API 链路冒烟脚本：走真实 HTTP + 信封加密，覆盖初筛
// 五个路由的完整链路（登录携「角色-科室」组合 → 新增检查医生用户 →
// 建档 → wscmbdItems 查条目（基础数据待录入为空表）→ save 新增（无
// 转诊落「无」）→ save 修改同键覆盖（异常 + 有转诊）→ query 回读校验
// → doctors 同科室候选 → delete 删除 → 清理冒烟档案）。
// 用法：后端启动后 cd server && dart run tool/initial_screening_api_smoke.dart
// （默认 http://localhost:8080，可经 SMOKE_BASE_URL 环境变量覆盖）。
import 'dart:convert';
import 'dart:io';

import 'package:common/utils/security_helper.dart';
import 'package:http/http.dart' as http;

final baseUrl = Platform.environment['SMOKE_BASE_URL'] ?? 'http://localhost:8080';

Future<void> main() async {
  final client = http.Client();

  // 1. 明文拉角色-科室组合并登录（登录须携带所选「角色-科室」授权组合，
  // 会话的医院/科室上下文据此推导，初筛记录的归属与检查医生校验都依赖它）
  final rolesResp = await client.get(Uri.parse('$baseUrl/api/auth/roles?usercode=admin'));
  final roles = ((jsonDecode(rolesResp.body) as Map<String, dynamic>)['data'] as Map<String, dynamic>)['roles'] as List<dynamic>;
  if (roles.isEmpty) {
    throw StateError('admin 无可选角色，请先执行 seed_demo_data');
  }
  final grant = roles.first as Map<String, dynamic>;
  final roleId = grant['id'] as String;
  final deptId = (grant['deptId'] as String?) ?? '';
  final loginResp = await client.post(
    Uri.parse('$baseUrl/api/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'usercode': 'admin', 'password': 'Admin@123', 'role': roleId, 'deptId': deptId}),
  );
  final loginData = _unwrapPlain(loginResp);
  final loginUserId = (loginData['user'] as Map<String, dynamic>)['id'] as String;
  final loginHospId = (loginData['user'] as Map<String, dynamic>)['hospId'] as String;
  final token = loginData['token'] as String;
  final sessionKey = loginData['sessionKey'] as String;
  print('1. 登录成功 token=${token.substring(0, 8)}...（科室上下文 $deptId）');

  final headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {bool allowFailure = false}) async {
    final sealedBody = await SecurePayload.seal(sessionKey, body);
    final resp = await client.post(Uri.parse('$baseUrl$path'), headers: headers, body: jsonEncode(sealedBody));
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
  String? childId;
  String? doctorId;
  try {
    // 2. 新增一名挂当前科室的医生用户（演示账号均未挂科室，检查医生校验
    // 要求「同科室 DOCTOR」，随冒烟账号落库即可，不清理——用户不做删除）
    final doctorCreated = await post('/api/user/add', {
      'hospId': loginHospId,
      'deptId': deptId,
      'userCode': 'SMKASD$suffix',
      'userName': '冒烟医生$suffix',
      'password': 'SmkAsd@12345',
      'userType': 'DOCTOR',
      'permissionLevel': '1',
    });
    doctorId = (doctorCreated['user'] as Map<String, dynamic>)['id'] as String;
    print('2. 已新增检查医生 SMKASD$suffix');

    // 3. 建档（初筛记录挂靠本院儿童）
    final created = await post('/api/child/add', {
      'child': {
        'checkTime': '2026-11-23',
        'visitCardNo': 'ASD$suffix',
        'name': '初筛冒烟儿童$suffix',
        'sex': '1',
        'birthDate': '2025-11-01',
        'addressProvince': '110000',
        'addressCity': '110100',
        'addressCounty': '110101',
        'addressDetails': '初筛冒烟路 1 号',
      },
    });
    childId = (created['child'] as Map<String, dynamic>)['id'] as String;
    print('3. 已建档 $childId');

    // 4. 预警征象条目查询（SCALE_WSCMBD 基础数据由运维录入，空表返回
    // 空列表即通过——验证查询链路而非数据）
    final wscmbd = await post('/api/initialScreening/wscmbdItems', {'month': 12});
    final items = wscmbd['items'] as List<dynamic>;
    print('4. 12 月龄预警征象条目 ${items.length} 条（基础数据待录入，空表合法）');

    // 5. save 新增（12 月龄、无转诊）：转诊医院名称落「无」、科室清空
    final first = await post('/api/initialScreening/save', {
      'record': {
        'childId': childId,
        'checkDate': '2026-11-23',
        'ageYear': 1,
        'ageMonth': 0,
        'ageDay': 22,
        'correctedAgeYear': null,
        'correctedAgeMonth': null,
        'correctedAgeDay': null,
        'checkMonth': 12,
        'warningSignResult': '未见异常',
        'languageSocialCommunicationResult': '未见异常',
        'checkResult': '未见异常',
        'hasReferral': '0',
        'referralHospName': '',
        'doctorId': doctorId,
        'doctorName': '冒烟医生$suffix',
      },
    });
    final record = first['record'] as Map<String, dynamic>;
    final recordId = record['id'] as String;
    if (record['referralHospName'] != '无' || record['referralDeptName'] != null) {
      throw StateError('无转诊落库口径不符: ${record['referralHospName']} / ${record['referralDeptName']}');
    }
    print('5. 新增成功 id=$recordId（无转诊落「无」）');

    // 6. save 修改同一键（12 月龄）：异常 + 有转诊，同键应覆盖同一条
    final second = await post('/api/initialScreening/save', {
      'record': {
        'childId': childId,
        'checkDate': '2026-11-23',
        'ageYear': 1,
        'ageMonth': 0,
        'ageDay': 22,
        'checkMonth': 12,
        'warningSignResult': '不会挥手表示“再见”或拍手表示“欢迎”',
        'languageSocialCommunicationResult': '语言功能障碍或倒退',
        'checkResult': '异常',
        'hasReferral': '1',
        'referralHospName': '市儿童医院',
        'referralDeptName': '儿童康复科',
        'doctorId': doctorId,
        'doctorName': '冒烟医生$suffix',
      },
    });
    final updated = second['record'] as Map<String, dynamic>;
    if (updated['id'] != recordId) {
      throw StateError('同键保存应覆盖原记录：${updated['id']} != $recordId');
    }
    if (updated['referralHospName'] != '市儿童医院' || updated['checkResult'] != '异常') {
      throw StateError('修改保存内容不符: ${updated['checkResult']} / ${updated['referralHospName']}');
    }
    print('6. 修改成功（同键覆盖，有转诊落字典值口径）');

    // 7. query 回读：一条记录、值为最新
    final queried = await post('/api/initialScreening/query', {'childId': childId});
    final records = queried['records'] as List<dynamic>;
    if (records.length != 1) {
      throw StateError('query 应返回 1 条，实际 ${records.length}');
    }
    print('7. query 回读 ${records.length} 条，检查时段 ${(records.first as Map<String, dynamic>)['checkMonth']}');

    // 8. 检查医生候选：应包含刚新增的同科室医生
    final doctorsData = await post('/api/initialScreening/doctors', {});
    final doctors = doctorsData['doctors'] as List<dynamic>;
    if (!doctors.any((d) => (d as Map<String, dynamic>)['id'] == doctorId)) {
      throw StateError('doctors 候选缺少新增医生');
    }
    print('8. doctors 候选 ${doctors.length} 人，含新增医生');

    // 9. 反例：检查医生传管理员自身（非 DOCTOR）应被拒绝
    final bad = await post('/api/initialScreening/save', {
      'record': {
        'childId': childId,
        'checkDate': '2026-11-23',
        'ageYear': 1,
        'ageMonth': 0,
        'ageDay': 22,
        'checkMonth': 6,
        'warningSignResult': '未见异常',
        'languageSocialCommunicationResult': '未见异常',
        'checkResult': '未见异常',
        'hasReferral': '0',
        'referralHospName': '',
        'doctorId': loginUserId,
        'doctorName': '系统管理员',
      },
    }, allowFailure: true);
    if (bad['code'] == 0) {
      throw StateError('非 DOCTOR 检查医生应被拒绝');
    }
    print('9. 反例通过：非同科室 DOCTOR 医生被拒绝（${bad['message']}）');

    // 10. delete 删除并确认
    await post('/api/initialScreening/delete', {'id': recordId});
    final after = await post('/api/initialScreening/query', {'childId': childId});
    if ((after['records'] as List<dynamic>).isNotEmpty) {
      throw StateError('删除后仍有记录');
    }
    print('10. delete 成功，回读为空');
    print('初筛记录 API 链路冒烟通过 ✓');
  } finally {
    // 清理冒烟档案（连带扩展/监护人与残余初筛记录）
    if (childId != null) {
      final sealed = await SecurePayload.seal(sessionKey, {'id': childId});
      final resp = await client.post(Uri.parse('$baseUrl/api/child/delete'), headers: headers, body: jsonEncode(sealed));
      var json = jsonDecode(resp.body) as Map<String, dynamic>;
      if (json.containsKey('payload')) {
        json = await SecurePayload.open(sessionKey, json);
      }
      print('清理冒烟儿童档案 -> ${json['code'] == 0 ? 'ok' : '失败（手工清理 $childId）'}');
    }
    client.close();
  }
}

/// 解开明文登录响应（登录在白名单，响应不封信封）。
Map<String, dynamic> _unwrapPlain(http.Response resp) {
  final json = jsonDecode(resp.body) as Map<String, dynamic>;
  if (json['code'] != 0) {
    throw StateError('接口失败: ${json['message']}');
  }
  return json['data'] as Map<String, dynamic>;
}
