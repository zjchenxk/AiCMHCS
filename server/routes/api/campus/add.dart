import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/campus_service.dart';

/// POST /api/campus/add
/// 请求体：{hospId, code, name, address?, tel?}
/// （code 必填且全表唯一；name 必填且同医院内唯一）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final hospId = body['hospId'];
  final code = body['code'];
  final name = body['name'];
  if (hospId is! String || hospId.trim().isEmpty) {
    return _error(400, 40001, '所属医院不能为空');
  }
  if (code is! String || name is! String) {
    return _error(400, 40001, '院区代码、院区名称不能为空');
  }

  final service = context.read<CampusService>();
  try {
    final campus = await service.create(
      hospId: hospId,
      code: code,
      name: name,
      address: body['address'] as String?,
      tel: body['tel'] as String?,
    );
    return Response.json(
      body: {
        'code': 0,
        'message': '新增成功',
        'data': {'campus': campus.toJson()},
      },
    );
  } on CampusException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
