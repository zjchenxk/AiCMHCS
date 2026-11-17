import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/user_service.dart';

/// POST /api/user/update
/// 请求体：{id, ...要修改的字段, password?, roleIds?, roleDeptIds?}——
/// 可修改字段为 userName/userType/permissionLevel/phone/idCardNo/status/
/// hisUserCode/mchisUserCode/certId/avatarImage/signatureImage，值 null
/// 表示清空该列（仅可空列，userName/status 除外）；登录账号、归属医院、
/// 挂载科室不可改。
/// password 非空时重置口令（留空不改）；roleIds 非 null 时全量覆盖角色
/// 关联（null 不动角色，空列表即清空）；roleDeptIds 为 {角色ID:
/// [科室ID,...]} 的适用科室映射（随 roleIds 一并全量覆盖，键须覆盖
/// 全部勾选角色且每角色至少一个科室）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final id = body['id'];
  if (id is! String || id.trim().isEmpty) {
    return _error(400, 40001, '用户ID不能为空');
  }
  final password = body['password'];
  if (password != null && password is! String) {
    return _error(400, 40002, '密码应为字符串');
  }
  final roleIds = body['roleIds'];
  if (roleIds != null && (roleIds is! List || roleIds.any((e) => e is! String))) {
    return _error(400, 40002, '角色ID列表应为字符串数组');
  }
  final roleDeptIds = body['roleDeptIds'];
  if (roleDeptIds != null) {
    final err = _validateRoleDeptIds(roleDeptIds);
    if (err != null) return _error(400, 40002, err);
  }

  // 只把已知业务字段透传给服务层，其余键（含 id）一律拒绝
  const allowed = <String>{
    'userName',
    'userType',
    'permissionLevel',
    'phone',
    'idCardNo',
    'status',
    'hisUserCode',
    'mchisUserCode',
    'certId',
    'avatarImage',
    'signatureImage',
  };
  final changes = <String, Object?>{
    for (final entry in body.entries)
      if (allowed.contains(entry.key)) entry.key: entry.value,
  };
  for (final entry in changes.entries) {
    final v = entry.value;
    if (v != null && v is! String) {
      return _error(400, 40002, '字段 ${entry.key} 应为字符串');
    }
  }
  if (changes.isEmpty && (password == null || (password as String).trim().isEmpty) && roleIds == null) {
    return _error(400, 40001, '请至少修改一项用户信息');
  }

  final service = context.read<UserService>();
  try {
    final user = await service.update(
      id.trim(),
      changes,
      password: password as String?,
      roleIds: roleIds == null ? null : (roleIds as List).cast<String>(),
      roleDeptIds: roleIds == null ? null : _parseRoleDeptIds(roleDeptIds),
    );
    return Response.json(
      body: {
        'code': 0,
        'message': '修改成功',
        'data': {'user': user.toJson()},
      },
    );
  } on UserException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

/// 校验 roleDeptIds 形状：须为 {角色ID: [科室ID,...]} 映射，值为字符串
/// 数组；合法返回 null，否则返回错误信息。
String? _validateRoleDeptIds(Object? raw) {
  if (raw is! Map) return '适用科室映射应为对象（角色ID → 科室ID数组）';
  for (final entry in raw.entries) {
    final list = entry.value;
    if (list is! List || list.any((e) => e is! String)) {
      return '适用科室列表应为字符串数组';
    }
  }
  return null;
}

/// 解析已通过形状校验的 roleDeptIds 为服务层入参。
Map<String, List<String>> _parseRoleDeptIds(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries) entry.key as String: (entry.value as List).cast<String>(),
  };
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
