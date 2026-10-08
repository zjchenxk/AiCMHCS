import 'package:dart_frog/dart_frog.dart';

/// 全局中间件：CORS（Flutter Web 跨域调用）+ 统一异常兜底。
const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'Access-Control-Allow-Headers':
      'Content-Type, Authorization, X-Requested-With',
  'Access-Control-Max-Age': '86400',
};

Handler middleware(Handler next) {
  return (context) async {
    if (context.request.method == HttpMethod.options) {
      return Response(statusCode: 204, headers: _corsHeaders);
    }
    Response response;
    try {
      response = await next(context);
    } catch (error, stackTrace) {
      print('[AiCMHCS] 未处理异常: $error\n$stackTrace');
      response = Response.json(
        statusCode: 500,
        body: const {
          'code': 50000,
          'message': '服务器内部错误',
          'data': null,
        },
      );
    }
    return response.copyWith(headers: _corsHeaders);
  };
}
