import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/dict_service.dart';

/// POST /api/dict/itemUpdate
/// 请求体：{id, itemCode?, itemValue?, displayOrder?}
/// （仅传本次要修改的字段；默认标记不经本接口修改，走 itemSetDefault）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final id = body['id'];
  if (id is! String || id.trim().isEmpty) {
    return _error(400, 40001, '数据项ID不能为空');
  }

  // 字段白名单透传（键与 JSON 契约一致，服务层再校验合法性）。
  const allowed = {'itemCode', 'itemValue', 'displayOrder'};
  final changes = {
    for (final e in body.entries)
      if (allowed.contains(e.key)) e.key: e.value?.toString(),
  };

  final service = context.read<DictService>();
  try {
    final item = await service.updateItem(id.trim(), changes);
    return Response.json(
      body: {
        'code': 0,
        'message': '保存成功',
        'data': {'item': item.toJson()},
      },
    );
  } on DictException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
