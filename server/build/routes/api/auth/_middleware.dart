import 'package:dart_frog/dart_frog.dart';
import 'package:server/middlewares/api_secure_middleware.dart';

/// /api/auth/** 报文加解密与会话校验（登录接口在白名单内走明文）。
/// 中间件逻辑见 apiSecureMiddleware（须挂叶子路由段，原因见其文档）。
Handler middleware(Handler next) => apiSecureMiddleware(next);
