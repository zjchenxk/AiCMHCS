import 'package:dart_frog/dart_frog.dart';

Response onRequest(RequestContext context) {
  return Response.json(
    body: {
      'code': 0,
      'message': 'ok',
      'data': {
        'name': 'AiCMHCS API',
        'version': 'v1',
        'endpoints': [
          {'method': 'POST', 'path': '/api/auth/login', 'desc': '用户登录'},
          {'method': 'GET', 'path': '/api/auth/me', 'desc': '当前登录用户'},
          {'method': 'GET', 'path': '/health', 'desc': '健康检查（含数据库探活）'},
        ],
      },
    },
  );
}
