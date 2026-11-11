import 'package:dart_frog/dart_frog.dart';
import 'package:server/services/menu_service.dart';

/// POST /api/menu/queryVisible
/// 请求体：查全部可见菜单项目（菜单规模有限，前端按 PARENT_ID 构建「模块→菜单→操作」树）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  final service = context.read<MenuService>();
  try {
    final menus = await service.listVisible();
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {
          'menus': menus.map((m) => m.toJson()).toList(),
        },
      },
    );
  } on MenuException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
