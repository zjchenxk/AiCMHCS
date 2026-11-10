import 'package:client/models/user_tree_node.dart';
import 'package:client/view_models/system/user_management_view_model.dart';
import 'package:client/views/base/base_page.dart';
import 'package:client/views/system/user_info_form.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 用户管理页：绑定当前登录用户的所属医院。左侧「科室→下级科室→
/// 用户」树（用户挂其归属科室下，未挂科室的收入「未分配科室」；医院
/// 尚未设置任何科室时显示引导提示，不能新增用户）；右侧信息表单
/// 三态——未选中给提示、选中用户可编辑（含角色多选）、在某科室下
/// 新增时切换为新增表单（挂载科室为发起新增的节点）。
class UserManagementPage extends BasePage {
  const UserManagementPage({
    super.key,
    required super.loginUser,
    required super.child,
  });

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  /// dispose 中不能再用 context 取 Provider，保存实例引用供移除监听
  late final UserManagementViewModel _viewModel;

  @override
  void initState() {
    super.initState();

    // 通过 Provider 获取全局注入的实例（不再自己 new）
    _viewModel = context.read<UserManagementViewModel>();
    // 每次进入页面按登录用户所属医院强制重拉（科室/角色管理等兄弟
    // 页面可能已改动数据）；延迟到首帧后发起，避免 build 期间同步
    // notifyListeners
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _viewModel.loadData(widget.loginUser.hospId);
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
    final viewModel = context.watch<UserManagementViewModel>();

    return viewModel.loading ? const Center(child: CircularProgressIndicator()) : _buildBody(context, viewModel);
  }

  Widget _buildBody(BuildContext context, UserManagementViewModel viewModel) {
    final theme = Theme.of(context);
    // 右侧面板标题随表单形态变化：新增显示挂载科室、编辑显示用户姓名
    final String formTitle = switch (viewModel.formMode) {
      UserFormMode.create => '新增用户 - ${viewModel.createParent?.name ?? ''}',
      UserFormMode.edit => '用户信息 - ${viewModel.selectedUser?.userName ?? ''}',
      UserFormMode.empty => '用户信息',
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左侧：科室→下级科室→用户树
        Expanded(
          flex: 4,
          child: Card(
            color: theme.colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: theme,
                  title: '用户列表',
                  icon: Icons.people_outline,
                  trailing: IconButton(
                    tooltip: '刷新',
                    icon: Icon(
                      Icons.refresh_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    // 手动整表重拉（科室/角色在兄弟页面改动后的兜底
                    // 入口；进入页面时 loadData 已自动重拉）
                    onPressed: viewModel.loading || viewModel.busy ? null : () => viewModel.loadData(widget.loginUser.hospId),
                  ),
                ),
                Expanded(
                  child: viewModel.unbound
                      ? const Center(child: Text('当前登录用户未设置所属医院，无法管理用户'))
                      : viewModel.departmentEmpty
                      ? _buildEmptyDepartment(theme)
                      : viewModel.roots.isEmpty
                      ? const Center(child: Text('暂无数据'))
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

        // 右侧：用户信息表单（按表单模式切换内容）
        Expanded(
          flex: 6,
          child: Card(
            color: theme.colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: theme,
                  title: formTitle,
                  icon: Icons.badge_outlined,
                ),
                Expanded(
                  child: switch (viewModel.formMode) {
                    UserFormMode.empty => Center(
                      child: Text(
                        viewModel.unbound
                            ? '当前登录用户未设置所属医院'
                            : viewModel.departmentEmpty
                            ? '未添加科室，不能新增用户'
                            : '请先在左侧选择用户，或点击科室节点的 + 新增用户',
                      ),
                    ),
                    // key 含模式、挂载目标与用户 ID：切换模式或目标时
                    // 表单重建，实现新增表单清空、编辑表单回填
                    _ => UserInfoForm(
                      key: ValueKey(
                        viewModel.formMode == UserFormMode.create ? 'create:${viewModel.createParent?.key ?? ''}' : 'edit:${viewModel.selectedUser!.id}',
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

  /// 医院尚未设置任何科室的空态引导（需求约定：未添加科室不能新增
  /// 用户——先到科室管理建科室）。
  Widget _buildEmptyDepartment(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_off_outlined,
            size: 40,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            '未添加科室，不能新增用户',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '请先在「系统管理 → 科室管理」中添加科室',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
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

  /// 递归构建树节点：科室（可新增用户、点击展开/折叠）、用户（点击
  /// 选中右侧编辑）。「未分配科室」虚拟节点仅展示收容的用户。
  Widget _buildTreeTile(
    BuildContext context,
    UserManagementViewModel viewModel,
    UserTreeNode node,
    int depth,
  ) {
    final theme = Theme.of(context);
    final selected = node.type == UserTreeNodeType.user && viewModel.selectedUser?.id == node.id && viewModel.formMode != UserFormMode.create;
    final icon = switch (node.type) {
      UserTreeNodeType.department => Icons.meeting_room_outlined,
      UserTreeNodeType.user => Icons.person_outline,
    };
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
          subtitle: node.user != null
              ? Text(
                  '${node.user!.userCode}　${_userTypeLabel(node.user!.userType)}${node.user!.status == '0' ? '（已停用）' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          trailing: _buildNodeTrailing(context, viewModel, node),
          // 科室节点点击展开/折叠（无右侧表单意义）；用户节点点击选中
          onTap: () => node.type == UserTreeNodeType.user ? viewModel.selectUser(node.user!) : viewModel.toggleExpand(node),
        ),
        if (node.expanded)
          ...node.children.map(
            (c) => _buildTreeTile(context, viewModel, c, depth + 1),
          ),
      ],
    );
  }

  /// 节点行尾：展开/折叠箭头 + 科室节点的「新增用户」按钮（虚拟节点
  /// 与用户节点无操作，空占位保持右缘对齐）。
  Widget _buildNodeTrailing(
    BuildContext context,
    UserManagementViewModel viewModel,
    UserTreeNode node,
  ) {
    final theme = Theme.of(context);
    final addable = node.type == UserTreeNodeType.department && node.department != null;
    if (!addable) {
      return const SizedBox(width: 72);
    }

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
          IconButton(
            tooltip: '新增用户',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.person_add_alt_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            // 右侧表单切换为新增（挂载科室为该节点）
            onPressed: () => viewModel.startCreate(node),
          ),
        ],
      ),
    );
  }

  /// 用户类别显示标签（存量 TEACHER/PARENT 等非标准值原样显示）。
  String _userTypeLabel(String? userType) {
    if (userType == null || userType.isEmpty) return '';
    return switch (userType) {
      'ADMIN' => '管理员',
      'DOCTOR' => '医生',
      'NURSE' => '护士',
      'TECHNICIAN' => '技师',
      'TEACHER' => '教师',
      'PARENT' => '家长',
      _ => userType,
    };
  }
}
