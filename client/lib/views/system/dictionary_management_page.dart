import 'package:client/models/dict_tree_node.dart';
import 'package:client/view_models/system/dict_management_view_model.dart';
import 'package:client/views/base/base_page.dart';
import 'package:client/views/system/dict_form_dialog.dart';
import 'package:client/views/system/dict_item_form_dialog.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 数据字典管理页：左侧数据字典树（按 PARENT_ID 递归，可逐级新增下级
/// 字典，增删改走毛玻璃 Form 对话框）；右侧为选中字典的数据项列表，
/// 支持新增、修改、删除数据项与设置默认项（同字典内至多一项默认）。
class DictionaryManagementPage extends BasePage {
  const DictionaryManagementPage({
    super.key,
    required super.loginUser,
    required super.child,
  });

  @override
  State<DictionaryManagementPage> createState() => _DictionaryManagementPageState();
}

class _DictionaryManagementPageState extends State<DictionaryManagementPage> {
  /// dispose 中不能再用 context 取 Provider，保存实例引用供移除监听
  late final DictManagementViewModel _viewModel;

  @override
  void initState() {
    super.initState();

    // 通过 Provider 获取全局注入的实例（不再自己 new）
    _viewModel = context.read<DictManagementViewModel>();
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
    final viewModel = context.watch<DictManagementViewModel>();

    return viewModel.loading ? const Center(child: CircularProgressIndicator()) : _buildBody(context, viewModel);
  }

  Widget _buildBody(BuildContext context, DictManagementViewModel viewModel) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左侧：数据字典树
        Expanded(
          flex: 4,
          child: Card(
            color: Theme.of(context).colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: Theme.of(context),
                  title: '数据字典',
                  icon: Icons.account_tree_outlined,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 新增顶级字典按钮按「新增数据字典」操作权限显隐
                      if (viewModel.canCreateDict)
                        IconButton(
                          tooltip: '新增顶级字典',
                          icon: Icon(
                            Icons.library_add_outlined,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          // 顶级新增（挂载目标为空）；树为空时也可用
                          onPressed: viewModel.loading || viewModel.busy ? null : () => _showDictForm(viewModel),
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
                      ? const Center(child: Text('暂无数据字典，请新增顶级字典'))
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

        // 右侧：选中字典的数据项列表
        Expanded(
          flex: 6,
          child: Card(
            color: Theme.of(context).colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: Theme.of(context),
                  title: viewModel.selectedDict == null ? '数据项' : '数据项 · ${viewModel.selectedDict!.dictName}',
                  icon: Icons.list_alt_outlined,
                  // 新增数据项按钮按「新增数据项」操作权限显隐
                  trailing: viewModel.selectedDict == null || !viewModel.canCreateItem
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '新增数据项',
                              icon: Icon(
                                Icons.playlist_add_outlined,
                                size: 20,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              onPressed: viewModel.busy ? null : () => _showItemForm(viewModel),
                            ),
                          ],
                        ),
                ),
                Expanded(
                  child: viewModel.selectedDict == null
                      ? const Center(child: Text('请先在左侧选择数据字典'))
                      : viewModel.itemsLoading
                      ? const Center(child: CircularProgressIndicator())
                      : viewModel.items.isEmpty
                      ? const Center(child: Text('该字典暂无数据项，请新增数据项'))
                      : ListView(
                          children: [
                            for (final item in viewModel.items) _buildItemTile(context, viewModel, item),
                          ],
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

  /// 递归构建字典树节点：字典（可新增下级字典/修改/删除，点击选中右侧
  /// 查看数据项）。
  Widget _buildTreeTile(
    BuildContext context,
    DictManagementViewModel viewModel,
    DictTreeNode node,
    int depth,
  ) {
    final theme = Theme.of(context);
    final selected = viewModel.selectedNode?.key == node.key;
    return Column(
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(left: 12.0 + depth * 20, right: 4),
          selected: selected,
          leading: Icon(
            node.isLeaf ? Icons.label_outline : Icons.folder_outlined,
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
            '${node.dict.dictCode}${node.dict.displayOrder == null ? '' : ' · 顺序 ${node.dict.displayOrder}'}',
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

  /// 节点行尾：展开/折叠箭头 + 操作菜单（新增下级字典/修改/删除，
  /// 各项按对应操作权限显隐；全部未授权时整个操作菜单不显示）。
  Widget _buildNodeTrailing(
    BuildContext context,
    DictManagementViewModel viewModel,
    DictTreeNode node,
  ) {
    final theme = Theme.of(context);
    final hasDictActions = viewModel.canCreateDict || viewModel.canUpdateDict || viewModel.canDeleteDict;
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
          if (hasDictActions)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              itemBuilder: (_) => [
                if (viewModel.canCreateDict)
                  PopupMenuItem(
                    value: 'add',
                    child: Row(
                      children: [
                        Icon(
                          Icons.library_add_outlined,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        const Text('新增下级字典'),
                      ],
                    ),
                  ),
                if (viewModel.canUpdateDict)
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        const Text('修改'),
                      ],
                    ),
                  ),
                if (viewModel.canDeleteDict)
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
                  _showDictForm(viewModel, parent: node);
                } else if (action == 'edit') {
                  _showDictForm(viewModel, dict: node.dict);
                } else if (action == 'delete') {
                  _confirmDeleteDict(context, viewModel, node);
                }
              },
            ),
        ],
      ),
    );
  }

  /// 数据项行：项目值 + 编码/顺序说明 + 默认徽章 + 行操作
  /// （设为默认/修改/删除）。
  Widget _buildItemTile(
    BuildContext context,
    DictManagementViewModel viewModel,
    DictItem item,
  ) {
    final theme = Theme.of(context);
    final isDefault = item.isDefault == '1';
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 12, right: 4),
      leading: Icon(
        isDefault ? Icons.star : Icons.label_outline,
        size: 18,
        color: isDefault ? theme.colorScheme.primary : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              item.itemValue,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isDefault ? FontWeight.bold : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isDefault) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '默认',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${item.itemCode}${item.displayOrder == null ? '' : ' · 顺序 ${item.displayOrder}'}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      // 行尾操作：修改（含设为默认项）/删除分别按「修改数据项」
      // 「删除数据项」权限显隐
      trailing: SizedBox(
        width: 120,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (!isDefault && viewModel.canUpdateItem)
              IconButton(
                tooltip: '设为默认项',
                icon: Icon(
                  Icons.star_outline,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: viewModel.busy
                    ? null
                    : () async {
                        final ok = await viewModel.setItemDefault(item);
                        if (!mounted) return;
                        if (ok) _showResultSnackBar('已设为默认项');
                        // 失败提示由 errorMsg 监听统一弹出
                      },
              ),
            if (viewModel.canUpdateItem)
              IconButton(
                tooltip: '修改',
                icon: Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: viewModel.busy ? null : () => _showItemForm(viewModel, item: item),
              ),
            if (viewModel.canDeleteItem)
              IconButton(
                tooltip: '删除',
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: viewModel.busy ? null : () => _confirmDeleteItem(context, viewModel, item),
              ),
          ],
        ),
      ),
      // 点击行打开编辑弹窗等同「修改数据项」，同权限控制
      onTap: viewModel.canUpdateItem ? () => _showItemForm(viewModel, item: item) : null,
    );
  }

  /// 打开字典表单对话框（新增顶级/新增下级/编辑共用；parent 与 dict
  /// 均为 null 时为顶级新增）。
  Future<void> _showDictForm(
    DictManagementViewModel viewModel, {
    DictTreeNode? parent,
    Dict? dict,
  }) async {
    if (parent != null) {
      // 新增下级：挂载目标为发起节点（对话框标题下方展示挂载位置）
      viewModel.startCreate(parent);
    } else if (dict == null) {
      viewModel.startCreate(null);
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => DictFormDialog(viewModel: viewModel, dict: dict),
    );
    if (!mounted || ok != true) return;
    _showResultSnackBar(dict == null ? '新增成功' : '保存成功');
  }

  /// 打开数据项表单对话框（item 为 null 时为新增）。
  Future<void> _showItemForm(
    DictManagementViewModel viewModel, {
    DictItem? item,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => DictItemFormDialog(viewModel: viewModel, item: item),
    );
    if (!mounted || ok != true) return;
    _showResultSnackBar(item == null ? '新增成功' : '保存成功');
  }

  /// 删除字典确认对话框（毛玻璃）；存在下级字典或数据项时后端阻止，
  /// 提示由 errorMsg 监听统一弹出。
  void _confirmDeleteDict(
    BuildContext context,
    DictManagementViewModel viewModel,
    DictTreeNode node,
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
                    '确定删除数据字典「${node.name}」吗？存在下级字典或数据项时需先删除。',
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
                          final ok = await viewModel.deleteDict(node);
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

  /// 删除数据项确认对话框（毛玻璃）。
  void _confirmDeleteItem(
    BuildContext context,
    DictManagementViewModel viewModel,
    DictItem item,
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
                    '确定删除数据项「${item.itemValue}」吗？',
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
                          final ok = await viewModel.deleteItem(item);
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
