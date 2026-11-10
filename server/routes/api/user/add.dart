import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/user_service.dart';

/// POST /api/user/add
/// 请求体：{hospId, deptId, userCode, userName, password, userType?,
/// permissionLevel?, phone?, idCardNo?, hisUserCode?, mchisUserCode?,
/// certId?, signatureImage?, status?, roleIds?}
/// （hospId 为登录用户所属医院；挂载科室必填且须属于该医院；登录账号
/// 全局唯一；口令 6-32 位；roleIds 须属于该医院，可空）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final hospId = body['hospId'];
  final deptId = body['deptId'];
  final userCode = body['userCode'];
  final userName = body['userName'];
  final password = body['password'];
  if (hospId is! String || hospId.trim().isEmpty) {
    return _error(400, 40001, '所属医院不能为空');
  }
  if (deptId is! String || deptId.trim().isEmpty) {
    return _error(400, 40001, '挂载科室不能为空');
  }
  if (userCode is! String || userName is! String || password is! String) {
    return _error(400, 40001, '登录账号、姓名、密码不能为空');
  }
  for (final key in [
    'userType',
    'permissionLevel',
    'phone',
    'idCardNo',
    'hisUserCode',
    'mchisUserCode',
    'certId',
    'avatarImage',
    'signatureImage',
    'status',
  ]) {
    final v = body[key];
    if (v != null && v is! String) {
      return _error(400, 40002, '字段 $key 应为字符串');
    }
  }
  final roleIds = body['roleIds'];
  if (roleIds != null && (roleIds is! List || roleIds.any((e) => e is! String))) {
    return _error(400, 40002, '角色ID列表应为字符串数组');
  }

  final service = context.read<UserService>();
  try {
    final user = await service.create(
      hospId: hospId,
      deptId: deptId,
      userCode: userCode,
      userName: userName,
      password: password,
      userType: body['userType'] as String?,
      permissionLevel: body['permissionLevel'] as String?,
      phone: body['phone'] as String?,
      idCardNo: body['idCardNo'] as String?,
      hisUserCode: body['hisUserCode'] as String?,
      mchisUserCode: body['mchisUserCode'] as String?,
      certId: body['certId'] as String?,
      avatarImage: body['avatarImage'] as String?,
      signatureImage: body['signatureImage'] as String?,
      status: body['status'] as String?,
      roleIds: (roleIds as List?)?.cast<String>() ?? const [],
    );
    return Response.json(
      body: {
        'code': 0,
        'message': '新增成功',
        'data': {'user': user.toJson()},
      },
    );
  } on UserException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
