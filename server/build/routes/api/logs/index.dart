import 'dart:async';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/operation_log_service.dart';
import 'package:server/utils/log_helper.dart';

/// POST /api/logs：客户端操作日志上报（client 端 LogHelper 的落库通道）。
/// 请求体 {logType, logName, logContent?}；USER_ID 由服务端从令牌会话
/// 推导，不信任客户端上报的用户ID；data 固定为 {}（客户端 BaseService
/// 会把 data 强转为 Map，不能为 null）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  if (token == null || token.isEmpty) {
    return _error(401, 40103, '缺少访问令牌（Authorization: Bearer <token>）');
  }
  final auth = context.read<AuthService>();
  final int userId;
  try {
    userId = (await auth.verify(token)).id;
  } on AuthException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final logType = body['logType'];
  final logName = body['logName'];
  final logContent = body['logContent'];
  if (logType is! String || !OperationLogService.logTypes.contains(logType)) {
    return _error(400, 40002, '日志类别必须为：信息/警告/错误');
  }
  if (logName is! String || logName.trim().isEmpty) {
    return _error(400, 40001, '日志名称不能为空');
  }
  if (logContent != null && logContent is! String) {
    return _error(400, 40002, '日志内容应为字符串');
  }

  try {
    await context.read<OperationLogService>().add(
      userId: userId,
      logType: logType,
      logName: logName,
      logContent: logContent as String?,
    );
    return Response.json(
      body: {'code': 0, 'message': 'ok', 'data': <String, dynamic>{}},
    );
  } catch (e, s) {
    // 显式上报接口如实反馈失败（客户端 LogService 会静默吞掉）。
    unawaited(
      LogHelper.error('server:routes/api/logs 上报落库', e, s, userId: userId),
    );
    return _error(500, 50000, '日志写入失败');
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
