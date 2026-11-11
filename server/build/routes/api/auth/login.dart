import 'dart:async';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/utils/log_helper.dart';

/// POST /api/auth/login
/// 请求体：{"username": "...", "password": "...", "role": "..."}
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

  final userCode = body['usercode'];
  final password = body['password'];
  final role = body['role'];
  if (userCode is! String || password is! String || role is! String || userCode.trim().isEmpty || password.isEmpty || role.trim().isEmpty) {
    return _error(400, 40001, '用户名、密码和角色不能为空');
  }

  final ip = _clientIp(context);

  unawaited(
    LogHelper.info('server:routes/api/auth/login', content: '用户 $userCode 尝试登录，角色 $role，IP $ip'),
  );

  final auth = context.read<AuthService>();
  try {
    final session = await auth.login(userCode, password, role, ip: ip);
    return Response.json(
      body: {
        'code': 0,
        'message': '登录成功',
        'data': {
          'token': session.token,
          'sessionKey': session.sessionKey,
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

/// 解析客户端 IP：优先取反向代理透传的 X-Forwarded-For（多级取第一个），
/// 无该头时回退 TCP 连接对端真实地址（本地/内网直连场景——浏览器与 http
/// 客户端不会自行携带 X-Forwarded-For）。
///returns: 客户端 IP，两者都取不到（如框架测试请求无连接信息）时为 null
String? _clientIp(RequestContext context) {
  final forwarded = context.request.headers['x-forwarded-for']?.split(',').first.trim();
  if (forwarded != null && forwarded.isNotEmpty) {
    return forwarded;
  }
  try {
    return context.request.connectionInfo.remoteAddress.address;
  } catch (_) {
    return null;
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
