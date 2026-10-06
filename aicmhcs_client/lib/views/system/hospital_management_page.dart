import 'package:aicmhcs_client/models/hospital_tree_node.dart';
import 'package:aicmhcs_client/view_models/system/hospital_management_view_model.dart';
import 'package:aicmhcs_client/views/base/base_page.dart';
import 'package:aicmhcs_client/views/system/hospital_info_form.dart';
import 'package:aicmhcs_client/widgets/glass_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

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
  @override
  void initState() {
    super.initState();

    // 通过 Provider 获取全局注入的实例（不再自己 new）
    final viewModel = context.read<HospitalManagementViewModel>();
    viewModel.loadOrganTree();

    // 监听 errorMsg 变化，用 SnackBar 提示错误
    viewModel.addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    // 注意：实例来自 Provider 全局注入，这里只移除监听，不要 viewModel.dispose()
    context.read<HospitalManagementViewModel>().removeListener(_onViewModelChanged);
    super.dispose();
  }

  void _onViewModelChanged() {
    if (!mounted) return;

    //获取当前主题
    final ThemeData theme = Theme.of(context);

    final viewModel = context.read<HospitalManagementViewModel>();
    if (viewModel.errorMsg != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            viewModel.errorMsg!,
            style: theme.textTheme.bodyMedium,
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating, // 悬浮式，不遮挡底部布局
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: '关闭',
            textColor: Colors.white,
            onPressed: viewModel.clearError,
          ),
        ),
      );
      // 提示后立即清空，避免同一错误重复弹出
      viewModel.clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    //获取当前主题
    final ThemeData theme = Theme.of(context);

    // 使用 watch 监听变化，VM notifyListeners 后自动刷新
    final viewModel = context.watch<HospitalManagementViewModel>();

    return viewModel.loading ? const Center(child: CircularProgressIndicator()) : _buildBody(theme, viewModel);
  }

  Widget _buildBody(ThemeData theme, HospitalManagementViewModel viewModel) {
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
                Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  color: theme.colorScheme.primaryContainer,
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_tree,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '医院列表',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: '添加顶级医院',
                        icon: Icon(
                          Icons.add_home_work_outlined,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        onPressed: () => _showAddRootDialog(theme, Icons.home_work_outlined),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: viewModel.organTree.isEmpty
                      ? const Center(child: Text('暂无医院数据'))
                      : ListView(
                          children: viewModel.organTree.map((n) => _buildTreeTile(theme, viewModel, n, 0)).toList(),
                        ),
                ),
              ],
            ),
          ),
        ),

        // 右侧：医院信息表单
        Expanded(
          flex: 6,
          child: viewModel.selectedNode == null
              ? const Center(child: Text('请先在左侧选择医院'))
              : HospitalInfoForm(
                  key: ValueKey(viewModel.selectedNode!.id),
                  node: viewModel.selectedNode!,
                  info: viewModel.selectedOrganInfo!,
                  onSave: (info) async {
                    final ok = await viewModel.saveOrganInfo(info);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok ? '保存成功' : '保存失败：${viewModel.errorMsg ?? ''}'),
                        backgroundColor: ok ? Colors.green : Colors.red,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 递归构建树节点
  Widget _buildTreeTile(ThemeData theme, HospitalManagementViewModel viewModel, HospitalTreeNode node, int depth) {
    final selected = viewModel.selectedNode?.id == node.id;
    return Column(
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(left: 12.0 + depth * 20, right: 4),
          leading: const Icon(Icons.home_work_outlined, size: 18),
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
                          Icon(Icons.add_home_work_outlined, size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: 10),
                          const Text('添加下级医院'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: 10),
                          const Text('删除医院'),
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
                      _showAddChildDialog(theme, Icons.home_work_outlined, node);
                    } else if (action == 'delete') {
                      _confirmDelete(theme, node);
                    }
                  },
                ),
              ],
            ),
          ),
          selected: selected,
          onTap: () => viewModel.selectOrgan(node.id),
        ),
        if (node.expanded) ...node.children.map((c) => _buildTreeTile(theme, viewModel, c, depth + 1)),
      ],
    );
  }

  void _showAddRootDialog(ThemeData theme, IconData icon) {
    _showNameDialog(theme, icon, '添加顶级医院', (name) async {
      // 顶级医院：通过 addChildHospital 传入虚拟根节点逻辑，这里简化为接口后刷新
      // 实际项目应调用 context.read<OrganViewModel>().addRootHospital(name)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('TODO：调用添加顶级医院接口'),
        ),
      );
    });
  }

  void _showAddChildDialog(ThemeData theme, IconData icon, HospitalTreeNode parent) {
    _showNameDialog(theme, icon, '添加「${parent.name}」下级医院', (name) async {
      await context.read<HospitalManagementViewModel>().addChildOrgan(parent, name);
    });
  }

  void _showNameDialog(ThemeData theme, IconData icon, String title, Future<void> Function(String) onOk) {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        // 收窄对话框左右边距，让宽度由内容决定
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GlassPanel(
            blur: 24,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Row(
                      children: [
                        Icon(icon, color: theme.colorScheme.primary, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // 输入框
                    TextFormField(
                      controller: controller,
                      autofocus: true,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                      decoration: InputDecoration(
                        labelText: '医院名称',
                        labelStyle: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.6)),
                        // 毛玻璃底色：半透明 surface
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: theme.colorScheme.primary),
                        ),
                      ),
                      onFieldSubmitted: (_) => _confirmName(ctx, formKey, controller, onOk),
                      validator: (v) => (v == null || v.trim().isEmpty) ? '请输入医院名称' : null,
                    ),
                    const SizedBox(height: 20),

                    // 按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(
                            '取消',
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
                          ),
                        ),
                        const SizedBox(width: 12),

                        FilledButton(
                          onPressed: () async {
                            if (controller.text.trim().isEmpty) return;
                            Navigator.pop(ctx);
                            await onOk(controller.text);
                          },
                          child: Text(
                            '确定',
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmName(BuildContext ctx, GlobalKey<FormState> formKey, TextEditingController controller, Future<void> Function(String) onOk) async {
    if (!formKey.currentState!.validate()) return;
    final name = controller.text.trim();
    Navigator.pop(ctx);
    await onOk(name);
  }

  void _confirmDelete(ThemeData theme, HospitalTreeNode node) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        // 收窄对话框左右边距，让宽度由内容决定
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
                      Icon(Icons.delete_outline, color: theme.colorScheme.primary, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        '删除确认',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Text(
                    '确定删除医院「${node.name}」吗？',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          '取消',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
                        ),
                      ),
                      const SizedBox(width: 12),

                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await context.read<HospitalManagementViewModel>().removeOrgan(node);
                        },
                        child: Text(
                          '删除',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimary),
                        ),
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
}
