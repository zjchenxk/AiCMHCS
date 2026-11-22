import 'package:client/main.dart';
import 'package:client/services/time_service.dart';
import 'package:client/utils/age_util.dart';

/// 相对时间标签：拍照时间距现在——不足 1 个月显示「{d}天前」；不足
/// 1 年显示「{m}月前」；1 年及以上显示「{y}年{m}月前」。
///
/// 「现在」取全局时间服务（TimeService.now，服务端口径，避免终端本地
/// 时钟不一致）；月份差按日历月计算（当月日期未到则减一月，与主界面
/// 实际年龄算法同口径）；不足一个月时的天数取自然日差。
///param time: 拍照时间（入库时间，服务端口径）
///param now: 当前时间（测试注入用；缺省取全局时间服务）
String photoAgeLabel(DateTime time, {DateTime? now}) {
  final current = now ?? getIt<TimeService>().now();
  var months = (current.year - time.year) * 12 + current.month - time.month;
  if (current.day < time.day) months--;
  if (months < 0) months = 0;
  if (months < 1) {
    final days = current.difference(time).inDays;
    return '${days < 0 ? 0 : days}天前';
  }
  final years = months ~/ 12;
  final rest = months % 12;
  if (years < 1) {
    return '$months月前';
  }
  return rest > 0 ? '$years年$rest月前' : '$years年前';
}

/// 拍摄年龄：照片拍摄时刻距今的岁/月/天复合文本（如「3岁2个月15天」
/// 「28天」），与儿童实足年龄同口径（日历对日、不做 30 天/月近似，见
/// [AgeUtil.formatAgeYmd]）；拍摄时刻晚于当前（时钟偏差）返回空串，由
/// 调用方回退显示原始拍摄时间。
///param time: 拍照时间（入库时间，服务端口径）
///param now: 当前时间（测试注入用；缺省取全局时间服务）
///returns: 拍摄年龄文本
String photoTakenAgeLabel(DateTime time, {DateTime? now}) {
  final current = now ?? getIt<TimeService>().now();
  return AgeUtil.formatAgeYmd(time, current);
}
