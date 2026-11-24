import 'package:client/view_models/system/holiday_management_view_model.dart';
import 'package:client/views/base/base_page.dart';
import 'package:client/views/system/holiday_info_form.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 法定节假日管理页：左侧为节假日列表（按起始日期倒序，每行展示
/// 「类型 + 放假区间 + 创建人/时间」），右侧为新增/修改编辑区（节假日
/// 类型下拉 + 起止日期选择）。布局与高危因素管理/数据字典管理同构
/// （左右双 Card，各带 60px primaryContainer 面板头）；【新增】/【刷新】
/// 在左列表面板头，增删改按操作权限 9911000001/9911000002/9911000003
/// 灰化控制（修改权限决定编辑态表单可编辑性）。
class HolidayManagementPage extends BasePage {
  const HolidayManagementPage({
    super.key,
    required super.loginUser,
    required super.child,
  });

  @override
  State<HolidayManagementPage> createState() => _HolidayManagementPageState();
}

class _HolidayManagementPageState extends State<HolidayManagementPage> {
  /// dispose 中不能再用 context 取 Provider，保存实例引用供移除监听
  late final HolidayManagementViewModel _viewModel;

  @override
  void initState() {
    super.initState();

    // 通过 Provider 获取全局注入的实例（不再自己 new）
    _viewModel = context.read<HolidayManagementViewModel>();
    // 每次进入页面强制重拉（保证切回本页时数据一致）；
    // 延迟到首帧后发起，避免 build 期间同步 notifyListeners
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _viewModel.loadData();
      }
    });

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

    //获取当前主题
    final ThemeData theme = Theme.of(context);

    if (_viewModel.errorMsg != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _viewModel.errorMsg!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onError,
            ),
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
    final viewModel = context.watch<HolidayManagementViewModel>();

    return viewModel.loading ? const Center(child: CircularProgressIndicator()) : _buildBody(context, viewModel);
  }

  Widget _buildBody(BuildContext context, HolidayManagementViewModel viewModel) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左侧：节假日列表
        Expanded(
          flex: 4,
          child: Card(
            color: theme.colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: theme,
                  title: '法定节假日',
                  icon: Icons.event_outlined,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 新增按钮按「新增法定节假日」操作权限灰化
                      IconButton(
                        tooltip: viewModel.canCreate ? '新增法定节假日' : '无新增操作权限',
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        onPressed: viewModel.loading || viewModel.busy || !viewModel.canCreate ? null : viewModel.startCreate,
                      ),
                      IconButton(
                        tooltip: '刷新',
                        icon: const Icon(Icons.refresh_outlined, size: 20),
                        // 手动整表重拉（进入页面时 loadData 已自动重拉）
                        onPressed: viewModel.loading || viewModel.busy ? null : viewModel.loadData,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: viewModel.isEmpty
                      ? const Center(child: Text('暂无法定节假日，请新增'))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: viewModel.holidays.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            indent: 12,
                            endIndent: 12,
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                          ),
                          itemBuilder: (context, index) => _buildHolidayTile(context, viewModel, viewModel.holidays[index]),
                        ),
                ),
              ],
            ),
          ),
        ),

        // 右侧：节假日信息表单（按表单模式切换内容）
        Expanded(
          flex: 6,
          child: Card(
            color: theme.colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: theme,
                  title: viewModel.formMode == HolidayFormMode.create ? '新增法定节假日' : '节假日信息',
                  icon: Icons.info_outlined,
                ),
                Expanded(
                  child: switch (viewModel.formMode) {
                    HolidayFormMode.empty => const Center(child: Text('请先在左侧选择节假日')),
                    // key 含模式与节假日 ID：切换模式/选中项时表单重建，
                    // 实现新增表单清空、编辑表单回填
                    _ => HolidayInfoForm(
                      key: ValueKey(
                        viewModel.formMode == HolidayFormMode.create ? 'create' : 'edit:${viewModel.selected!.id}',
                      ),
                      viewModel: viewModel,
                    ),
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 面板抬头：primaryContainer 背景条（左右两栏同款，与高危因素/互斥
  /// 规则管理页一致）。
  Widget _buildPanelHeader({
    required ThemeData theme,
    required String title,
    required IconData icon,
    Widget? trailing,
  }) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: theme.colorScheme.primaryContainer,
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  /// 单条节假日：类型 + 放假区间，附创建人与创建时间。
  Widget _buildHolidayTile(
    BuildContext context,
    HolidayManagementViewModel viewModel,
    BaseHoliday holiday,
  ) {
    final theme = Theme.of(context);
    final selected = viewModel.formMode != HolidayFormMode.create && viewModel.selected?.id == holiday.id;
    return Material(
      color: selected ? theme.colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
      child: InkWell(
        onTap: () => viewModel.selectHoliday(holiday),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.event_outlined,
                    size: 16,
                    color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: holiday.holidayTypeLabel,
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(text: '　'),
                          TextSpan(
                            text: '${holiday.startDate} ~ ${holiday.endDate}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Text(
                  '创建人：${holiday.creatorName}${(holiday.createTime ?? '').isEmpty ? '' : ' · ${holiday.createTime}'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
