import 'package:client/main.dart';
import 'package:client/services/log_service.dart';
import 'package:material_ui/material_ui.dart';

/// 操作日志静态门面：任意位置一行调用上报日志（经 LogService 走
/// POST /api/logs 落库，表 SYS_OPERATION_LOG）。
///
/// 全部方法尽力而为：未登录（无会话，含启动早期）直接丢弃、发送失败
/// 静默（debugPrint），绝不抛出、上报失败不再触发上报（防递归）。
///
/// LOG_NAME 命名约定：client:类名.方法名，如
/// client:AdminDivisionManagementViewModel.loadRoots。
class LogHelper {
  LogHelper._();

  ///param name: 日志名称
  ///param content: 日志内容
  static Future<void> info(String name, {String? content}) => _send('信息', name, content);

  /// 警告日志，参数同 [info]。
  static Future<void> warn(String name, {String? content}) => _send('警告', name, content);

  ///param name: 日志名称（client:类名.方法名）
  ///param error: 异常对象
  ///param stackTrace: 跟踪堆栈（与异常消息拼接上报）
  static Future<void> error(String name, Object? error, [StackTrace? stackTrace]) {
    return _send('错误', name, stackTrace == null ? '$error' : '$error\n$stackTrace');
  }

  static Future<void> _send(String logType, String logName, String? logContent) async {
    try {
      // 未登录无会话可上报，直接丢弃（token 为 late 变量，启动早期
      // 读取可能抛 LateInitializationError，一并吞掉）。
      if (token == null) return;
      await getIt<LogService>().addLog(logType, logName, logContent);
    } catch (e) {
      debugPrint('[LogHelper] 日志上报失败: $e');
    }
  }
}
