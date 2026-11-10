import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/menu_service.dart';

/// POST /api/menu/add
/// 请求体：{parentId?, itemCode, itemName, itemType, menuRoute?, menuIcon?}
/// （parentId 空为顶级项目；itemCode 必填且全表唯一；itemType 限
/// 1-模块/2-菜单/3-操作；类型为菜单时 menuRoute 必填）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final itemCode = body['itemCode'];
  final itemName = body['itemName'];
  final itemType = body['itemType'];
  final visible = body['visible'];

  if (itemCode is! String || itemCode.trim().isEmpty) {
    return _error(400, 40001, '项目编码不能为空');
  }
  if (itemName is! String || itemName.trim().isEmpty) {
    return _error(400, 40001, '项目名称不能为空');
  }
  if (itemType is! String || itemType.trim().isEmpty) {
    return _error(400, 40001, '项目类型不能为空');
  }
  if (visible is! String || visible.trim().isEmpty) {
    return _error(400, 40001, '是否显示不能为空');
  }
  final parentId = body['parentId'];
  if (parentId != null && parentId is! String) {
    return _error(400, 40002, '上级项目ID应为字符串');
  }
  final menuRoute = body['menuRoute'];
  if (menuRoute != null && menuRoute is! String) {
    return _error(400, 40002, '菜单路由应为字符串');
  }
  final menuIcon = body['menuIcon'];
  if (menuIcon != null && menuIcon is! String) {
    return _error(400, 40002, '菜单图标应为字符串');
  }

  final service = context.read<MenuService>();
  try {
    final menu = await service.create(
      parentId: parentId as String?,
      itemCode: itemCode,
      itemName: itemName,
      itemType: itemType,
      menuRoute: menuRoute as String?,
      menuIcon: menuIcon as String?,
      visible: visible,
    );
    return Response.json(
      body: {
        'code': 0,
        'message': '新增成功',
        'data': {'menu': menu.toJson()},
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
