import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/role_service.dart';

/// POST /api/role/permissionSave
/// 请求体：{roleId, menuIds: [菜单ID...]}，全量保存角色的菜单权限
/// （先清空既有关联再插入，空列表即清空权限）。
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
  final menuIds = body['menuIds'];
  if (menuIds == null) {
    return _error(400, 40001, '菜单ID列表不能为空（空权限传空列表）');
  }
  if (menuIds is! List || menuIds.any((e) => e is! String)) {
    return _error(400, 40002, '菜单ID列表应为字符串数组');
  }

  final service = context.read<RoleService>();
  try {
    final saved = await service.savePermissions(
      roleId.trim(),
      menuIds.cast<String>(),
    );
    return Response.json(
      body: {
        'code': 0,
        'message': '保存成功',
        'data': {'saved': saved},
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
