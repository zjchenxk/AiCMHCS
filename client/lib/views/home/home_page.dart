import 'dart:math';

import 'package:client/models/dashboard_stats.dart';
import 'package:client/view_models/home/home_view_model.dart';
import 'package:client/views/base/base_page.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:client/widgets/month_picker_dialog.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 曲线定义：label 图例与提示名称、color 主题色、pick 该曲线在月度点的取值。
typedef _SeriesDef = ({String label, Color color, int Function(MonthPoint) pick});

/// 首页 Dashboard：板块一数量统计（初筛异常/复筛异常/确诊 KPI 汇总）与
/// 板块二/三/四 初筛/复筛/诊断月度趋势曲线图，各板块时间段（起止月）
/// 独立筛选。统计数字当前为客户端演示数据（见 HomeViewModel），未接后端。
class HomePage extends BasePage {
  const HomePage({super.key, required super.loginUser, required super.child});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// dispose 中不能再用 context 取 Provider，保存实例引用供移除监听
  late final HomeViewModel _viewModel;

  @override
  void initState() {
    super.initState();

    // 通过 Provider 获取全局注入的实例（不再自己 new）
    _viewModel = context.read<HomeViewModel>();
    // 仅首次进入加载：切页回来保留已加载的演示数据与各板块区间状态
    // （延迟到首帧后发起，避免 build 期间同步 notifyListeners）
    if (_viewModel.series == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _viewModel.loadDashboard();
      });
    }

    // 监听 errorMsg 变化，用 SnackBar 提示错误
    _viewModel.addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    // 注意：实例来自 Provider 全局注入，这里只移除监听，不要 viewModel.dispose()
    _viewModel.removeListener(_onViewModelChanged);
    super.dispose();
  }

  void _onViewModelChanged() {
    if (!mounted) return;

    final ThemeData theme = Theme.of(context);

    if (_viewModel.errorMsg != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _viewModel.errorMsg!,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onError),
          ),
          backgroundColor: theme.colorScheme.error,
          behavior: SnackBarBehavior.floating, // 悬浮式，不遮挡底部布局
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: '关闭',
            textColor: theme.colorScheme.onPrimary,
            onPressed: _viewModel.clearError,
          ),
        ),
      );
      // 提示后立即清空，避免同一错误重复弹出
      _viewModel.clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 使用 watch 监听变化，VM notifyListeners 后自动刷新
    final viewModel = context.watch<HomeViewModel>();
    final theme = Theme.of(context);

    if (viewModel.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final series = viewModel.series;
    if (series == null || series.months.isEmpty) {
      return Center(
        child: Text('暂无统计数据', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildKpiBoard(theme, viewModel),
          const SizedBox(height: 16),
          _buildTrendBoard(theme, viewModel, DashboardBoard.screen, '初筛统计', _screenSeries(theme)),
          const SizedBox(height: 16),
          _buildTrendBoard(theme, viewModel, DashboardBoard.reScreen, '复筛统计', _reScreenSeries(theme)),
          const SizedBox(height: 16),
          _buildTrendBoard(theme, viewModel, DashboardBoard.diagnosis, '诊断统计', _diagnosisSeries(theme)),
        ],
      ),
    );
  }

  // ---------------- 板块一：数量统计（KPI 汇总） ----------------

  Widget _buildKpiBoard(ThemeData theme, HomeViewModel viewModel) {
    return GlassPanel(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _boardHeader(theme, viewModel, DashboardBoard.kpi, '数量统计'),
            const SizedBox(height: 16),
            _buildKpiCards(theme, viewModel),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCards(ThemeData theme, HomeViewModel viewModel) {
    final cards = [
      ('初筛异常儿童数量', viewModel.kpiScreenAbnormalCount),
      ('复筛异常儿童数量', viewModel.kpiReScreenAbnormalCount),
      ('确诊儿童数量', viewModel.kpiConfirmedCount),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 560;
        final children = [for (final (label, value) in cards) _kpiCard(theme, label, value)];
        if (!horizontal) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final child in children) ...[child, const SizedBox(height: 12)],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[Expanded(child: children[i]), if (i < children.length - 1) const SizedBox(width: 12)],
          ],
        );
      },
    );
  }

  Widget _kpiCard(ThemeData theme, String label, int value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // 层级靠色彩与透明度区分（扁平化），不用阴影
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.65))),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: theme.textTheme.headlineMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ---------------- 板块二/三/四：月度趋势曲线图 ----------------

  Widget _buildTrendBoard(ThemeData theme, HomeViewModel viewModel, DashboardBoard board, String title, List<_SeriesDef> defs) {
    final points = viewModel.slice(board);

    return GlassPanel(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _boardHeader(theme, viewModel, board, title),
            const SizedBox(height: 12),
            _buildLegend(theme, defs),
            const SizedBox(height: 12),
            SizedBox(height: 260, child: _buildLineChart(theme, points, defs)),
          ],
        ),
      ),
    );
  }

  // 曲线定义：初筛 2 根 / 复筛 3 根 / 诊断 3 根
  List<_SeriesDef> _screenSeries(ThemeData theme) => [
    (label: '初筛人数', color: theme.colorScheme.primary, pick: (p) => p.screened),
    (label: '异常人数', color: theme.colorScheme.secondary, pick: (p) => p.screenAbnormal),
  ];

  List<_SeriesDef> _reScreenSeries(ThemeData theme) => [
    (label: '复筛人数', color: theme.colorScheme.primary, pick: (p) => p.reScreened),
    (label: '异常人数', color: theme.colorScheme.secondary, pick: (p) => p.reScreenAbnormal),
    (label: '复查人数', color: theme.colorScheme.tertiary, pick: (p) => p.reScreenRecheck),
  ];

  List<_SeriesDef> _diagnosisSeries(ThemeData theme) => [
    (label: '诊断人数', color: theme.colorScheme.primary, pick: (p) => p.diagnosed),
    (label: '确认人数', color: theme.colorScheme.secondary, pick: (p) => p.confirmed),
    (label: '复查人数', color: theme.colorScheme.tertiary, pick: (p) => p.diagRecheck),
  ];

  Widget _buildLegend(ThemeData theme, List<_SeriesDef> defs) {
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        for (final def in defs)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: def.color, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 5),
              Text(def.label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
            ],
          ),
      ],
    );
  }

  Widget _buildLineChart(ThemeData theme, List<MonthPoint> points, List<_SeriesDef> defs) {
    final maxX = points.length > 1 ? (points.length - 1).toDouble() : 1.0;
    // 纵轴整数刻度：峰值上浮 15% 后 4 等分、每段向上取整，保证刻度全为整数
    final step = max(1, (_peakValue(points, defs) * 1.15 / 4).ceil());
    final labelInterval = max(1, (points.length / 12).ceil()).toDouble();

    final outline = theme.colorScheme.outlineVariant;
    final axisTextStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6));
    final tooltipTextStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onInverseSurface);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: 0,
        maxY: step * 4.0,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: step.toDouble(),
          getDrawingHorizontalLine: (value) => FlLine(color: outline.withValues(alpha: 0.3), strokeWidth: 0.5),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(color: outline.withValues(alpha: 0.5), width: 0.5),
            left: BorderSide(color: outline.withValues(alpha: 0.5), width: 0.5),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: step.toDouble(),
              getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: axisTextStyle),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: labelInterval,
              getTitlesWidget: (value, meta) => _monthLabel(theme, points, value, meta),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            maxContentWidth: 180,
            getTooltipColor: (_) => theme.colorScheme.inverseSurface,
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  // 首条带月份头行，其余为各系列一行「名称: 值」
                  spot.barIndex == 0 ? '${points[spot.x.toInt()].month}\n' : '',
                  tooltipTextStyle!,
                  children: [
                    TextSpan(text: '${defs[spot.barIndex].label}: ${spot.y.toInt()}'),
                  ],
                ),
            ],
          ),
        ),
        lineBarsData: [
          for (final def in defs)
            LineChartBarData(
              spots: [
                for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), def.pick(points[i]).toDouble()),
              ],
              isCurved: true,
              barWidth: 2,
              color: def.color,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: false),
            ),
        ],
      ),
    );
  }

  /// 横轴月份标签：显示 'M 月'（完整 'yyyy-MM' 在触摸提示中展示）；
  /// 区间超过 12 个月时由 interval 抽稀。
  Widget _monthLabel(ThemeData theme, List<MonthPoint> points, double value, TitleMeta meta) {
    final index = value.toInt();
    if (value != index || index < 0 || index >= points.length) {
      return const SizedBox.shrink();
    }
    final label = '${int.parse(points[index].month.substring(5))}月';
    return SideTitleWidget(
      meta: meta,
      child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
    );
  }

  double _peakValue(List<MonthPoint> points, List<_SeriesDef> defs) {
    var peak = 0;
    for (final p in points) {
      for (final def in defs) {
        final v = def.pick(p);
        if (v > peak) peak = v;
      }
    }
    return peak.toDouble();
  }

  // ---------------- 起止月筛选 ----------------

  Widget _boardHeader(ThemeData theme, HomeViewModel viewModel, DashboardBoard board, String title) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final titleWidget = Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold));
        final rangeControl = _rangeControl(theme, viewModel, board);
        // 窄屏标题与筛选控件上下排布，避免横向溢出
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [titleWidget, const SizedBox(height: 10), rangeControl],
          );
        }
        return Row(children: [titleWidget, const Spacer(), rangeControl]);
      },
    );
  }

  Widget _rangeControl(ThemeData theme, HomeViewModel viewModel, DashboardBoard board) {
    final range = viewModel.rangeOf(board);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _rangeField(theme, range.from, () => _pickRangeStart(board)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('至', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
        ),
        _rangeField(theme, range.to, () => _pickRangeEnd(board)),
      ],
    );
  }

  Widget _rangeField(ThemeData theme, String value, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined, size: 15, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(value, style: theme.textTheme.bodySmall),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickRangeStart(DashboardBoard board) async {
    final range = _viewModel.rangeOf(board);
    final picked = await showMonthPickerDialog(
      context: context,
      title: '选择起始月',
      initialMonth: range.from,
      firstMonth: _viewModel.earliestMonth,
      lastMonth: _viewModel.latestMonth,
    );
    if (picked == null || !mounted) return;
    // 起止倒挂前置拦截（对齐高级搜索口径）
    if (!_viewModel.setRange(board, picked, range.to)) {
      _showRangeError('起始月不能晚于截止月');
    }
  }

  Future<void> _pickRangeEnd(DashboardBoard board) async {
    final range = _viewModel.rangeOf(board);
    final picked = await showMonthPickerDialog(
      context: context,
      title: '选择截止月',
      initialMonth: range.to,
      firstMonth: _viewModel.earliestMonth,
      lastMonth: _viewModel.latestMonth,
    );
    if (picked == null || !mounted) return;
    if (!_viewModel.setRange(board, range.from, picked)) {
      _showRangeError('截止月不能早于起始月');
    }
  }

  void _showRangeError(String message) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onError)),
        backgroundColor: theme.colorScheme.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(label: '关闭', textColor: theme.colorScheme.onPrimary, onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar),
      ),
    );
  }
}
