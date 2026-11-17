import 'package:dart_frog/dart_frog.dart';
import 'package:server/database/engine/database_gateway.dart';

/// GET /api/time
/// 全局时间服务：返回服务器当前时间（毫秒级 Unix 时间戳 + 格式化文本），
/// 供客户端时钟校准（客户端采集时间统一以服务端为准，避免各终端本地
/// 时钟不一致）。
///
/// 明文白名单接口（见 api_secure_middleware 的 _plaintextPaths）：时间
/// 非敏感信息，且客户端须在登录前即可校准；刻意不读数据库、不留请求
/// 日志，保证极轻量（客户端会周期性轮询）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(statusCode: 405, body: {'code': 40500, 'message': '该接口仅支持 GET 请求', 'data': null});
  }
  final now = DateTime.now();
  return Response.json(
    body: {
      'code': 0,
      'message': 'ok',
      'data': {
        // 毫秒级 Unix 时间戳：客户端时钟偏移推算依据（走秒换算受本地
        // 时区影响，直接用时间戳最稳）
        'epochMs': now.millisecondsSinceEpoch,
        // 格式化文本（formatTimestamp 同口径，便于调试对账）
        'serverTime': formatTimestamp(now),
      },
    },
  );
}
