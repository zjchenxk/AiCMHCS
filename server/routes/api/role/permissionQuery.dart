import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/role_service.dart';

/// POST /api/role/permissionQuery
/// 请求体：{roleId}，查询该角色已授权的菜单 ID 列表。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final roleId = body['roleId'];
  if (roleId is! String || roleId.trim().isEmpty) {
    return _error(400, 40001, '角色ID不能为空');
  }

  final service = context.read<RoleService>();
  try {
    final menuIds = await service.listPermissionMenuIds(roleId.trim());
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {'menuIds': menuIds},
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
