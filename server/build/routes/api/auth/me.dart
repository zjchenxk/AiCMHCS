import 'package:server/services/auth_service.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/auth/me
/// 请求头：Authorization: Bearer <token>
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: 405,
      body: const {
        'code': 40500,
        'message': '该接口仅支持 GET 请求',
        'data': null,
      },
    );
  }

  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') == true
      ? authorization!.substring('Bearer '.length).trim()
      : null;
  if (token == null || token.isEmpty) {
    return _error(401, 40103, '缺少访问令牌（Authorization: Bearer <token>）');
  }

  final auth = context.read<AuthService>();
  try {
    final user = await auth.verify(token);
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': user.toJson(),
      },
    );
  } on AuthException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
      statusCode: status,
      body: {'code': code, 'message': message, 'data': null},
    );
