import 'package:client/main.dart';
import 'package:client/services/base/base_service.dart';

/// 操作日志上报服务：把客户端日志经 POST /api/logs 落库（USER_ID 由
/// 服务端从令牌会话推导，客户端不上报）。上报为尽力而为语义——失败
/// 返回 false 静默，绝不影响业务流程；调用方一般经
/// utils/log_helper.dart 的 LogHelper 门面使用。
class LogService {
  ///param logType: 日志类别（信息/警告/错误）
  ///param logName: 日志名称（client:类名.方法名）
  ///param logContent: 日志内容（异常消息及堆栈等，可空）
  ///returns: 是否上报成功
  Future<bool> addLog(String logType, String logName, String? logContent) async {
    try {
      await getIt<BaseService>().post(
        '/api/logs',
        {
          'logType': logType,
          'logName': logName,
          'logContent': ?logContent,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
