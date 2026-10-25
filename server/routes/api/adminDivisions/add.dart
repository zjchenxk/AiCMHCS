import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/admin_division_service.dart';

/// POST /api/adminDivisions/add
/// 请求体：{code, name, parentCode?}（parentCode 缺省为省级）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final code = body['code'];
  final name = body['name'];
  final parentCode = body['parentCode'];
  if (code is! String || name is! String || code.trim().isEmpty) {
    return _error(400, 40001, '行政区划代码和名称不能为空');
  }
  if (parentCode != null && parentCode is! String) {
    return _error(400, 40002, '上级行政区划代码应为字符串');
  }

  final service = context.read<AdminDivisionService>();
  try {
    final division = await service.create(
      code: code,
      name: name,
      parentCode: parentCode as String?,
    );
    return Response.json(
      body: {
        'code': 0,
        'message': '新增成功',
        'data': {'division': division.toJson()},
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
