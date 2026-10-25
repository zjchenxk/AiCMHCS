import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/admin_division_service.dart';

/// POST /api/adminDivisions/update
/// 请求体：{code, newCode?, name?}（code 定位记录；newCode 改编码时
/// 级联更新全部下级父引用；至少修改一项）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final code = body['code'];
  final newCode = body['newCode'];
  final name = body['name'];
  if (code is! String || code.trim().isEmpty) {
    return _error(400, 40001, '行政区划代码不能为空');
  }
  if ((newCode == null || newCode.toString().trim().isEmpty) && (name == null || name.toString().trim().isEmpty)) {
    return _error(400, 40001, '行政区划代码和名称至少修改一项');
  }
  if (newCode != null && newCode is! String) {
    return _error(400, 40002, '新行政区划代码应为字符串');
  }
  if (name != null && name is! String) {
    return _error(400, 40002, '行政区划名称应为字符串');
  }

  final service = context.read<AdminDivisionService>();
  try {
    final division = await service.update(
      code.trim(),
      newCode: newCode as String?,
      newName: name as String?,
    );
    return Response.json(
      body: {
        'code': 0,
        'message': '修改成功',
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
