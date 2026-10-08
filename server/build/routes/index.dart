import 'package:dart_frog/dart_frog.dart';

Response onRequest(RequestContext context) {
  return Response.json(
    body: {
      'code': 0,
      'message': 'ok',
      'data': {
        'name': '智慧儿童心理保健系统',
        'abbr': 'AiCMHCS',
        'version': '0.1.0',
        'backend': 'Dart Frog',
        'database': 'DM8（达梦）',
      },
    },
  );
}
