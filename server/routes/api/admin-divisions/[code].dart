import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/admin_division_service.dart';

/// /api/admin-divisions/[code]
/// - GET：详情 + 子树规模，data: {code, name, parentCode, subtreeCount}
/// - PUT：修改行政区划（body 的 code/name 均可选；改 code 时级联更新
///   全部下级父引用），data: {'division': {...}}
/// - DELETE：级联删除全部下级，data: {'deleted': 删除行数}
Future<Response> onRequest(RequestContext context, String code) async {
  final c = code.trim();
  if (c.isEmpty) {
    return _error(400, 40001, '行政区划代码不能为空');
  }

  final service = context.read<AdminDivisionService>();
  final method = context.request.method;
  if (method == HttpMethod.get) {
    return _detail(service, c);
  }
  if (method == HttpMethod.put) {
    return _update(context, service, c);
  }
  if (method == HttpMethod.delete) {
    return _delete(service, c);
  }
  return _error(405, 40500, '该接口仅支持 GET/PUT/DELETE 请求');
}

Future<Response> _detail(AdminDivisionService service, String code) async {
  try {
    final division = await service.getByCode(code);
    final count = await service.subtreeCount(code);
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {
          'code': division.code,
          'name': division.name,
          'parentCode': division.parentCode,
          'subtreeCount': count,
        },
      },
    );
  } on AdminDivisionException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Future<Response> _update(RequestContext context, AdminDivisionService service, String code) async {
  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final newCode = body['code'];
  final name = body['name'];
  if ((newCode == null || newCode.toString().trim().isEmpty) && (name == null || name.toString().trim().isEmpty)) {
    return _error(400, 40001, '行政区划代码和名称至少修改一项');
  }
  if (newCode != null && newCode is! String) {
    return _error(400, 40002, '行政区划代码应为字符串');
  }
  if (name != null && name is! String) {
    return _error(400, 40002, '行政区划名称应为字符串');
  }
  try {
    // 前置 is! 校验已保证二者为 String 或 null
    final division = await service.update(code, newCode: newCode as String?, newName: name as String?);
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

Future<Response> _delete(AdminDivisionService service, String code) async {
  try {
    final deleted = await service.deleteSubtree(code);
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
