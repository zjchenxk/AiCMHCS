import 'package:dart_frog/dart_frog.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/menu_service.dart';

/// POST /api/menu/operations
/// 请求体：{}（无需入参）。
/// 返回当前登录角色已授权的操作类项目（ITEM_TYPE=3）ITEM_CODE 集合，
/// 供功能页做按钮级权限控制；角色从令牌会话推导（不信任客户端上报），
/// 切换角色后会话角色随登录会话更新，重进页面即取到新角色的操作权限。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 登录角色从令牌会话推导（verify 失败由加密中间件的会话校验前置拦截）。
  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final session = token == null ? null : await context.read<AuthService>().verifySession(token);
  final roleId = session?.roleId.trim() ?? '';
  if (roleId.isEmpty) {
    return _error(400, 40001, '当前登录会话无角色信息，不能查询操作权限');
  }

  final service = context.read<MenuService>();
  try {
    final codes = await service.listRoleOperationCodes(roleId);
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {'operationCodes': codes.toList()},
      },
    );
  } on MenuException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  } on AuthException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
