import 'dart:async';
import 'dart:convert';

import 'package:client/main.dart';
import 'package:client/models/child_sidebar.dart';
import 'package:client/services/child_service.dart';
import 'package:client/services/time_service.dart';
import 'package:client/utils/asd_check_flow.dart';
import 'package:client/utils/log_helper.dart';
import 'package:client/utils/risk_color.dart';
import 'package:client/view_models/asd/initial_screening_view_model.dart';
import 'package:client/view_models/main/initial_screening_list_view_model.dart';
import 'package:client/view_models/main/main_view_model.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 右侧侧边栏垂直 TAB（参照 VS Code 活动条：最右缘 5 个图标位，选中
/// 项高亮；内容区随 TAB 切换）。
enum _SidebarTab {
  current('当前儿童', Icons.child_care_outlined),
  initial('初筛儿童', Icons.fact_check_outlined),
  rescreen('复筛儿童', Icons.event_repeat_outlined),
  diagnosis('诊断儿童', Icons.monitor_heart_outlined),
  intervention('干预儿童', Icons.volunteer_activism_outlined);

  const _SidebarTab(this.title, this.icon);

  /// TAB 标题（标题栏靠右展示）。
  final String title;

  /// 活动条图标（outlined 系列）。
  final IconData icon;
}

/// 主界面右侧儿童信息侧边栏。
///
/// 在显示当前儿童信息（MainViewModel.child）的基础上集成初筛/复筛/
/// 诊断/干预儿童列表：最右缘为 5 个垂直 TAB 图标（VS Code 活动条样式），
/// 标题栏收起/展开按钮在最左端、标题文字靠右。
///
/// - 当前儿童 TAB：头像、基本信息、五色高危分级（CHILD_HIGH_RISK_FACTOR）、
///   高危因素列表（REMARK 显示在名称下方）与历次检查时间轴
///   （CHILD_CHECK_RECORD）；未选定儿童时显示指引占位。
/// - 初筛儿童 TAB：按检查日期区间分页查询 ASD_INITIAL_SCREENING（服务端
///   解密儿童姓名），双击记录切换当前儿童并打开初筛记录表定位到对应
///   月龄 TAB 浏览。
/// - 复筛/诊断/干预儿童 TAB：界面结构与初筛一致，取数与双击暂缓开放。
///
/// 侧边栏常驻显示（列表 TAB 不依赖当前儿童）；收起后仅保留活动条竖排
/// 图标，点 TAB 图标展开并激活对应页。展开宽度 320（含活动条），内容区
/// 独立滚动。
class ChildInfoSidebar extends StatefulWidget {
  /// 构造函数。
  const ChildInfoSidebar({super.key});

  /// 展开总宽度（含最右缘活动条；内容区 = 总宽 − 44 活动条）。
  static const double expandedWidth = 320;

  /// 收起宽度（仅保留活动条竖排 TAB 与展开按钮）。
  static const double collapsedWidth = 48;

  /// 最右缘活动条宽度。
  static const double activityRailWidth = 44;

  @override
  State<ChildInfoSidebar> createState() => _ChildInfoSidebarState();
}

class _ChildInfoSidebarState extends State<ChildInfoSidebar> {
  /// 展开态内容区滚动控制器：显式同挂 Scrollbar 与 SingleChildScrollView——
  /// Web 桌面平台下 SingleChildScrollView 缺省不关联 PrimaryScrollController，
  /// 无控制器的 Scrollbar 在滚动条淡出动画时会断言失败（整屏红闪 + 报错
  /// 日志「The Scrollbar's ScrollController has no ScrollPosition attached」）。
  final ScrollController _scrollController = ScrollController();

  // 初筛列表查询条件输入框（只读，点按弹日期选择器）
  final TextEditingController _startDateCtrl = TextEditingController();
  final TextEditingController _endDateCtrl = TextEditingController();

  /// 当前激活的内容 TAB。
  _SidebarTab _activeTab = _SidebarTab.current;

  /// 正在打开初筛记录（防双击重入）。
  bool _openingRecord = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _startDateCtrl.dispose();
    _endDateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MainViewModel>(
      builder: (context, mainViewModel, _) {
        final theme = Theme.of(context);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
          width: mainViewModel.childSidebarCollapsed ? ChildInfoSidebar.collapsedWidth : ChildInfoSidebar.expandedWidth,
          child: GlassPanel(
            borderRadius: 16,
            child: mainViewModel.childSidebarCollapsed
                ? _buildCollapsedRail(theme, mainViewModel)
                // 固定内容宽度：收起动画期间内容被面板裁切，不因宽度收缩
                // 触发文字换行/溢出报错（与左侧功能菜单同一处理）
                : OverflowBox(
                    alignment: AlignmentDirectional.topStart,
                    minWidth: ChildInfoSidebar.expandedWidth - 1,
                    maxWidth: ChildInfoSidebar.expandedWidth - 1,
                    child: SizedBox(
                      width: ChildInfoSidebar.expandedWidth - 1,
                      child: _buildExpandedPanel(theme, mainViewModel),
                    ),
                  ),
          ),
        );
      },
    );
  }

  // ---------------- 骨架（活动条 / 标题栏 / 收起态） ----------------

  /// 收起态：展开按钮 + 竖排 5 个 TAB 图标（点图标展开并激活对应页）。
  Widget _buildCollapsedRail(ThemeData theme, MainViewModel mainViewModel) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Tooltip(
          message: '展开侧边栏',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            hoverColor: theme.colorScheme.primary.withValues(alpha: 0.10),
            highlightColor: theme.colorScheme.primary.withValues(alpha: 0.16),
            onTap: mainViewModel.toggleChildSidebar,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Icon(
                Icons.keyboard_double_arrow_left,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ),
        ),
        // TAB 图标保持居顶（与展开态活动条同布局，避免展开时
        // 「居中→居顶」的位移动画）
        const SizedBox(height: 8),
        for (final tab in _SidebarTab.values) _buildRailButton(theme, tab),
      ],
    );
  }

  /// 展开态：标题栏（收起钮最左、标题靠右）+ 加载进度条 + 内容区 +
  /// 最右缘活动条。
  Widget _buildExpandedPanel(ThemeData theme, MainViewModel mainViewModel) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            children: [
              _buildHeader(theme, mainViewModel),
              // 扩展档案/头像/列表加载中的细进度条（不遮挡已展示内容）
              if (mainViewModel.childSidebarLoading)
                LinearProgressIndicator(
                  minHeight: 2,
                  color: theme.colorScheme.primary,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                ),
              Expanded(child: _buildTabContent(theme, mainViewModel)),
            ],
          ),
        ),
        _buildActivityRail(theme),
      ],
    );
  }

  /// 标题栏：收起/展开按钮在最左端，标题文字靠右。
  Widget _buildHeader(ThemeData theme, MainViewModel mainViewModel) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 6),
      child: Row(
        children: [
          Tooltip(
            message: '收起',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              hoverColor: theme.colorScheme.primary.withValues(alpha: 0.10),
              highlightColor: theme.colorScheme.primary.withValues(alpha: 0.16),
              onTap: mainViewModel.toggleChildSidebar,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(
                  Icons.keyboard_double_arrow_right,
                  size: 18,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _activeTab.title,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 最右缘活动条：5 个垂直 TAB 图标（选中项主题色高亮）。
  Widget _buildActivityRail(ThemeData theme) {
    return Container(
      width: ChildInfoSidebar.activityRailWidth,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3), width: 0.5)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          for (final tab in _SidebarTab.values) _buildRailButton(theme, tab),
        ],
      ),
    );
  }

  /// 活动条单个 TAB 按钮（收起/展开两态同几何，切换时不产生尺寸形变）。
  Widget _buildRailButton(ThemeData theme, _SidebarTab tab) {
    final active = _activeTab == tab;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Tooltip(
        message: tab.title,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: theme.colorScheme.primary.withValues(alpha: 0.10),
          highlightColor: theme.colorScheme.primary.withValues(alpha: 0.16),
          onTap: () => _selectTab(tab),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: active ? theme.colorScheme.primary.withValues(alpha: 0.14) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              tab.icon,
              size: 20,
              color: active ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }

  /// 切换 TAB（收起态点图标同时展开面板；进入初筛列表时惰性加载）。
  void _selectTab(_SidebarTab tab) {
    setState(() => _activeTab = tab);
    final mainViewModel = context.read<MainViewModel>();
    if (mainViewModel.childSidebarCollapsed) {
      mainViewModel.toggleChildSidebar();
    }
    if (tab == _SidebarTab.initial) {
      unawaited(context.read<InitialScreeningListViewModel>().ensureLoaded());
    }
  }

  /// 内容区按激活 TAB 分发。
  Widget _buildTabContent(ThemeData theme, MainViewModel mainViewModel) {
    return switch (_activeTab) {
      _SidebarTab.current => _buildCurrentChildContent(theme, mainViewModel),
      _SidebarTab.initial => _buildInitialScreeningTab(theme),
      _ => _buildDeferredListTab(theme, _activeTab),
    };
  }

  // ---------------- TAB：当前儿童 ----------------

  /// 当前儿童内容（未选定儿童时显示指引占位）。
  Widget _buildCurrentChildContent(ThemeData theme, MainViewModel mainViewModel) {
    final data = mainViewModel.childSidebarData;
    if (data == null) {
      return _buildEmptyHint(theme, '未选定儿童', '请先在顶部搜索框精确检索并选定儿童');
    }
    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildProfile(theme, data),
            const SizedBox(height: 18),
            // 数据未就绪时展示加载/失败状态，避免把「未加载」误显示为「无高危因素」
            if (data.factorsLoaded) _buildRiskScale(theme, data) else _buildRiskStatusSection(theme, mainViewModel, data),
            const SizedBox(height: 18),
            _buildBasicMetrics(theme, data),
            if (data.factorsLoaded) ...[
              const SizedBox(height: 18),
              _buildSectionTitle(theme, '高危因素'),
              const SizedBox(height: 8),
              ..._buildFactorTiles(theme, data),
            ],
            const SizedBox(height: 18),
            _buildSectionTitle(theme, '历次检查'),
            const SizedBox(height: 10),
            if (data.examsLoaded)
              _buildTimeline(theme, data)
            else
              _buildStatusBox(
                theme,
                data.examsLoadFailed ? '检查记录加载失败' : '正在加载检查记录…',
                onRetry: data.examsLoadFailed ? mainViewModel.refreshChildSidebar : null,
              ),
          ],
        ),
      ),
    );
  }

  // ---------------- TAB：初筛儿童（真实取数） ----------------

  /// 初筛列表 TAB：日期区间查询栏 + 分页列表（双击记录打开初筛记录表）。
  Widget _buildInitialScreeningTab(ThemeData theme) {
    return Consumer<InitialScreeningListViewModel>(
      builder: (context, viewModel, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildQueryBar(
              theme,
              onSearch: () => viewModel.search(start: _startDateCtrl.text, end: _endDateCtrl.text),
              onReset: _resetScreeningFilter,
            ),
            Expanded(
              child: viewModel.loading && viewModel.records.isEmpty
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : viewModel.loadFailed
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      children: [
                        _buildStatusBox(theme, '初筛记录加载失败', onRetry: viewModel.refresh),
                      ],
                    )
                  : viewModel.records.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      children: [
                        _buildStatusBox(theme, viewModel.loaded ? '暂无初筛记录' : '点击【查询】加载初筛记录'),
                      ],
                    )
                  : Scrollbar(
                      controller: _scrollController,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        itemCount: viewModel.records.length,
                        itemBuilder: (context, index) => _buildScreeningTile(theme, viewModel.records[index]),
                      ),
                    ),
            ),
            _buildPager(theme, viewModel),
          ],
        );
      },
    );
  }

  /// 单条初筛记录（儿童姓名 + 月龄标签 + 检查日期/初筛结果；双击打开）。
  Widget _buildScreeningTile(ThemeData theme, InitialScreeningListItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Tooltip(
        message: '双击打开该儿童的初筛记录表',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: theme.colorScheme.primary.withValues(alpha: 0.08),
          highlightColor: theme.colorScheme.primary.withValues(alpha: 0.14),
          onDoubleTap: () => unawaited(_openScreeningRecord(item)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35), width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.childName.isEmpty ? '（未命名儿童）' : item.childName,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _monthLabel(item.checkMonth),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                    const SizedBox(width: 4),
                    Text(
                      item.checkDate,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      item.checkResult,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: item.checkResult == AsdCheckFlow.abnormal ? theme.colorScheme.error : theme.colorScheme.onSurface.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 初筛列表双击记录：切换当前儿童 → 打开初筛记录表 → 定位到该记录
  /// 的月龄 TAB（浏览态由页面按已录入记录自动进入）。
  Future<void> _openScreeningRecord(InitialScreeningListItem item) async {
    if (_openingRecord) return;
    _openingRecord = true;
    // await 前取齐界面依赖（跨异步不持 BuildContext）
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
    try {
      final archive = await getIt<ChildService>().load(item.childId);
      if (!mounted) return;
      final mainViewModel = context.read<MainViewModel>();
      // 先登记待打开时段再切儿童/导航：初筛页 _tryApplyAutoTab 取走后
      // 切到对应月龄 TAB（记录加载完成后该 TAB 自动进入浏览态）
      context.read<InitialScreeningViewModel>().requestOpenMonth(item.checkMonth);
      mainViewModel.setCurrentChild(archive.$1);
      mainViewModel.openMenuByRoute('/asd/initialScreening');
    } catch (e, st) {
      LogHelper.error('client:ChildInfoSidebar.openScreeningRecord', e, st);
      messenger.showSnackBar(
        SnackBar(
          content: Text('打开初筛记录失败，请稍后重试', style: TextStyle(color: theme.colorScheme.onError)),
          backgroundColor: theme.colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      _openingRecord = false;
    }
  }

  /// 重置初筛查询条件并重新查询全部记录。
  Future<void> _resetScreeningFilter() async {
    _startDateCtrl.clear();
    _endDateCtrl.clear();
    await context.read<InitialScreeningListViewModel>().search();
  }

  // ---------------- TAB：复筛/诊断/干预（取数暂缓） ----------------

  /// 暂缓开放的列表 TAB：查询栏 + 列头占位 + 提示（取数与双击暂缓）。
  Widget _buildDeferredListTab(ThemeData theme, _SidebarTab tab) {
    final (dateLabel, resultLabel) = switch (tab) {
      _SidebarTab.intervention => ('管理日期', '康复效果'),
      _ => ('检查日期', tab == _SidebarTab.rescreen ? '复筛结果' : '诊断结果'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildQueryBar(
          theme,
          onSearch: () => _toastDeferred('${tab.title}查询'),
          onReset: () => _toastDeferred('${tab.title}查询'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text('儿童姓名', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.55))),
              ),
              Expanded(
                child: Text(dateLabel, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.55))),
              ),
              Expanded(
                child: Text(
                  resultLabel,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: _buildStatusBox(theme, '${tab.title}查询功能暂缓开放'),
        ),
      ],
    );
  }

  /// 暂缓 TAB 的查询/重置提示。
  void _toastDeferred(String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$action暂缓开放'), behavior: SnackBarBehavior.floating),
    );
  }

  // ---------------- 列表公共部件 ----------------

  /// 查询条件栏：起始/截止日期（只读框点按弹选择器）+ 查询/重置。
  Widget _buildQueryBar(ThemeData theme, {required VoidCallback onSearch, required VoidCallback onReset}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _buildDateField(theme, _startDateCtrl, '起始日期')),
              const SizedBox(width: 6),
              Expanded(child: _buildDateField(theme, _endDateCtrl, '截止日期')),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: onSearch,
                // 高度随全局统一按钮主题（勿加 visualDensity，会改变高度）
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                icon: const Icon(Icons.search, size: 14),
                label: const Text('查询'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onReset,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                child: const Text('重置'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 只读日期输入框（点按弹日期选择器，选定后回写文本）。
  Widget _buildDateField(ThemeData theme, TextEditingController controller, String hint) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.45)),
        // 约束为 0 后图标默认贴框；图标距框左缘 6px，与文本间距 6px
        // （由 contentPadding.left 承担、不再叠加右侧内距）
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Icon(Icons.date_range_outlined, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        isDense: true,
        contentPadding: const EdgeInsets.only(left: 6, right: 8, top: 9, bottom: 9),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.colorScheme.primary),
        ),
      ),
      onTap: () => unawaited(_pickDate(controller)),
    );
  }

  /// 弹日期选择器并回写到输入框（yyyy-MM-dd）。
  Future<void> _pickDate(TextEditingController controller) async {
    final now = getIt<TimeService>().now();
    final initial = DateTime.tryParse(controller.text) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      controller.text = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  /// 分页脚标：上一页/页码信息/下一页。
  Widget _buildPager(ThemeData theme, InitialScreeningListViewModel viewModel) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left, size: 18),
            tooltip: '上一页',
            onPressed: viewModel.page > 1 ? () => unawaited(viewModel.goToPage(viewModel.page - 1)) : null,
          ),
          Expanded(
            child: Text(
              '第 ${viewModel.page} / ${viewModel.totalPages} 页 · 共 ${viewModel.total} 条',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right, size: 18),
            tooltip: '下一页',
            onPressed: viewModel.page < viewModel.totalPages ? () => unawaited(viewModel.goToPage(viewModel.page + 1)) : null,
          ),
        ],
      ),
    );
  }

  /// 检查时段标签（复用初筛页 TAB 定义；未定义时段回退「N月龄」）。
  String _monthLabel(int month) {
    for (final tab in screeningTabs) {
      if (tab.$1 == month) return tab.$2;
    }
    return '$month月龄';
  }

  // ---------------- 当前儿童 TAB 内容（原有实现） ----------------

  /// 头像 + 姓名 + 性别图标 + 年龄（岁/月/天）。
  Widget _buildProfile(ThemeData theme, ChildSidebarData data) {
    final genderIcon = switch (data.gender) {
      '男' => Icons.male,
      '女' => Icons.female,
      _ => Icons.person_outline,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundImage: _decodeAvatar(data.avatarBase64),
          child: Icon(Icons.child_care_outlined, size: 32, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(
                data.name.isEmpty ? '未命名儿童' : data.name,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (data.gender.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(genderIcon, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 2),
                        Text(
                          data.gender,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  if (data.gender.isNotEmpty && data.ageText.isNotEmpty)
                    Text(
                      '·',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  if (data.ageText.isNotEmpty)
                    Text(
                      data.ageText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                ],
              ),
              // 早产儿（矫正窗口内）额外展示矫正年龄；实足年龄保留在上方
              if (data.correctedAgeText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Tooltip(
                    message: '早产儿矫正年龄：以预产期（矫正胎龄 40 周）为起点计算，用于体格生长与发育评估；预防接种等按实足年龄',
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Wrap(
                        spacing: 3,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '矫正年龄 ${data.correctedAgeText}',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 高危因素未加载完成时的状态块（加载中 / 加载失败 + 重试）。
  Widget _buildRiskStatusSection(ThemeData theme, MainViewModel mainViewModel, ChildSidebarData data) {
    final failed = data.factorsLoadFailed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(theme, '高危五色分级'),
        const SizedBox(height: 8),
        _buildStatusBox(
          theme,
          failed ? '高危因素加载失败' : '正在加载高危因素…',
          onRetry: failed ? mainViewModel.refreshChildSidebar : null,
        ),
      ],
    );
  }

  /// 数据未就绪/加载失败时的状态块（可选重试按钮）。
  Widget _buildStatusBox(ThemeData theme, String message, {VoidCallback? onRetry}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 2),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }

  /// 空态指引（标题 + 说明，当前儿童未选定时显示）。
  Widget _buildEmptyHint(ThemeData theme, String title, String hint) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.child_care_outlined, size: 44, color: theme.colorScheme.primary.withValues(alpha: 0.35)),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
            ),
          ],
        ),
      ),
    );
  }

  /// 五色分级色标 + 综合分级摘要。
  Widget _buildRiskScale(ThemeData theme, ChildSidebarData data) {
    final activeLevels = data.activeLevels;
    final activeColor = RiskColorPalette.colorOf(data.riskLevel.label, theme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(theme, '高危五色分级'),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final level in HighRiskLevel.values) Expanded(child: _buildRiskBadge(theme, level, activeLevels.contains(level))),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: activeColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: activeColor.withValues(alpha: 0.35), width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: activeColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _riskSummary(data),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '依据《高危新生儿分类分级管理专家共识（2023）》评估',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  /// 五色色标中的单个分级（选中项实心勾选，未选中项弱化）。
  Widget _buildRiskBadge(ThemeData theme, HighRiskLevel level, bool active) {
    final color = RiskColorPalette.colorOf(level.label, theme);
    // 浅色（黄色）底上用深色勾，其余深色底用主题前景色，保证可辨识
    final checkColor = color.computeLuminance() > 0.45 ? theme.colorScheme.onSurface : theme.colorScheme.onPrimary;
    return Tooltip(
      message: level.description,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? color : color.withValues(alpha: 0.14),
              border: Border.all(
                color: active ? color : color.withValues(alpha: 0.30),
                width: active ? 2 : 1,
              ),
            ),
            child: active ? Icon(Icons.check, size: 14, color: checkColor) : null,
          ),
          const SizedBox(height: 4),
          Text(
            level.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: active ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withValues(alpha: 0.4),
              fontWeight: active ? FontWeight.bold : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  /// 综合分级摘要文案（紫色为叠加标识，单独说明）。
  String _riskSummary(ChildSidebarData data) {
    final base = '综合分级：${data.riskLevel.label}';
    if (!data.purpleOverlay) return base;
    return '$base，叠加紫色（传染病管理）';
  }

  /// 出生日期、G/P、出生孕周、出生体重、联系电话（无值项不显示）。
  Widget _buildBasicMetrics(ThemeData theme, ChildSidebarData data) {
    final rows = <(String, String?)>[
      ('出生日期', data.birthDateText),
      ('孕次产次', data.gravidityParity),
      ('出生孕周', data.gestationalAge),
      ('出生体重', data.birthWeight),
      ('联系电话', data.phone),
    ].where((row) => row.$2 != null && row.$2!.isNotEmpty).toList();
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 0.5,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      rows[i].$1,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      rows[i].$2!,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 分组标题（左侧主题色竖条）。
  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  /// 高危因素卡片列表（左侧色条标识所属五色级别）。
  List<Widget> _buildFactorTiles(ThemeData theme, ChildSidebarData data) {
    return [for (final factor in data.factors) _buildFactorTile(theme, factor)];
  }

  /// 单条高危因素卡片（名称 + 五色标签；有 REMARK 时在名称下方展示）。
  Widget _buildFactorTile(ThemeData theme, HighRiskFactor factor) {
    final color = RiskColorPalette.colorOf(factor.riskColor, theme);
    final colorLabel = factor.riskColor?.trim().isNotEmpty ?? false ? factor.riskColor!.trim() : '未设置';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.5,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          factor.title,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          colorLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 数据库备注（REMARK）非空时显示在因素名称下方
                  if (factor.remark.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      factor.remark,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 历次检查时间轴。
  Widget _buildTimeline(ThemeData theme, ChildSidebarData data) {
    if (data.exams.isEmpty) {
      return Text(
        '暂无检查记录',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < data.exams.length; i++) _buildTimelineItem(theme, data.exams[i], isLast: i == data.exams.length - 1),
      ],
    );
  }

  /// 单条检查记录（圆点 + 竖线 + 日期/名称/结果）。
  Widget _buildTimelineItem(ThemeData theme, ChildExamRecord exam, {required bool isLast}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 16,
            child: Column(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primary,
                    border: Border.all(color: theme.colorScheme.surface, width: 1.5),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exam.date,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    exam.name,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (exam.result.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      exam.result,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 解析头像 base64（CHILD_PHOTO.AVATAR_IMAGE 为裸 base64）；无效时
  /// 返回 null，回退显示默认儿童图标。
  MemoryImage? _decodeAvatar(String? base64Str) {
    if (base64Str == null || base64Str.isEmpty) return null;
    try {
      return MemoryImage(base64Decode(base64Str));
    } catch (_) {
      return null;
    }
  }
}
