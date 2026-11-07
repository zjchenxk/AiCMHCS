import 'package:client/view_models/system/campus_management_view_model.dart';
import 'package:client/views/base/base_page.dart';
import 'package:client/views/system/campus_info_form.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 院区管理页：院区归属当前登录用户的所属医院。左侧该院区的院区列表
/// （选择 + 删除）；右侧信息表单三态——未选中给提示、选中院区可编辑、
/// 新增时切换为新增表单（表单清空，归属固定为登录用户所属医院）。
class CampusManagementPage extends BasePage {
  const CampusManagementPage({
    super.key,
    required super.loginUser,
    required super.child,
  });

  @override
  State<CampusManagementPage> createState() => _CampusManagementPageState();
}

class _CampusManagementPageState extends State<CampusManagementPage> {
  /// dispose 中不能再用 context 取 Provider，保存实例引用供移除监听
  late final CampusManagementViewModel _viewModel;

  @override
  void initState() {
    super.initState();

    // 通过 Provider 获取全局注入的实例（不再自己 new）
    _viewModel = context.read<CampusManagementViewModel>();
    // 每次进入页面按登录用户所属医院加载；VM 内部对同一医院已加载的
    // 情况直接跳过（切页保留状态），医院变化（切换账号）时强制重拉；
    // 延迟到首帧后发起，避免 build 期间同步 notifyListeners
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _viewModel.loadData(widget.loginUser.hospId);
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
    final viewModel = context.watch<CampusManagementViewModel>();

    return viewModel.loading ? const Center(child: CircularProgressIndicator()) : _buildBody(context, viewModel);
  }

  Widget _buildBody(BuildContext context, CampusManagementViewModel viewModel) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左侧：院区列表（归属登录用户所属医院）
        Expanded(
          flex: 4,
          child: Card(
            color: Theme.of(context).colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: Theme.of(context),
                  title: '院区列表',
                  icon: Icons.domain_outlined,
                  trailing: IconButton(
                    tooltip: '新增院区',
                    icon: Icon(
                      Icons.add_business_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    // 未设置所属医院时禁用新增
                    onPressed: viewModel.unbound || viewModel.busy ? null : viewModel.startCreate,
                  ),
                ),
                Expanded(
                  child: viewModel.unbound
                      ? const Center(child: Text('当前登录用户未设置所属医院，无法管理院区'))
                      : viewModel.campuses.isEmpty
                      ? const Center(child: Text('暂无院区，点击右上角新增'))
                      : ListView(
                          children: viewModel.campuses.map((c) => _buildCampusTile(context, viewModel, c)).toList(),
                        ),
                ),
              ],
            ),
          ),
        ),

        // 右侧：院区信息表单（按表单模式切换内容）
        Expanded(
          flex: 6,
          child: Card(
            color: Theme.of(context).colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: Theme.of(context),
                  title: '院区信息',
                  icon: Icons.info_outlined,
                ),
                Expanded(
                  child: switch (viewModel.formMode) {
                    CampusFormMode.empty => Center(
                      child: Text(
                        viewModel.unbound ? '当前登录用户未设置所属医院' : '请先在左侧选择院区',
                      ),
                    ),
                    // key 含模式与院区 ID：切换模式或目标时表单重建，
                    // 实现新增表单清空、编辑表单回填
                    _ => CampusInfoForm(
                      key: ValueKey(
                        viewModel.formMode == CampusFormMode.create ? 'create' : 'edit:${viewModel.selectedCampus!.id}',
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

  /// 面板抬头：primaryContainer 背景条（左右两栏同款）
  Widget _buildPanelHeader({required ThemeData theme, required String title, required IconData icon, Widget? trailing}) {
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

  /// 院区列表行：主显名称，副显代码/地址/电话；点击选中（右侧编辑），
  /// 行尾删除（确认对话框）
  Widget _buildCampusTile(BuildContext context, CampusManagementViewModel viewModel, Campus campus) {
    final theme = Theme.of(context);
    final selected = viewModel.selectedCampus?.id == campus.id && viewModel.formMode != CampusFormMode.create;
    final subtitleParts = [
      if (campus.code.isNotEmpty) '代码：${campus.code}',
      if (campus.address != null && campus.address!.isNotEmpty) '地址：${campus.address}',
      if (campus.tel != null && campus.tel!.isNotEmpty) '电话：${campus.tel}',
    ];
    return ListTile(
      dense: true,
      selected: selected,
      leading: Icon(
        Icons.domain_outlined,
        size: 20,
        color: selected ? theme.colorScheme.primary : null,
      ),
      title: Text(
        campus.name,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? theme.colorScheme.primary : null,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitleParts.isEmpty
          ? null
          : Text(
              subtitleParts.join('　'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: IconButton(
        tooltip: '删除',
        visualDensity: VisualDensity.compact,
        icon: Icon(
          Icons.delete_outline,
          size: 18,
          color: theme.colorScheme.error,
        ),
        onPressed: viewModel.busy ? null : () => _confirmDelete(context, viewModel, campus),
      ),
      onTap: () => viewModel.selectCampus(campus),
    );
  }

  /// 删除确认对话框（毛玻璃）
  void _confirmDelete(BuildContext context, CampusManagementViewModel viewModel, Campus campus) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GlassPanel(
            blur: 24,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        color: theme.colorScheme.error,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '删除确认',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '确定删除院区「${campus.name}」吗？',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.error,
                          foregroundColor: theme.colorScheme.onError,
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final ok = await viewModel.deleteCampus(campus);
                          if (!mounted) return;
                          if (ok) {
                            _showResultSnackBar('删除成功');
                          }
                          // 失败提示由 errorMsg 监听统一弹出
                        },
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showResultSnackBar(String message) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onPrimary,
          ),
        ),
        backgroundColor: theme.colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
