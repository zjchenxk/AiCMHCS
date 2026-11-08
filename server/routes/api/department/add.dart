import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/department_service.dart';

/// POST /api/department/add
/// 请求体：{hospId, campusId?, parentId?, code, name, address?, tel?}
/// （挂载目标三选一：parentId 挂上级科室、campusId 挂院区、均空挂医院
/// ——医院已设置院区时须挂院区下；code 必填且全表唯一；name 必填且
/// 同挂载点内唯一）。
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
    return _error(400, 40001, '科室代码、科室名称不能为空');
  }
  final campusId = body['campusId'];
  if (campusId != null && campusId is! String) {
    return _error(400, 40002, '院区ID应为字符串');
  }
  final parentId = body['parentId'];
  if (parentId != null && parentId is! String) {
    return _error(400, 40002, '上级科室ID应为字符串');
  }

  final service = context.read<DepartmentService>();
  try {
    final department = await service.create(
      hospId: hospId,
      campusId: campusId as String?,
      parentId: parentId as String?,
      code: code,
      name: name,
      address: body['address'] as String?,
      tel: body['tel'] as String?,
    );
    return Response.json(
      body: {
        'code': 0,
        'message': '新增成功',
        'data': {'department': department.toJson()},
      },
    );
  } on DepartmentException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
