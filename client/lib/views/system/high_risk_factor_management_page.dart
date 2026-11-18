import 'package:client/models/high_risk_factor_tree_node.dart';
import 'package:client/utils/risk_color.dart';
import 'package:client/view_models/system/high_risk_factor_management_view_model.dart';
import 'package:client/views/base/base_page.dart';
import 'package:client/views/system/high_risk_factor_info_form.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 高危因素管理页：左侧按高危颜色（绿/黄/橙/红/紫）分组，每组以对应
/// 颜色的浅色底显示，组内按「大类→小类→名称」组织树（大类/小类为空
/// 时名称逐级上提，名称末尾附高危因素编码）；右侧为新增/修改编辑区
/// （高危颜色中文五色下拉，高危等级绑定数据字典 DICT_CODE=99010001）。
/// 增删按钮按操作权限 9909000001/9909000002/9909000003 控制。
class HighRiskFactorManagementPage extends BasePage {
  const HighRiskFactorManagementPage({
    super.key,
    required super.loginUser,
    required super.child,
  });

  @override
  State<HighRiskFactorManagementPage> createState() => _HighRiskFactorManagementPageState();
}

class _HighRiskFactorManagementPageState extends State<HighRiskFactorManagementPage> {
  /// dispose 中不能再用 context 取 Provider，保存实例引用供移除监听
  late final HighRiskFactorManagementViewModel _viewModel;

  @override
  void initState() {
    super.initState();

    // 通过 Provider 获取全局注入的实例（不再自己 new）
    _viewModel = context.read<HighRiskFactorManagementViewModel>();
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
    final viewModel = context.watch<HighRiskFactorManagementViewModel>();

    return viewModel.loading ? const Center(child: CircularProgressIndicator()) : _buildBody(context, viewModel);
  }

  Widget _buildBody(BuildContext context, HighRiskFactorManagementViewModel viewModel) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左侧：按颜色分组的「大类→小类→名称」树
        Expanded(
          flex: 4,
          child: Card(
            color: theme.colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: theme,
                  title: '高危因素',
                  icon: Icons.warning_amber_outlined,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 新增按钮按「新增高危因素」操作权限显隐（无权限灰化）
                      IconButton(
                        tooltip: viewModel.canCreate ? '新增高危因素' : '无新增操作权限',
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
                      ? const Center(child: Text('暂无高危因素，请新增'))
                      : ListView(
                          padding: const EdgeInsets.only(top: 8, bottom: 8),
                          children: [
                            for (final group in viewModel.groups) _buildColorGroup(context, viewModel, group),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),

        // 右侧：高危因素信息表单（按表单模式切换内容）
        Expanded(
          flex: 6,
          child: Card(
            color: theme.colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: theme,
                  title: viewModel.formMode == HighRiskFactorFormMode.create ? '新增高危因素' : '高危因素信息',
                  icon: Icons.info_outlined,
                ),
                Expanded(
                  child: switch (viewModel.formMode) {
                    HighRiskFactorFormMode.empty => const Center(child: Text('请先在左侧选择高危因素')),
                    // key 含模式与因素 ID：切换模式/选中项时表单重建，
                    // 实现新增表单清空、编辑表单回填
                    _ => HighRiskFactorInfoForm(
                      key: ValueKey(
                        viewModel.formMode == HighRiskFactorFormMode.create ? 'create' : 'edit:${viewModel.selected!.id}',
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

  /// 面板抬头：primaryContainer 背景条（左右两栏同款）。
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

  /// 单个颜色分组：对应语义色的浅色底 + 描边，组头显示色标/名称/数量。
  Widget _buildColorGroup(
    BuildContext context,
    HighRiskFactorManagementViewModel viewModel,
    HighRiskFactorGroup group,
  ) {
    final theme = Theme.of(context);
    final color = RiskColorPalette.colorOf(group.colorName, theme);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      padding: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: RiskColorPalette.backgroundOf(group.colorName, theme),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: RiskColorPalette.borderOf(group.colorName, theme),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 组头：色标 + 颜色名称 + 因素数量
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    group.colorName ?? RiskColorPalette.unsetLabel,
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${group.factorCount} 项',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          for (final root in group.roots) _buildTreeNode(context, viewModel, root, 0),
        ],
      ),
    );
  }

  /// 递归构建树节点：大类/小类可展开折叠，因素叶子点击选中右侧编辑。
  Widget _buildTreeNode(
    BuildContext context,
    HighRiskFactorManagementViewModel viewModel,
    HighRiskFactorTreeNode node,
    int depth,
  ) {
    final theme = Theme.of(context);
    if (node.isLeaf) {
      final factor = node.factor!;
      final selected = viewModel.formMode != HighRiskFactorFormMode.create && viewModel.selected?.id == factor.id;
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.only(left: 12.0 + depth * 18, right: 4),
        selected: selected,
        selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.12),
        leading: Icon(
          Icons.label_outline,
          size: 16,
          color: selected ? theme.colorScheme.primary : null,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                node.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            // 名称末尾附高危因素编码
            Text(
              '（${factor.riskFactorCode}）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
        onTap: () => viewModel.selectFactor(factor),
      );
    }

    // 大类/小类分支节点：点击整行展开/折叠
    return Column(
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(left: 10.0 + depth * 18, right: 6),
          leading: Icon(
            node.kind == HighRiskFactorNodeKind.category ? Icons.folder_outlined : Icons.subdirectory_arrow_right,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          title: Text(
            node.name,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            node.expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
            size: 20,
          ),
          onTap: () => viewModel.toggleNode(node),
        ),
        if (node.expanded)
          for (final child in node.children) _buildTreeNode(context, viewModel, child, depth + 1),
      ],
    );
  }
}
