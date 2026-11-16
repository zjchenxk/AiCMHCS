/// 相对时间标签：拍照时间距现在——不足 1 个月显示「{d}天前」；不足
/// 1 年显示「{m}月前」；1 年及以上显示「{y}年{m}月前」。
///
/// 月份差按日历月计算（当月日期未到则减一月，与主界面实际年龄算法
/// 同口径）；不足一个月时的天数取自然日差。
String photoAgeLabel(DateTime time) {
  final now = DateTime.now();
  var months = (now.year - time.year) * 12 + now.month - time.month;
  if (now.day < time.day) months--;
  if (months < 0) months = 0;
  if (months < 1) {
    final days = now.difference(time).inDays;
    return '${days < 0 ? 0 : days}天前';
  }
  final years = months ~/ 12;
  final rest = months % 12;
  if (years < 1) {
    return '$months月前';
  }
  return rest > 0 ? '$years年$rest月前' : '$years年前';
}
