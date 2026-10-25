import 'package:client/models/admin_division_node.dart';
import 'package:client/view_models/system/admin_division_management_view_model.dart';
import 'package:client/views/base/base_page.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 行政区划设置页：左侧树形列表懒加载逐级展开；右侧信息表单三态——
/// 未选中给提示、选中节点可编辑（代码/名称可改、上级只读）、
/// 添加省级/下级时切换为新增表单（代码/名称清空、上级代码显示目标
/// 父级且只读）；删除为级联删除（连全部子级）。
class AdminDivisionManagementPage extends BasePage {
  const AdminDivisionManagementPage({
    super.key,
    required super.loginUser,
    required super.child,
  });

  @override
  State<AdminDivisionManagementPage> createState() => _AdminDivisionManagementPageState();
}

class _AdminDivisionManagementPageState extends State<AdminDivisionManagementPage> {
  /// dispose 中不能再用 context 取 Provider，保存实例引用供移除监听
  late final AdminDivisionManagementViewModel _viewModel;

  @override
  void initState() {
    super.initState();

    // 通过 Provider 获取全局注入的实例（不再自己 new）
    _viewModel = context.read<AdminDivisionManagementViewModel>();
    // 仅首次进入加载：切页回来保留已加载的树与选中状态
    // （VM 为全局单例，重复 loadRoots 会重建整棵树、丢失展开状态）；
    // 延迟到首帧后发起，避免 build 期间同步 notifyListeners
    if (_viewModel.roots.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _viewModel.loadRoots();
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
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          backgroundColor: theme.colorScheme.errorContainer,
          behavior: SnackBarBehavior.floating, // 悬浮式，不遮挡底部布局
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: '关闭',
            textColor: theme.colorScheme.primary,
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
    final viewModel = context.watch<AdminDivisionManagementViewModel>();

    return viewModel.loading ? const Center(child: CircularProgressIndicator()) : _buildBody(context, viewModel);
  }

  Widget _buildBody(BuildContext context, AdminDivisionManagementViewModel viewModel) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左侧：行政区划树形列表（懒加载逐级展开）
        Expanded(
          flex: 4,
          child: Card(
            color: theme.colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme,
                  title: '行政区划',
                  icon: Icons.account_tree_outlined,
                  trailing: IconButton(
                    tooltip: '添加省级区划',
                    icon: Icon(
                      Icons.add_location_alt_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    // 右侧表单切换为新增省级（上级为空）
                    onPressed: viewModel.busy ? null : () => viewModel.startCreate(),
                  ),
                ),

                Expanded(
                  child: viewModel.roots.isEmpty
                      ? const Center(child: Text('暂无行政区划数据'))
                      : ListView(
                          children: viewModel.roots.map((n) => _buildTreeTile(context, viewModel, n, 0)).toList(),
                        ),
                ),
              ],
            ),
          ),
        ),

        // 右侧：固定显示的行政区划信息卡片（按表单模式切换内容）
        Expanded(
          flex: 6,
          child: Card(
            color: theme.colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme,
                  title: '行政区划信息',
                  icon: Icons.location_city_outlined,
                ),

                Expanded(
                  child: switch (viewModel.formMode) {
                    AdminDivisionFormMode.empty => const Center(child: Text('请先在左侧选择行政区划')),
                    // key 含模式与目标父级/节点代码：切换模式或目标时表单重建，
                    // 实现新增表单清空、编辑表单回填
                    _ => _AdminDivisionDetailForm(
                      key: ValueKey(
                        viewModel.formMode == AdminDivisionFormMode.create ? 'create:${viewModel.creatingParentNode?.code ?? ''}' : 'edit:${viewModel.selectedNode!.code}',
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
  Widget _buildPanelHeader(
    ThemeData theme, {
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

  /// 递归构建树节点
  Widget _buildTreeTile(
    BuildContext context,
    AdminDivisionManagementViewModel viewModel,
    AdminDivisionNode node,
    int depth,
  ) {
    final theme = Theme.of(context);
    final selected = viewModel.selectedNode?.code == node.code;
    return Column(
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(left: 12.0 + depth * 20, right: 4),
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
                if (node.hasChildren)
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
                    // 村/居委会为最末级，不提供添加下级入口
                    if (!node.isVillageLevel)
                      PopupMenuItem(
                        value: 'add',
                        child: Row(
                          children: [
                            Icon(
                              Icons.add_location_alt_outlined,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            const Text('添加下级区划'),
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
                      // 右侧表单切换为新增下级（上级代码显示该节点）
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

  /// 删除确认对话框：先统计子树规模，提示将连带删除的下级数量
  void _confirmDelete(BuildContext context, AdminDivisionNode node) {
    final theme = Theme.of(context);
    final viewModel = context.read<AdminDivisionManagementViewModel>();
    // 打开对话框即异步取子树规模（含自身）；future 只发起一次，随重建复用
    final countFuture = viewModel.subtreeCount(node);

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
              child: FutureBuilder<int>(
                future: countFuture,
                builder: (ctx, snapshot) {
                  final subtreeText = snapshot.hasData ? (snapshot.data! > 1 ? '将同时删除其下共 ${snapshot.data!} 个行政区划（含自身）' : '该区划没有下级') : (snapshot.hasError ? '下级数量统计失败，仍将级联删除全部下级' : '正在统计下级数量…');
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
                        '确定删除「${node.name}（${node.code}）」吗？',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtreeText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
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
                              final ok = await viewModel.deleteDivision(node);
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
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        backgroundColor: theme.colorScheme.primaryContainer,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// 右侧信息表单：编辑模式（选中节点的代码/名称可改，上级只读）与
/// 新增模式（代码/名称清空待录，上级代码显示目标父级且只读）。
/// 以模式+目标代码为 ValueKey，由页面在切换时重建实现清空/回填。
class _AdminDivisionDetailForm extends StatefulWidget {
  const _AdminDivisionDetailForm({
    super.key,
    required this.viewModel,
  });

  final AdminDivisionManagementViewModel viewModel;

  @override
  State<_AdminDivisionDetailForm> createState() => _AdminDivisionDetailFormState();
}

class _AdminDivisionDetailFormState extends State<_AdminDivisionDetailForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final viewModel = widget.viewModel;
    final editing = viewModel.formMode == AdminDivisionFormMode.edit ? viewModel.selectedNode : null;
    _codeController = TextEditingController(text: editing?.code ?? '');
    _nameController = TextEditingController(text: editing?.name ?? '');
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewModel = widget.viewModel;
    final creating = viewModel.formMode == AdminDivisionFormMode.create;
    final editingNode = viewModel.selectedNode;
    // 上级代码：编辑态取节点父级；新增态取目标父节点（省级为空）
    final parentCode = creating ? viewModel.creatingParentNode?.code : editingNode?.parentCode;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 行政区划代码（新增录入 / 编辑修改，修改后级联更新下级父引用）
            TextFormField(
              controller: _codeController,
              autofocus: creating,
              keyboardType: TextInputType.number,
              style: theme.textTheme.bodyMedium,
              decoration: _inputDecoration(
                theme,
                '行政区划代码',
                creating ? '2~12 位数字' : '2~12 位数字，修改后下级父引用同步更新',
              ),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return '请输入行政区划代码';
                if (!RegExp(r'^\d{2,12}$').hasMatch(value)) return '代码应为 2~12 位数字';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // 名称（可编辑）
            TextFormField(
              controller: _nameController,
              style: theme.textTheme.bodyMedium,
              decoration: _inputDecoration(theme, '行政区划名称', null),
              validator: (v) => (v == null || v.trim().isEmpty) ? '请输入行政区划名称' : null,
            ),
            const SizedBox(height: 12),

            // 上级行政区划代码（只读：新增时为录入目标父级，不允许经表单调整）
            TextFormField(
              initialValue: parentCode ?? '（省级）',
              readOnly: true,
              style: theme.textTheme.bodyMedium,
              decoration: _readOnlyDecoration(theme, '上级行政区划代码'),
            ),
            const SizedBox(height: 20),

            // 操作按钮：新增模式可取消，编辑模式仅保存
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (creating) ...[
                  TextButton(
                    onPressed: viewModel.busy ? null : viewModel.cancelCreate,
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: viewModel.busy ? null : _save,
                    icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                    label: const Text('添加'),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: viewModel.busy ? null : _save,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('保存'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(ThemeData theme, String label, String? hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.colorScheme.primary),
      ),
    );
  }

  InputDecoration _readOnlyDecoration(ThemeData theme, String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final viewModel = widget.viewModel;
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    // 提交前记录模式：新增成功后 formMode 已切回编辑态
    final wasCreating = viewModel.formMode == AdminDivisionFormMode.create;

    final ok = wasCreating ? await viewModel.createDivision(parent: viewModel.creatingParentNode, code: code, name: name) : await viewModel.updateDivision(viewModel.selectedNode!, newCode: code, name: name);
    if (!mounted || !ok) return;
    // 失败提示由 errorMsg 监听统一弹出
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasCreating ? '新增成功' : '修改成功',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        backgroundColor: theme.colorScheme.primaryContainer,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
