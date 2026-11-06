import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/campus_service.dart';

/// POST /api/campus/query
/// 请求体：{id} 查单个院区详情；{hospId} 查指定医院下的院区列表；
/// 缺省查全部院区（院区规模有限，前端按医院分组）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final id = body['id'];
  if (id != null && id is! String) {
    return _error(400, 40002, '院区ID应为字符串');
  }
  final hospId = body['hospId'];
  if (hospId != null && hospId is! String) {
    return _error(400, 40002, '医院ID应为字符串');
  }

  final service = context.read<CampusService>();
  try {
    // id 优先：查单个详情
    final i = (id as String?)?.trim() ?? '';
    if (i.isNotEmpty) {
      final campus = await service.getById(i);
      return Response.json(
        body: {
          'code': 0,
          'message': 'ok',
          'data': {'campus': campus.toJson()},
        },
      );
    }

    // hospId：按医院过滤；缺省全量
    final campuses = await service.listAll();
    final h = (hospId as String?)?.trim() ?? '';
    final filtered = h.isEmpty ? campuses : campuses.where((c) => c.hospId == h).toList();
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {
          'campuses': filtered.map((c) => c.toJson()).toList(),
        },
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
