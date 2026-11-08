import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/role_service.dart';

/// POST /api/role/add
/// 请求体：{hospId, roleCode, roleName, remark?}
/// （hospId 为登录用户所属医院；编码/名称必填且同医院内唯一）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final hospId = body['hospId'];
  final roleCode = body['roleCode'];
  final roleName = body['roleName'];
  if (hospId is! String || hospId.trim().isEmpty) {
    return _error(400, 40001, '所属医院不能为空');
  }
  if (roleCode is! String || roleName is! String) {
    return _error(400, 40001, '角色编码、角色名称不能为空');
  }

  final service = context.read<RoleService>();
  try {
    final role = await service.create(
      hospId: hospId,
      roleCode: roleCode,
      roleName: roleName,
      remark: body['remark'] as String?,
    );
    return Response.json(
      body: {
        'code': 0,
        'message': '新增成功',
        'data': {'role': role.toJson()},
      },
    );
  } on RoleException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
