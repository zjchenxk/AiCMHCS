import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/role_service.dart';

/// POST /api/role/query
/// 请求体：{id} 查单个角色详情；{hospId} 查指定医院下的角色列表
/// （角色管理页归属登录用户所属医院，客户端传 loginUser.hospId）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final id = body['id'];
  if (id != null && id is! String) {
    return _error(400, 40002, '角色ID应为字符串');
  }
  final hospId = body['hospId'];
  if (hospId != null && hospId is! String) {
    return _error(400, 40002, '医院ID应为字符串');
  }

  final service = context.read<RoleService>();
  try {
    // id 优先：查单个详情
    final i = (id as String?)?.trim() ?? '';
    if (i.isNotEmpty) {
      final role = await service.getById(i);
      return Response.json(
        body: {
          'code': 0,
          'message': 'ok',
          'data': {'role': role.toJson()},
        },
      );
    }

    // hospId：按医院过滤（空则视为参数缺失，明确报错而非全表返回——
    // 角色按医院隔离，跨院全量列表无业务意义）
    final h = (hospId as String?)?.trim() ?? '';
    if (h.isEmpty) {
      return _error(400, 40001, '医院ID不能为空');
    }
    final roles = await service.listByHospital(h);
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {
          'roles': roles.map((r) => r.toJson()).toList(),
        },
      },
    );
  } on RoleException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
