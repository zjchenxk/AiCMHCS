import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/admin_division_service.dart';

/// POST /api/adminDivisions/delete
/// 请求体：{code}，级联删除该区划及其全部下级。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final code = body['code'];
  if (code is! String || code.trim().isEmpty) {
    return _error(400, 40001, '行政区划代码不能为空');
  }

  final service = context.read<AdminDivisionService>();
  try {
    final deleted = await service.deleteSubtree(code.trim());
    return Response.json(
      body: {
        'code': 0,
        'message': '删除成功',
        'data': {'deleted': deleted},
      },
    );
  } on AdminDivisionException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
