import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/user_service.dart';

/// POST /api/user/query
/// 请求体：{id} 查单个用户详情；{hospId} 查指定医院下的用户列表
/// （用户管理页归属登录用户所属医院，客户端传 loginUser.hospId）。
/// 每个用户携带拥有的角色 ID 列表（roleIds，前端回显免二次请求）；
/// 手机号 / 身份证号经 FieldCipher 解密为明文下发，传输由信封保护。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final id = body['id'];
  if (id != null && id is! String) {
    return _error(400, 40002, '用户ID应为字符串');
  }
  final hospId = body['hospId'];
  if (hospId != null && hospId is! String) {
    return _error(400, 40002, '医院ID应为字符串');
  }

  final service = context.read<UserService>();
  try {
    // id 优先：查单个详情
    final i = (id as String?)?.trim() ?? '';
    if (i.isNotEmpty) {
      final user = await service.getById(i);
      return Response.json(
        body: {
          'code': 0,
          'message': 'ok',
          'data': {'user': user.toJson()},
        },
      );
    }

    // hospId：按医院过滤（空则视为参数缺失，明确报错而非全表返回——
    // 用户按医院隔离，跨院全量列表无业务意义）
    final h = (hospId as String?)?.trim() ?? '';
    if (h.isEmpty) {
      return _error(400, 40001, '医院ID不能为空');
    }
    final users = await service.listByHospital(h);
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {
          'users': users.map((u) => u.toJson()).toList(),
        },
      },
    );
  } on UserException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
