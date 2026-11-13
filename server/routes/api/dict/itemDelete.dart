import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/dict_service.dart';

/// POST /api/dict/itemDelete
/// 请求体：{id}，删除单个数据项。
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

  final service = context.read<DictService>();
  try {
    final deleted = await service.deleteItem(id.trim());
    return Response.json(
      body: {
        'code': 0,
        'message': '删除成功',
        'data': {'deleted': deleted},
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
