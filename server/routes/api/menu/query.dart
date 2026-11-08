import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/menu_service.dart';

/// POST /api/menu/query
/// 请求体：{id} 查单个菜单项目详情；缺省查全部菜单项目（菜单规模
/// 有限，前端按 PARENT_ID 构建「模块→菜单→操作」树）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final id = body['id'];
  if (id != null && id is! String) {
    return _error(400, 40002, '菜单ID应为字符串');
  }

  final service = context.read<MenuService>();
  try {
    // id 优先：查单个详情
    final i = (id as String?)?.trim() ?? '';
    if (i.isNotEmpty) {
      final menu = await service.getById(i);
      return Response.json(
        body: {
          'code': 0,
          'message': 'ok',
          'data': {'menu': menu.toJson()},
        },
      );
    }

    final menus = await service.listAll();
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
