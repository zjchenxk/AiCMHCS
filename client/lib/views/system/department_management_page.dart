import 'package:client/models/department_tree_node.dart';
import 'package:client/view_models/system/department_management_view_model.dart';
import 'package:client/views/base/base_page.dart';
import 'package:client/views/system/department_info_form.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 科室管理页：绑定当前登录用户的所属医院。左侧「医院→院区→科室→
/// 下级科室」树（医院未设置院区时无院区层，科室直挂医院根，此时医院
/// 根可新增科室；已设置院区时顶级科室只能挂院区下）；右侧信息表单
/// 三态——未选中给提示、选中科室可编辑、新增时切换为新增表单
/// （表单清空，挂载目标为发起新增的节点）。
class DepartmentManagementPage extends BasePage {
  const DepartmentManagementPage({super.key, required super.loginUser, required super.child});

  @override
  State<DepartmentManagementPage> createState() => _DepartmentManagementPageState();
}

class _DepartmentManagementPageState extends State<DepartmentManagementPage> {
  /// dispose 中不能再用 context 取 Provider，保存实例引用供移除监听
  late final DepartmentManagementViewModel _viewModel;

  @override
  void initState() {
    super.initState();

    // 通过 Provider 获取全局注入的实例（不再自己 new）
    _viewModel = context.read<DepartmentManagementViewModel>();
    // 每次进入页面按登录用户所属医院加载；VM 内部对同一医院已加载的
    // 情况直接跳过（切页保留状态），医院变化（切换账号）时强制重拉；
    // 延迟到首帧后发起，避免 build 期间同步 notifyListeners
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _viewModel.loadData(widget.loginUser.hospId, widget.loginUser.hospName);
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
    final viewModel = context.watch<DepartmentManagementViewModel>();

    return viewModel.loading ? const Center(child: CircularProgressIndicator()) : _buildBody(context, viewModel);
  }

  Widget _buildBody(BuildContext context, DepartmentManagementViewModel viewModel) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左侧：科室树（医院→院区→科室→下级科室）
        Expanded(
          flex: 4,
          child: Card(
            color: Theme.of(context).colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: Theme.of(context),
                  title: '科室列表',
                  icon: Icons.account_tree_outlined,
                  trailing: IconButton(
                    tooltip: '刷新',
                    icon: Icon(
                      Icons.refresh_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    // 手动整表重拉（院区/科室在兄弟页面改动后的兜底
                    // 入口；进入页面时 loadData 已自动重拉）
                    onPressed: viewModel.loading || viewModel.busy
                        ? null
                        : () => viewModel.loadData(
                            widget.loginUser.hospId,
                            widget.loginUser.hospName,
                          ),
                  ),
                ),
                Expanded(
                  child: viewModel.unbound
                      ? const Center(child: Text('当前登录用户未设置所属医院，无法管理科室'))
                      : viewModel.root == null
                      ? const Center(child: Text('暂无数据'))
                      : ListView(
                          children: [
                            _buildTreeTile(
                              context,
                              viewModel,
                              viewModel.root!,
                              0,
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),

        // 右侧：科室信息表单（按表单模式切换内容）
        Expanded(
          flex: 6,
          child: Card(
            color: Theme.of(context).colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: Theme.of(context),
                  title: '科室信息',
                  icon: Icons.info_outlined,
                ),
                Expanded(
                  child: switch (viewModel.formMode) {
                    DepartmentFormMode.empty => Center(
                      child: Text(
                        viewModel.unbound ? '当前登录用户未设置所属医院' : '请先在左侧选择科室',
                      ),
                    ),
                    // key 含模式、挂载目标与科室 ID：切换模式或目标时
                    // 表单重建，实现新增表单清空、编辑表单回填
                    _ => DepartmentInfoForm(
                      key: ValueKey(
                        viewModel.formMode == DepartmentFormMode.create ? 'create:${viewModel.createParent?.key ?? ''}' : 'edit:${viewModel.selectedDepartment!.id}',
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

  /// 递归构建树节点：医院根（无院区时可新增科室）、院区（可新增科室）、
  /// 科室（可新增下级科室/删除，点击选中右侧编辑）。
  Widget _buildTreeTile(BuildContext context, DepartmentManagementViewModel viewModel, DepartmentTreeNode node, int depth) {
    final theme = Theme.of(context);
    final selected = viewModel.selectedNode?.key == node.key && viewModel.formMode != DepartmentFormMode.create;
    final icon = switch (node.type) {
      DepartmentTreeNodeType.hospital => Icons.local_hospital_outlined,
      DepartmentTreeNodeType.campus => Icons.domain_outlined,
      DepartmentTreeNodeType.department => Icons.meeting_room_outlined,
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
          subtitle: node.type == DepartmentTreeNodeType.department && node.department != null && node.department!.code.isNotEmpty
              ? Text(
                  '代码：${node.department!.code}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
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

  /// 节点行尾：展开/折叠箭头 + 按类型提供的操作菜单。
  ///
  /// 医院根仅在未设置院区时提供「新增科室」（已设置院区时顶级科室
  /// 必须挂院区下）；院区提供「新增科室」；科室提供「新增下级科室」
  /// 与「删除」。
  Widget _buildNodeTrailing(BuildContext context, DepartmentManagementViewModel viewModel, DepartmentTreeNode node) {
    final theme = Theme.of(context);
    final isHospitalRoot = node.type == DepartmentTreeNodeType.hospital;
    //允许在医院结点下新增科室，不管是否有院区。chenxk，2026-11-10
    //final hospitalAddable = isHospitalRoot && !viewModel.hasCampuses;
    final hospitalAddable = isHospitalRoot;
    final menuAddable = !isHospitalRoot && (node.type == DepartmentTreeNodeType.campus || node.type == DepartmentTreeNodeType.department);
    final deletable = node.type == DepartmentTreeNodeType.department;

    if (!hospitalAddable && !menuAddable) {
      return !node.isLeaf
          ? InkWell(
              onTap: () => viewModel.toggleExpand(node),
              child: Icon(
                node.expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                size: 20,
              ),
            )
          : const SizedBox(width: 20);
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
                    Text(
                      node.type == DepartmentTreeNodeType.department ? '新增下级科室' : '新增科室',
                    ),
                  ],
                ),
              ),
              if (deletable)
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

  /// 删除确认对话框（毛玻璃）；存在下级科室时后端阻止，提示由
  /// errorMsg 监听统一弹出。
  void _confirmDelete(BuildContext context, DepartmentManagementViewModel viewModel, DepartmentTreeNode node) {
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
                    '确定删除科室「${node.name}」吗？存在下级科室时需先删除下级。',
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
                          final ok = await viewModel.deleteDepartment(node);
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
