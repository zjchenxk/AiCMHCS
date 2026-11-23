import 'dart:math';

import 'package:client/main.dart';
import 'package:client/models/dashboard_stats.dart';
import 'package:client/services/time_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:material_ui/material_ui.dart';

/// Dashboard 板块标识：各板块时间段（起止月）独立筛选。
enum DashboardBoard {
  /// 板块一：数量统计（初筛异常 / 复筛异常 / 确诊 KPI 汇总）
  kpi,

  /// 板块二：初筛统计图
  screen,

  /// 板块三：复筛统计图
  reScreen,

  /// 板块四：诊断统计图
  diagnosis,
}

/// 首页 Dashboard ViewModel。
///
/// 当前统计数字为**客户端演示数据**（未接后端统计接口）：进入页面经
/// [loadDashboard] 以「当月」为终点回溯 [demoMonths] 个月生成确定性
/// 伪随机月度序列（种子取绝对月份键，重建/翻月不跳变），三张曲线图与
/// KPI 汇总共用同一份序列——KPI 数字即所选区间内对应曲线求和。
/// 接通真实接口后，仅需把演示生成替换为服务端拉取，板块区间筛选与
/// 派生逻辑不变。
class HomeViewModel extends ChangeNotifier {
  /// 构造函数：注入时间服务（缺省从服务定位器取，测试可覆写）。
  HomeViewModel({TimeService? timeService}) : _timeService = timeService ?? getIt<TimeService>();

  final TimeService _timeService;

  /// 演示数据窗口：回溯的月份数（默认筛选近 1 年，多留一倍供前翻）。
  static const int demoMonths = 24;

  DashboardSeries? _series;
  DashboardSeries? get series => _series;

  bool _loading = false;
  bool get loading => _loading;

  String? _errorMsg;
  String? get errorMsg => _errorMsg;

  void clearError() {
    _errorMsg = null;
    notifyListeners();
  }

  // 各板块起止月（'yyyy-MM'），loadDashboard 后必非空
  final Map<DashboardBoard, ({String from, String to})> _ranges = {};

  /// 指定板块的起止月区间。
  ({String from, String to}) rangeOf(DashboardBoard board) => _ranges[board]!;

  /// 数据窗口最早月（演示序列起点；未加载时 null）。
  String? get earliestMonth {
    final s = _series;
    if (s == null || s.months.isEmpty) return null;
    return s.months.first.month;
  }

  /// 数据窗口最晚月（即当前月；未加载时 null）。
  String? get latestMonth {
    final s = _series;
    if (s == null || s.months.isEmpty) return null;
    return s.months.last.month;
  }

  // ---------------- 加载 ----------------

  /// 加载 Dashboard 数据：当前为演示数据本地生成（同步完成，签名留
  /// Future 以便将来无缝替换为服务端拉取）。
  Future<bool> loadDashboard() async {
    if (_series != null) {
      return true;
    }
    _loading = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final now = _timeService.now();
      _series = DashboardSeries(months: _buildDemoMonths(now));
      _initDefaultRanges(now);
      return true;
    } catch (e, st) {
      LogHelper.error('client:HomeViewModel.loadDashboard', e, st);
      _errorMsg = '加载统计数据失败';
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 默认区间：近 12 个月（起 = 当月前推 11 个月，止 = 当月）。
  void _initDefaultRanges(DateTime now) {
    final to = monthKey(now);
    final from = monthKey(DateTime(now.year, now.month - 11));
    for (final board in DashboardBoard.values) {
      _ranges[board] = (from: from, to: to);
    }
  }

  // ---------------- 区间筛选 ----------------

  /// 设置板块起止月。起晚于止返回 false（不生效）；超出数据窗口部分
  /// 截断到窗口边界。
  bool setRange(DashboardBoard board, String from, String to) {
    final series = _series;
    if (series == null || series.months.isEmpty) {
      return false;
    }
    if (from.compareTo(to) > 0) {
      return false;
    }
    final first = series.months.first.month;
    final last = series.months.last.month;
    final f = from.compareTo(first) < 0 ? first : from;
    final t = to.compareTo(last) > 0 ? last : to;
    _ranges[board] = (from: f, to: t);
    notifyListeners();
    return true;
  }

  /// 指定板块区间内的月度切片（升序）。
  List<MonthPoint> slice(DashboardBoard board) {
    final series = _series;
    if (series == null || series.months.isEmpty) {
      return const [];
    }
    final range = _ranges[board]!;
    return series.months.where((p) => p.month.compareTo(range.from) >= 0 && p.month.compareTo(range.to) <= 0).toList();
  }

  // ---------------- KPI 派生（板块一：区间求和） ----------------

  /// 初筛异常儿童数量
  int get kpiScreenAbnormalCount => MonthPoint.sumBy(slice(DashboardBoard.kpi), (p) => p.screenAbnormal);

  /// 复筛异常儿童数量
  int get kpiReScreenAbnormalCount => MonthPoint.sumBy(slice(DashboardBoard.kpi), (p) => p.reScreenAbnormal);

  /// 确诊儿童数量
  int get kpiConfirmedCount => MonthPoint.sumBy(slice(DashboardBoard.kpi), (p) => p.confirmed);

  // ---------------- 演示数据生成 ----------------

  /// 以 [now] 所在月为终点回溯 [demoMonths] 个月生成月度序列（升序）。
  /// 随机种子取「绝对月份键（年*12+月）」，同一月份在任何窗口位置下
  /// 取值一致——重建 ViewModel、翻看更早月份都不会跳变。
  List<MonthPoint> _buildDemoMonths(DateTime now) {
    final points = <MonthPoint>[];
    for (var i = demoMonths - 1; i >= 0; i--) {
      final monthDate = DateTime(now.year, now.month - i);
      final key = monthKey(monthDate);
      final seed = monthDate.year * 12 + monthDate.month - 1;
      final rng = Random(seed);

      // 数值链路保持业务上说得通：初筛 → 异常（8%~19%）→ 复筛人数
      // （初筛异常的 60%~90%）→ 复筛异常（复筛人数的 20%~39%）→
      // 复查（复筛异常的 30%~69%）；诊断（复筛异常的 60%~90%）→
      // 确诊（诊断的 50%~84%）→ 诊断复查（确诊的 20%~59%）。
      final screened = 60 + rng.nextInt(140);
      final screenAbnormal = _ratio(screened, 8 + rng.nextInt(12));
      final reScreened = _ratio(screenAbnormal, 60 + rng.nextInt(31));
      final reScreenAbnormal = _ratio(reScreened, 20 + rng.nextInt(20));
      final reScreenRecheck = _ratio(reScreenAbnormal, 30 + rng.nextInt(40));
      final diagnosed = _ratio(reScreenAbnormal, 60 + rng.nextInt(31));
      final confirmed = _ratio(diagnosed, 50 + rng.nextInt(35));
      final diagRecheck = _ratio(confirmed, 20 + rng.nextInt(40));

      points.add(
        MonthPoint(
          month: key,
          screened: screened,
          screenAbnormal: screenAbnormal,
          reScreened: reScreened,
          reScreenAbnormal: reScreenAbnormal,
          reScreenRecheck: reScreenRecheck,
          diagnosed: diagnosed,
          confirmed: confirmed,
          diagRecheck: diagRecheck,
        ),
      );
    }
    return points;
  }

  /// 百分比取整：base 的 [percent]%（四舍五入），并保证结果非负。
  static int _ratio(int base, int percent) => (base * percent / 100).round();
}

/// 月份标识（'yyyy-MM'，零填充——字符串序即时间序，可直接比较）。
String monthKey(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-${two(date.month)}';
}
