import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/menu_service.dart';

/// POST /api/auth/switchRole
/// 请求体：{"role": "<角色ID>"}（加密信封已由中间件解开）。
/// 校验目标角色属于当前登录用户并更新会话角色，随响应下发携带新
/// 角色 ID 的用户信息与该角色已授权的模块/菜单，主界面据此刷新
/// 顶部用户信息与侧边栏权限菜单。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  if (token == null || token.isEmpty) {
    return _error(401, 40103, '缺少访问令牌（Authorization: Bearer <token>）');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final role = body['role'];
  if (role is! String || role.trim().isEmpty) {
    return _error(400, 40001, '所选角色不能为空');
  }

  final auth = context.read<AuthService>();
  try {
    final session = await auth.switchRole(token, role);

    // 角色归属已在 switchRole 校验，随响应下发新角色的授权菜单
    // （ITEM_TYPE 1/2，操作类不下发），口径与登录响应一致。
    final menus = await context.read<MenuService>().listRoleAll(session.roleId);

    return Response.json(
      body: {
        'code': 0,
        'message': '切换成功',
        'data': {
          'user': session.user.copyWith(roleId: session.roleId).toJson(),
          'menus': menus.map((m) => m.toJson()).toList(),
        },
      },
    );
  } on AuthException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  } on MenuException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
