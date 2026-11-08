import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/department_service.dart';

/// POST /api/department/query
/// 请求体：{id} 查单个科室详情；{hospId} 查指定医院下的科室列表；
/// 缺省查全部科室（科室规模有限，前端按医院分组建树）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final id = body['id'];
  if (id != null && id is! String) {
    return _error(400, 40002, '科室ID应为字符串');
  }
  final hospId = body['hospId'];
  if (hospId != null && hospId is! String) {
    return _error(400, 40002, '医院ID应为字符串');
  }

  final service = context.read<DepartmentService>();
  try {
    // id 优先：查单个详情
    final i = (id as String?)?.trim() ?? '';
    if (i.isNotEmpty) {
      final department = await service.getById(i);
      return Response.json(
        body: {
          'code': 0,
          'message': 'ok',
          'data': {'department': department.toJson()},
        },
      );
    }

    // hospId：按医院过滤；缺省全量
    final departments = await service.listAll();
    final h = (hospId as String?)?.trim() ?? '';
    final filtered = h.isEmpty ? departments : departments.where((d) => d.hospId == h).toList();
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {
          'departments': filtered.map((d) => d.toJson()).toList(),
        },
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
