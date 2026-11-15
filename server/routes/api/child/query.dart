import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/child_service.dart';

/// POST /api/child/query
/// 请求体：{id} 查整档（child + ext + guardians）；缺省按
/// {name?, visitCardNo?, healthNo?} 检索本院档案（至少一个条件，返回
/// 前 20 条简要列表）。医院从令牌会话推导（不信任客户端上报）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;

  // 登录用户从令牌会话推导（verify 失败由加密中间件的会话校验前置拦截）。
  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能查询儿童档案');
  }

  final service = context.read<ChildService>();
  try {
    final id = (body['id'] as String?)?.trim() ?? '';
    if (id.isNotEmpty) {
      final (child, ext, guardians) = await service.load(id, hospId);
      return Response.json(
        body: {
          'code': 0,
          'message': 'ok',
          'data': {
            'child': child.toJson(),
            'ext': ext?.toJson(),
            'guardians': guardians.map((g) => g.toJson()).toList(),
          },
        },
      );
    }
    final children = await service.search(
      hospId: hospId,
      name: body['name']?.toString(),
      visitCardNo: body['visitCardNo']?.toString(),
      healthNo: body['healthNo']?.toString(),
    );
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {'children': children.map((c) => c.toJson()).toList()},
      },
    );
  } on ChildException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  } on AuthException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
