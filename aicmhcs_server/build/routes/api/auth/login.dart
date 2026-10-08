import 'package:aicmhcs_server/services/auth_service.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/auth/login
/// 请求体：{"username": "...", "password": "..."}
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      statusCode: 405,
      body: const {
        'code': 40500,
        'message': '该接口仅支持 POST 请求',
        'data': null,
      },
    );
  }

  dynamic body;
  try {
    body = await context.request.json();
  } catch (_) {
    return _error(400, 40002, '请求体必须是合法的 JSON');
  }
  if (body is! Map<String, dynamic>) {
    return _error(400, 40002, '请求体格式错误，应为 JSON 对象');
  }

  final username = body['username'];
  final password = body['password'];
  if (username is! String || password is! String ||
      username.trim().isEmpty || password.isEmpty) {
    return _error(400, 40001, '用户名和密码不能为空');
  }

  final ip = context.request.headers['x-forwarded-for']
      ?.split(',')
      .first
      .trim();

  final auth = context.read<AuthService>();
  try {
    final session = await auth.login(username, password, ip: ip);
    return Response.json(
      body: {
        'code': 0,
        'message': '登录成功',
        'data': {
          'token': session.token,
          'tokenType': 'Bearer',
          'expiresIn': auth.sessionTtl.inSeconds,
          'user': session.user.toJson(),
        },
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
