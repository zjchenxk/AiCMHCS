import 'dart:io';

import 'package:server/services/operation_log_service.dart';

/// 操作日志静态门面：中间件、服务层深处等任意位置一行调用写日志，
/// 无需携带 RequestContext。
///
/// main.dart 启动时经 [service] 注入服务；此后所有方法均为尽力而为：
/// 立即返回、不抛异常、写入失败仅输出 stderr——日志写入失败不得再
/// 触发日志（防递归），也不得影响业务响应。
///
/// LOG_NAME 命名约定：方法用 `server:类名.方法名`，请求兜底用
/// `server:METHOD /路由路径`，请求留痕直接用路由路径。
class LogHelper {
  LogHelper._();

  static OperationLogService? _service;

  /// 已注入的操作日志服务（未注入时为 null，写入调用直接跳过）。
  static OperationLogService? get service => _service;

  /// 操作日志服务（main.dart 启动时注入一次）。
  static set service(OperationLogService value) {
    _service = value;
  }

  ///param name: 日志名称
  ///param content: 日志内容
  ///param userId: 用户ID（无会话场景可为 null）
  ///returns: 写入完成的 Future（不抛异常，调用方可不等待）
  static Future<void> info(String name, {String? content, int? userId}) => _write(OperationLogService.typeInfo, name, content, userId);

  /// 警告日志，参数同 [info]。
  static Future<void> warn(String name, {String? content, int? userId}) => _write(OperationLogService.typeWarn, name, content, userId);

  ///param name: 日志名称
  ///param error: 异常对象（toString 落库）
  ///param stackTrace: 跟踪堆栈（与异常消息拼接落库）
  ///param content: 附加内容（置于异常消息之前）
  ///param userId: 用户ID
  ///returns: 写入完成的 Future（不抛异常，调用方可不等待）
  static Future<void> error(String name, Object? error, StackTrace? stackTrace, {String? content, int? userId}) {
    final parts = [
      if (content != null && content.isNotEmpty) content,
      if (error != null) '$error',
      if (stackTrace != null) '$stackTrace',
    ];
    return _write(
      OperationLogService.typeError,
      name,
      parts.isEmpty ? null : parts.join('\n'),
      userId,
    );
  }

  static Future<void> _write(String logType, String logName, String? logContent, int? userId) async {
    final operationLogs = _service;
    if (operationLogs == null) return;
    try {
      await operationLogs.add(
        userId: userId,
        logType: logType,
        logName: logName,
        logContent: logContent,
      );
    } catch (e, s) {
      stderr.writeln('[操作日志写入失败] $e\n$s');
    }
  }
}
