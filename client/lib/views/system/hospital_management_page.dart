import 'package:client/models/hospital_tree_node.dart';
import 'package:client/view_models/system/hospital_management_view_model.dart';
import 'package:client/views/base/base_page.dart';
import 'package:client/views/system/hospital_info_form.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 医院管理页：左侧医联体树形列表（全量加载）；右侧信息表单三态——
/// 未选中给提示、选中医院可编辑（基本信息可改、上级只读）、添加顶级/
/// 下级医院时切换为新增表单（表单清空、上级医院显示目标父级且只读）；
/// 删除为级联删除（连全部下级）。
class HospitalManagementPage extends BasePage {
  const HospitalManagementPage({
    super.key,
    required super.loginUser,
    required super.child,
  });

  @override
  State<HospitalManagementPage> createState() => _HospitalManagementPageState();
}

class _HospitalManagementPageState extends State<HospitalManagementPage> {
  /// dispose 中不能再用 context 取 Provider，保存实例引用供移除监听
  late final HospitalManagementViewModel _viewModel;

  @override
  void initState() {
    super.initState();

    // 通过 Provider 获取全局注入的实例（不再自己 new）
    _viewModel = context.read<HospitalManagementViewModel>();
    // 仅首次进入加载：切页回来保留已加载的树与选中状态
    // （VM 为全局单例，重复 loadHospitals 会重建整棵树、丢失展开状态）；
    // 延迟到首帧后发起，避免 build 期间同步 notifyListeners
    if (_viewModel.hospitalTree.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _viewModel.loadHospitals();
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
    final viewModel = context.watch<HospitalManagementViewModel>();

    return viewModel.loading ? const Center(child: CircularProgressIndicator()) : _buildBody(context, viewModel);
  }

  Widget _buildBody(BuildContext context, HospitalManagementViewModel viewModel) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左侧：医院树形列表
        Expanded(
          flex: 4,
          child: Card(
            color: theme.colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme,
                  title: '医院列表',
                  icon: Icons.account_tree_outlined,
                  trailing: IconButton(
                    tooltip: '添加顶级医院',
                    icon: Icon(
                      Icons.add_home_work_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    // 右侧表单切换为新增顶级（上级为空）
                    onPressed: viewModel.busy ? null : () => viewModel.startCreate(),
                  ),
                ),

                Expanded(
                  child: viewModel.hospitalTree.isEmpty
                      ? const Center(child: Text('暂无医院数据'))
                      : ListView(
                          children: viewModel.hospitalTree.map((n) => _buildTreeTile(context, viewModel, n, 0)).toList(),
                        ),
                ),
              ],
            ),
          ),
        ),

        // 右侧：固定显示的医院信息卡片（按表单模式切换内容）
        Expanded(
          flex: 6,
          child: Card(
            color: theme.colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme,
                  title: '医院信息',
                  icon: Icons.local_hospital_outlined,
                ),

                Expanded(
                  child: switch (viewModel.formMode) {
                    HospitalFormMode.empty => const Center(child: Text('请先在左侧选择医院')),
                    // key 含模式与目标父级/医院 ID：切换模式或目标时表单重建，
                    // 实现新增表单清空、编辑表单回填
                    _ => HospitalInfoForm(
                      key: ValueKey(
                        viewModel.formMode == HospitalFormMode.create ? 'create:${viewModel.creatingParentNode?.id ?? ''}' : 'edit:${viewModel.selectedNode!.id}',
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
  Widget _buildPanelHeader(ThemeData theme, {required String title, required IconData icon, Widget? trailing}) {
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

  /// 递归构建树节点
  Widget _buildTreeTile(BuildContext context, HospitalManagementViewModel viewModel, HospitalTreeNode node, int depth) {
    final theme = Theme.of(context);
    final selected = viewModel.selectedNode?.id == node.id;
    return Column(
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(left: 12.0 + depth * 20, right: 4),
          leading: Icon(
            Icons.home_work_outlined,
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
          trailing: SizedBox(
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
                            Icons.add_home_work_outlined,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          const Text('添加下级医院'),
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
                      // 右侧表单切换为新增下级（上级医院显示该节点）
                      viewModel.startCreate(parent: node);
                    } else if (action == 'delete') {
                      _confirmDelete(context, node);
                    }
                  },
                ),
              ],
            ),
          ),
          selected: selected,
          onTap: () => viewModel.selectNode(node),
        ),
        if (node.expanded)
          ...node.children.map(
            (c) => _buildTreeTile(context, viewModel, c, depth + 1),
          ),
      ],
    );
  }

  /// 删除确认对话框：先统计子树规模与院区数；子树内存在院区时阻止
  /// 删除（后端 deleteSubtree 同规则兜底校验）
  void _confirmDelete(BuildContext context, HospitalTreeNode node) {
    final theme = Theme.of(context);
    final viewModel = context.read<HospitalManagementViewModel>();
    // 打开对话框即异步取子树规模与院区数；future 只发起一次，随重建复用
    final infoFuture = viewModel.subtreeInfo(node);

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
              child: FutureBuilder<(int, int)>(
                future: infoFuture,
                builder: (ctx, snapshot) {
                  final info = snapshot.data;
                  final blocked = (info?.$2 ?? 0) > 0;
                  final subtreeText = snapshot.hasData ? (info!.$1 > 1 ? '将同时删除其下共 ${info.$1} 所医院（含自身）' : '该医院没有下级') : (snapshot.hasError ? '下级数量统计失败，仍将级联删除全部下级' : '正在统计下级数量…');
                  return Column(
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
                        '确定删除医院「${node.name}」吗？',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtreeText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      if (blocked) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.block_outlined,
                              color: theme.colorScheme.error,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '该医院（含下级）下存在 ${info!.$2} 个院区，请先删除院区后，再删除医院',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(blocked ? '知道了' : '取消'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.error,
                              foregroundColor: theme.colorScheme.onError,
                            ),
                            // 存在院区时禁用（后端同规则兜底）
                            onPressed: blocked
                                ? null
                                : () async {
                                    Navigator.pop(ctx);
                                    final ok = await viewModel.deleteHospital(node);
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
                  );
                },
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
