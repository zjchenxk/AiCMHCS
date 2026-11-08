import 'package:client/models/menu_tree_node.dart';
import 'package:client/utils/menu_icons.dart';
import 'package:client/view_models/system/menu_management_view_model.dart';
import 'package:client/views/base/base_page.dart';
import 'package:client/views/system/menu_info_form.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 菜单管理页：左侧「模块→菜单→操作」项目树（顶级项目为多根，可
/// 逐级新增下级项目）；右侧信息表单三态——未选中给提示、选中项目可
/// 编辑、新增时切换为新增表单（表单清空，挂载目标为发起新增的节点，
/// 面板头的「新增顶级项目」挂顶级）。
class MenuManagementPage extends BasePage {
  const MenuManagementPage({
    super.key,
    required super.loginUser,
    required super.child,
  });

  @override
  State<MenuManagementPage> createState() => _MenuManagementPageState();
}

class _MenuManagementPageState extends State<MenuManagementPage> {
  /// dispose 中不能再用 context 取 Provider，保存实例引用供移除监听
  late final MenuManagementViewModel _viewModel;

  @override
  void initState() {
    super.initState();

    // 通过 Provider 获取全局注入的实例（不再自己 new）
    _viewModel = context.read<MenuManagementViewModel>();
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
    final viewModel = context.watch<MenuManagementViewModel>();

    return viewModel.loading ? const Center(child: CircularProgressIndicator()) : _buildBody(context, viewModel);
  }

  Widget _buildBody(BuildContext context, MenuManagementViewModel viewModel) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左侧：菜单项目树（模块→菜单→操作）
        Expanded(
          flex: 4,
          child: Card(
            color: Theme.of(context).colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: Theme.of(context),
                  title: '菜单项目',
                  icon: Icons.account_tree_outlined,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '新增顶级项目',
                        icon: Icon(
                          Icons.add_business_outlined,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        // 顶级新增（挂载目标为空）；树为空时也可用
                        onPressed: viewModel.loading || viewModel.busy ? null : () => viewModel.startCreate(null),
                      ),
                      IconButton(
                        tooltip: '刷新',
                        icon: Icon(
                          Icons.refresh_outlined,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        // 手动整表重拉（进入页面时 loadData 已自动重拉）
                        onPressed: viewModel.loading || viewModel.busy ? null : viewModel.loadData,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: viewModel.isEmpty
                      ? const Center(child: Text('暂无菜单项目，请新增顶级项目'))
                      : ListView(
                          children: [
                            for (final root in viewModel.roots) _buildTreeTile(context, viewModel, root, 0),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),

        // 右侧：菜单项目信息表单（按表单模式切换内容）
        Expanded(
          flex: 6,
          child: Card(
            color: Theme.of(context).colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: Theme.of(context),
                  title: '项目信息',
                  icon: Icons.info_outlined,
                ),
                Expanded(
                  child: switch (viewModel.formMode) {
                    MenuFormMode.empty => const Center(child: Text('请先在左侧选择菜单项目')),
                    // key 含模式、挂载目标与项目 ID：切换模式或目标时
                    // 表单重建，实现新增表单清空、编辑表单回填
                    _ => MenuInfoForm(
                      key: ValueKey(
                        viewModel.formMode == MenuFormMode.create ? 'create:${viewModel.createParent?.key ?? 'top'}' : 'edit:${viewModel.selectedMenu!.id}',
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

  /// 递归构建树节点：项目（可新增下级项目/删除，点击选中右侧编辑）。
  /// 图标优先取项目设置的 MENU_ICON，未设置按类型回退。
  Widget _buildTreeTile(
    BuildContext context,
    MenuManagementViewModel viewModel,
    MenuTreeNode node,
    int depth,
  ) {
    final theme = Theme.of(context);
    final selected = viewModel.selectedNode?.key == node.key && viewModel.formMode != MenuFormMode.create;
    final icon = menuIconOrFallback(
      node.menu.menuIcon,
      fallback: menuItemTypeIcon(node.menu.itemType),
    );
    return Column(
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(left: 12.0 + depth * 20, right: 4),
          selected: selected,
          leading: Icon(
            icon,
            size: 18,
            color: selected ? theme.colorScheme.primary : null,
          ),
          title: Text(
            node.name,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? theme.colorScheme.primary : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${menuItemTypeLabel(node.menu.itemType)} · ${node.menu.itemCode}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: _buildNodeTrailing(context, viewModel, node),
          onTap: () => viewModel.selectNode(node),
        ),
        if (node.expanded)
          ...node.children.map(
            (c) => _buildTreeTile(context, viewModel, c, depth + 1),
          ),
      ],
    );
  }

  /// 节点行尾：展开/折叠箭头 + 操作菜单（新增下级项目/删除）。
  Widget _buildNodeTrailing(
    BuildContext context,
    MenuManagementViewModel viewModel,
    MenuTreeNode node,
  ) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 72,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!node.isLeaf)
            InkWell(
              onTap: () => viewModel.toggleExpand(node),
              child: Icon(
                node.expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                size: 20,
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'add',
                child: Row(
                  children: [
                    Icon(
                      Icons.add_business_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    const Text('新增下级项目'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    const Text('删除'),
                  ],
                ),
              ),
            ],
            tooltip: '更多操作...',
            color: theme.colorScheme.surface,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            onSelected: (action) {
              if (action == 'add') {
                // 右侧表单切换为新增（顶部显示挂载位置）
                viewModel.startCreate(node);
              } else if (action == 'delete') {
                _confirmDelete(context, viewModel, node);
              }
            },
          ),
        ],
      ),
    );
  }

  /// 删除确认对话框（毛玻璃）；存在下级项目时后端阻止，提示由
  /// errorMsg 监听统一弹出。
  void _confirmDelete(
    BuildContext context,
    MenuManagementViewModel viewModel,
    MenuTreeNode node,
  ) {
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
                    '确定删除菜单项目「${node.name}」吗？存在下级项目时需先删除下级。',
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
                          final ok = await viewModel.deleteMenu(node);
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
