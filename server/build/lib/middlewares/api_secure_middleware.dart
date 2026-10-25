import 'dart:async';
import 'dart:convert';

import 'package:common/utils/security_util.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/utils/log_helper.dart';
import 'package:server/utils/log_sanitizer.dart';

/// /api/** 报文加解密中间件（等保通信保密性/完整性要求）。
///
/// **必须挂在叶子路由段**（如 routes/api/auth/、routes/api/admin-divisions/
/// 各自的 _middleware.dart），不能挂在会被路径穿越的段（如 routes/api/）：
/// dart_frog Router 对 mount 的内层路由不命中时会回退继续尝试下一个
/// mount，且重建 context 时丢弃原 shelf request context——body 流与
/// provider 都传不过去。若本中间件在路径穿越段执行，回退后在最终
/// 命中段再次执行时 body 已被消费（shelf 请求体只能读一次），非 GET
/// 请求会全部报「请求体必须是合法的加密信封 JSON」。
///
/// 白名单接口（登录、API 自描述索引）走明文；其余请求凭 Authorization
/// 中的 token 找到会话密钥，先解开请求体信封、把明文经 provider 注入
/// 管线交给下游路由（业务路由用 context.read<ApiBody>().json 取参），
/// 再把路由响应整体封入信封返回。无有效会话或解密失败时返回明文错误
/// （此时客户端没有可用密钥，无法解密错误响应）。
const _plaintextPaths = {'/api/auth/login', '/api'};

/// 请求留痕跳过的路径：日志上报接口自身（否则每条客户端日志都会
/// 再产生一条请求日志，形成放大）。
const _skipLogPaths = {'/api/logs'};

/// 构建加密中间件（各叶子路由段的 _middleware.dart 调用）。
Handler apiSecureMiddleware(Handler next) {
  return (context) async {
    if (_plaintextPaths.contains(context.request.uri.path)) {
      return next(context);
    }

    final authorization = context.request.headers['authorization'];
    final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
    if (token == null || token.isEmpty) {
      return _error(401, 40103, '缺少访问令牌（Authorization: Bearer <token>）');
    }

    final auth = context.read<AuthService>();
    final LoginSession session;
    try {
      session = await auth.verifySession(token);
    } on AuthException catch (e) {
      return _error(e.httpStatus, e.code, e.message);
    }

    // 入参解密：dart_frog 的 RequestContext 不支持替换请求体（无私有构造
    // 之外的入口），明文经 provider 注入，业务路由统一用
    // context.read<ApiBody>().json 取参（勿直接 request.json()，那是密文）。
    var ctx = context;
    Map<String, dynamic>? plainBody;
    if (context.request.method != HttpMethod.get) {
      try {
        final raw = await ctx.request.body();
        final plain = raw.isEmpty
            ? <String, dynamic>{}
            : await SecurePayload.open(
                session.sessionKey,
                jsonDecode(raw) as Map<String, dynamic>,
              );
        plainBody = plain;
        ctx = ctx.provide<ApiBody>(() => ApiBody(plain));
      } on SecurePayloadException catch (e) {
        return _error(400, 40002, '请求体解密失败：${e.message}');
      } catch (_) {
        return _error(400, 40002, '请求体必须是合法的加密信封 JSON');
      }
    }

    // 请求留痕（信息类）：LOG_NAME 记路由路径，LOG_CONTENT 记脱敏后的
    // 明文入参（GET 无解密体，记查询串）；fire-and-forget 不阻塞响应。
    // 登录与 /api 索引已在上方白名单分支早退，天然不留痕。
    if (!_skipLogPaths.contains(context.request.uri.path)) {
      final query = context.request.uri.query;
      unawaited(
        LogHelper.info(
          context.request.uri.path,
          content: plainBody != null ? encodeForLog(plainBody) : (query.isEmpty ? null : query),
          userId: session.user.id,
        ),
      );
    }

    final response = await next(ctx);

    // 出参加密：路由的 {code,message,data} 整体封入信封；
    // 非路由产生的响应（404/204 等框架级文本）保持明文原样返回。
    dynamic plainJson;
    try {
      plainJson = jsonDecode(await response.body());
    } catch (_) {
      return response;
    }
    if (plainJson is! Map<String, dynamic>) {
      return response;
    }
    try {
      final sealed = await SecurePayload.seal(session.sessionKey, plainJson);
      return Response.json(statusCode: response.statusCode, body: sealed);
    } catch (_) {
      return _error(500, 50000, '响应加密失败');
    }
  };
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
