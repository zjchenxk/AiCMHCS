import 'package:server/database/engine/database_gateway.dart';

/// 操作日志服务：向 SYS_OPERATION_LOG 追加操作/请求/异常日志。
///
/// 日志写入为尽力而为语义（统一经 [server.utils.log_helper.LogHelper]
/// 吞错），不参与业务事务；USER_ID 由调用方从会话推导，不信任客户端
/// 上报的用户ID。
class OperationLogService {
  /// 构造函数：注入数据库网关。
  OperationLogService(this._db);

  final DatabaseGateway _db;

  /// 日志类别：信息（正常请求与业务留痕）。
  static const String typeInfo = '信息';

  /// 日志类别：警告。
  static const String typeWarn = '警告';

  /// 日志类别：错误（异常及堆栈）。
  static const String typeError = '错误';

  /// 合法日志类别集合（路由参数校验用）。
  static const List<String> logTypes = [typeInfo, typeWarn, typeError];

  /// LOG_NAME 截断长度（列宽 500 字节按字节计，ASCII 路径名取保守值）。
  static const int _maxNameLength = 240;

  /// LOG_CONTENT 截断长度：列本身是 TEXT（达梦 CLOB，容量 2G-1 字节），
  /// 但含中文的内容会被达梦网关改写为内联字面量拼进 SQL 文本
  /// （dpi_bind_param 仅支持 ASCII，见 dm_param_rewrite），上限实际
  /// 受单条 SQL 语句长度约束，故取保守值。
  static const int _maxContentLength = 4000;

  ///param logType: 日志类别（信息/警告/错误）
  ///param logName: 日志名称（方法全路径或请求路由路径）
  ///param userId: 用户ID（无会话的请求/异常可为 null）
  ///param logContent: 日志内容（脱敏后的入参/异常消息及堆栈，可空）
  Future<void> add({required String logType, required String logName, int? userId, String? logContent}) async {
    await _db.execute(
      'INSERT INTO SYS_OPERATION_LOG '
      '(USER_ID, LOG_TYPE, LOG_NAME, LOG_CONTENT, LOG_TIME) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        userId,
        logType,
        _clip(logName, _maxNameLength),
        _clip(logContent, _maxContentLength),
        formatTimestamp(DateTime.now()),
      ],
    );
  }

  /// 超长文本截断，尾部追加省略号标记截断痕迹。
  static String? _clip(String? text, int maxLength) {
    if (text == null || text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}…';
  }
}
