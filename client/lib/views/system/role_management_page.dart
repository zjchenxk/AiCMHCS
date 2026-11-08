import 'package:client/models/menu_tree_node.dart';
import 'package:client/utils/menu_icons.dart';
import 'package:client/view_models/system/role_management_view_model.dart';
import 'package:client/views/base/base_page.dart';
import 'package:client/views/system/role_form_dialog.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 角色管理页：角色归属当前登录用户的所属医院。左侧该医院的角色列表
/// （选中 + 编辑/删除，头部按钮新增，录入经毛玻璃表单对话框）；右侧
/// 为选中角色的菜单权限树——显示 MENU_ICON / ITEM_CODE / ITEM_NAME，
/// 按 ITEM_CODE 逐级排序，复选框勾选级联，支持全选/取消全选与整体
/// 保存（后端全量覆盖）。
class RoleManagementPage extends BasePage {
  const RoleManagementPage({
    super.key,
    required super.loginUser,
    required super.child,
  });

  @override
  State<RoleManagementPage> createState() => _RoleManagementPageState();
}

class _RoleManagementPageState extends State<RoleManagementPage> {
  /// dispose 中不能再用 context 取 Provider，保存实例引用供移除监听
  late final RoleManagementViewModel _viewModel;

  @override
  void initState() {
    super.initState();

    // 通过 Provider 获取全局注入的实例（不再自己 new）
    _viewModel = context.read<RoleManagementViewModel>();
    // 每次进入页面按登录用户所属医院加载（角色 + 菜单权限树）；
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
    final viewModel = context.watch<RoleManagementViewModel>();

    return viewModel.loading ? const Center(child: CircularProgressIndicator()) : _buildBody(context, viewModel);
  }

  Widget _buildBody(BuildContext context, RoleManagementViewModel viewModel) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左侧：角色列表（归属登录用户所属医院）
        Expanded(
          flex: 4,
          child: Card(
            color: Theme.of(context).colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: Theme.of(context),
                  title: '角色列表',
                  icon: Icons.group_outlined,
                  trailing: IconButton(
                    tooltip: '新增角色',
                    icon: Icon(
                      Icons.add_business_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    // 未设置所属医院时禁用新增
                    onPressed: viewModel.unbound || viewModel.busy ? null : () => _showRoleForm(viewModel),
                  ),
                ),
                Expanded(
                  child: viewModel.unbound
                      ? const Center(child: Text('当前登录用户未设置所属医院，无法管理角色'))
                      : viewModel.roles.isEmpty
                      ? const Center(child: Text('暂无角色，点击右上角新增'))
                      : ListView(
                          children: viewModel.roles.map((r) => _buildRoleTile(context, viewModel, r)).toList(),
                        ),
                ),
              ],
            ),
          ),
        ),

        // 右侧：选中角色的菜单权限树
        Expanded(
          flex: 6,
          child: Card(
            color: Theme.of(context).colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: Theme.of(context),
                  title: viewModel.selectedRole == null ? '菜单权限' : '菜单权限 - ${viewModel.selectedRole!.roleName}',
                  icon: Icons.admin_panel_settings_outlined,
                  trailing: _buildPermHeaderActions(context, viewModel),
                ),
                Expanded(child: _buildPermBody(context, viewModel)),
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

  /// 右侧面板头部操作：全选/取消全选 + 保存
  Widget _buildPermHeaderActions(BuildContext context, RoleManagementViewModel viewModel) {
    final theme = Theme.of(context);
    final enabled = viewModel.selectedRole != null && !viewModel.permLoading && !viewModel.permBusy;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '已选 ${viewModel.checkedCount} 项',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 4),
        TextButton(
          onPressed: enabled ? viewModel.toggleCheckAll : null,
          child: Text(viewModel.allChecked ? '取消全选' : '全选'),
        ),
        const SizedBox(width: 4),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
          onPressed: enabled && viewModel.permDirty ? viewModel.savePermissions : null,
          icon: viewModel.permBusy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined, size: 16),
          label: const Text('保存'),
        ),
      ],
    );
  }

  /// 右侧面板主体：未选中/加载中/无菜单/权限树四态
  Widget _buildPermBody(BuildContext context, RoleManagementViewModel viewModel) {
    if (viewModel.selectedRole == null) {
      return Center(
        child: Text(viewModel.unbound ? '当前登录用户未设置所属医院' : '请先在左侧选择角色'),
      );
    }
    if (viewModel.permLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (viewModel.menuEmpty) {
      return const Center(child: Text('暂无菜单项目，请先在菜单管理中维护'));
    }
    return ListView(
      children: [
        for (final root in viewModel.menuRoots) _buildPermTile(context, viewModel, root, 0),
      ],
    );
  }

  /// 递归构建权限树节点行：复选框（三态）+ 图标 + 名称 + 编码，
  /// 行尾展开/折叠箭头；点击复选框或行整棵子树级联勾选/取消。
  /// 图标优先取菜单设置的 MENU_ICON，未设置按类型回退。
  Widget _buildPermTile(
    BuildContext context,
    RoleManagementViewModel viewModel,
    MenuTreeNode node,
    int depth,
  ) {
    final theme = Theme.of(context);
    final state = viewModel.nodeCheckState(node);
    final icon = menuIconOrFallback(
      node.menu.menuIcon,
      fallback: menuItemTypeIcon(node.menu.itemType),
    );
    return Column(
      children: [
        InkWell(
          onTap: () => viewModel.toggleNodeCheck(node),
          child: Padding(
            padding: EdgeInsets.only(left: 6.0 + depth * 20, right: 4),
            child: Row(
              children: [
                Checkbox(
                  tristate: true,
                  value: state,
                  visualDensity: VisualDensity.compact,
                  onChanged: (_) => viewModel.toggleNodeCheck(node),
                ),
                const SizedBox(width: 4),
                Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.name,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // 编码定宽列：各行同一位置右对齐（列宽覆盖 ITEM_CODE 上限 10 字符）
                SizedBox(
                  width: 72,
                  child: Text(
                    node.menu.itemCode,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 行尾图标固定占位：叶子行同样预留，保证编码列各行恒对齐
                SizedBox(
                  width: 28,
                  child: node.isLeaf
                      ? null
                      : Center(
                          child: InkWell(
                            onTap: () => viewModel.toggleExpand(node),
                            child: Icon(
                              node.expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                              size: 20,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        if (node.expanded)
          ...node.children.map(
            (c) => _buildPermTile(context, viewModel, c, depth + 1),
          ),
      ],
    );
  }

  /// 角色列表行：主显名称，副显编码/备注；点击选中（右侧加载权限），
  /// 行尾编辑（表单对话框）与删除（确认对话框）
  Widget _buildRoleTile(BuildContext context, RoleManagementViewModel viewModel, Role role) {
    final theme = Theme.of(context);
    final selected = viewModel.selectedRole?.id == role.id;
    final subtitleParts = [
      if (role.roleCode.isNotEmpty) '编码：${role.roleCode}',
      if (role.remark != null && role.remark!.isNotEmpty) '备注：${role.remark}',
    ];
    return ListTile(
      dense: true,
      selected: selected,
      leading: Icon(
        Icons.group_outlined,
        size: 20,
        color: selected ? theme.colorScheme.primary : null,
      ),
      title: Text(
        role.roleName,
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
      trailing: SizedBox(
        width: 72,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: '编辑',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.edit_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              onPressed: viewModel.busy ? null : () => _showRoleForm(viewModel, role: role),
            ),
            IconButton(
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: theme.colorScheme.error,
              ),
              onPressed: viewModel.busy ? null : () => _confirmDelete(context, viewModel, role),
            ),
          ],
        ),
      ),
      onTap: () => viewModel.selectRole(role),
    );
  }

  /// 新增/编辑角色表单对话框（毛玻璃），成功后提示（对话框内已处理
  /// 失败内联展示）。
  Future<void> _showRoleForm(RoleManagementViewModel viewModel, {Role? role}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => RoleFormDialog(viewModel: viewModel, role: role),
    );
    if (!mounted || ok != true) return;
    _showResultSnackBar(role == null ? '新增成功' : '保存成功');
  }

  /// 删除确认对话框（毛玻璃）
  void _confirmDelete(BuildContext context, RoleManagementViewModel viewModel, Role role) {
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
                    '确定删除角色「${role.roleName}」吗？其菜单权限配置将一并删除。',
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
                          final ok = await viewModel.deleteRole(role);
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
