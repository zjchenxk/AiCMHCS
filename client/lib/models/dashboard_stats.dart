/// 首页 Dashboard 统计数据模型。
///
/// 当前为客户端演示数据（未接后端统计接口），模型先行按协议风格定义：
/// 接通真实接口后随「月度统计」协议扩展 fromJson/toJson，届时迁往 common 包。
library;

/// 单月统计点：month 为 'yyyy-MM' 字符串，各计数为该月发生量（演示口径）。
class MonthPoint {
  /// 月份标识，'yyyy-MM'（如 '2026-11'）
  final String month;

  // ── 初筛板块 ──
  /// 初筛人数
  final int screened;

  /// 初筛异常人数
  final int screenAbnormal;

  // ── 复筛板块 ──
  /// 复筛人数
  final int reScreened;

  /// 复筛异常人数
  final int reScreenAbnormal;

  /// 复筛后复查人数
  final int reScreenRecheck;

  // ── 诊断板块 ──
  /// 诊断人数
  final int diagnosed;

  /// 确诊人数
  final int confirmed;

  /// 诊断后复查人数
  final int diagRecheck;

  const MonthPoint({
    required this.month,
    required this.screened,
    required this.screenAbnormal,
    required this.reScreened,
    required this.reScreenAbnormal,
    required this.reScreenRecheck,
    required this.diagnosed,
    required this.confirmed,
    required this.diagRecheck,
  });

  /// 区间内某取值器的求和（KPI 与图表切片共用）
  static int sumBy(List<MonthPoint> points, int Function(MonthPoint) pick) {
    var total = 0;
    for (final p in points) {
      total += pick(p);
    }
    return total;
  }
}

/// Dashboard 全量月度序列（演示数据窗口：回溯 N 个月，按月升序）
class DashboardSeries {
  final List<MonthPoint> months;

  const DashboardSeries({required this.months});
}
