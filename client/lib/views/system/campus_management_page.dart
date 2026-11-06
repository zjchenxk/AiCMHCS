import 'package:client/models/hospital_tree_node.dart';
import 'package:client/view_models/system/campus_management_view_model.dart';
import 'package:client/views/base/base_page.dart';
import 'package:client/views/system/campus_edit_dialog.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 院区管理页：左侧医院树（仅选择，医院增删走医院设置页）；右侧为选中
/// 医院的院区列表，支持新增/编辑（毛玻璃对话框）与删除（确认对话框）。
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
    // 仅首次进入加载：切页回来保留已加载的树与选中状态
    // （VM 为全局单例，重复 loadData 会重建整棵树、丢失展开状态）；
    // 延迟到首帧后发起，避免 build 期间同步 notifyListeners
    if (_viewModel.hospitalTree.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _viewModel.loadData();
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
    final viewModel = context.watch<CampusManagementViewModel>();

    return viewModel.loading ? const Center(child: CircularProgressIndicator()) : _buildBody(context, viewModel);
  }

  Widget _buildBody(BuildContext context, CampusManagementViewModel viewModel) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左侧：医院树形列表（选择载体）
        Expanded(
          flex: 4,
          child: Card(
            color: Theme.of(context).colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: Theme.of(context),
                  title: '医院列表',
                  icon: Icons.account_tree_outlined,
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

        // 右侧：选中医院的院区列表
        Expanded(
          flex: 6,
          child: Card(
            color: Theme.of(context).colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: Theme.of(context),
                  title: viewModel.selectedNode == null ? '院区列表' : '${viewModel.selectedNode!.name} · 院区',
                  icon: Icons.domain_outlined,
                  trailing: IconButton(
                    tooltip: '新增院区',
                    icon: Icon(
                      Icons.add_business_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: viewModel.busy || viewModel.selectedNode == null ? null : () => _showEditDialog(viewModel),
                  ),
                ),
                Expanded(
                  child: viewModel.selectedNode == null
                      ? const Center(child: Text('请先在左侧选择医院'))
                      : viewModel.campuses.isEmpty
                      ? const Center(child: Text('该医院暂无院区，点击右上角新增'))
                      : ListView(
                          children: viewModel.campuses.map((c) => _buildCampusTile(context, viewModel, c)).toList(),
                        ),
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

  /// 递归构建医院树节点（仅选择，无操作菜单）
  Widget _buildTreeTile(BuildContext context, CampusManagementViewModel viewModel, HospitalTreeNode node, int depth) {
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
          trailing: !node.isLeaf
              ? InkWell(
                  onTap: () => viewModel.toggleExpand(node),
                  child: Icon(
                    node.expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                    size: 20,
                  ),
                )
              : null,
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

  /// 院区列表行：主显名称，副显代码/地址/电话，行尾编辑与删除
  Widget _buildCampusTile(BuildContext context, CampusManagementViewModel viewModel, Campus campus) {
    final theme = Theme.of(context);
    final subtitleParts = [
      if (campus.code.isNotEmpty) '代码：${campus.code}',
      if (campus.address != null && campus.address!.isNotEmpty) '地址：${campus.address}',
      if (campus.tel != null && campus.tel!.isNotEmpty) '电话：${campus.tel}',
    ];
    return ListTile(
      dense: true,
      leading: Icon(Icons.domain_outlined, size: 20, color: theme.colorScheme.primary),
      title: Text(
        campus.name,
        style: theme.textTheme.bodyMedium,
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '编辑',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.edit_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            onPressed: viewModel.busy ? null : () => _showEditDialog(viewModel, campus: campus),
          ),
          IconButton(
            tooltip: '删除',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: theme.colorScheme.error,
            ),
            onPressed: viewModel.busy ? null : () => _confirmDelete(context, viewModel, campus),
          ),
        ],
      ),
    );
  }

  /// 打开新增/编辑院区对话框（新增目标为当前选中医院）
  Future<void> _showEditDialog(CampusManagementViewModel viewModel, {Campus? campus}) async {
    final hospitalName = viewModel.selectedNode?.name ?? '';
    final editing = campus != null;
    final ok = await CampusEditDialog.show(
      context,
      hospitalName: hospitalName,
      initial: campus,
      onSubmit: (code, name, address, tel) => editing
          ? viewModel.updateCampus(campus.id, {
              'code': code,
              'name': name,
              'address': address,
              'tel': tel,
            })
          : viewModel.createCampus(code: code, name: name, address: address, tel: tel),
    );
    if (!mounted || ok != true) return;
    _showResultSnackBar(editing ? '修改成功' : '新增成功');
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
