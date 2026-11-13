import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/dict_service.dart';

/// POST /api/dict/itemQuery
/// 请求体：{dictId}，返回该字典的全部数据项扁平列表（前端按显示顺序
/// 排序展示，默认项由 isDefault 标记）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final dictId = body['dictId'];
  if (dictId is! String || dictId.trim().isEmpty) {
    return _error(400, 40001, '字典ID不能为空');
  }

  final service = context.read<DictService>();
  try {
    final items = await service.listItems(dictId.trim());
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {'items': items.map((i) => i.toJson()).toList()},
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
