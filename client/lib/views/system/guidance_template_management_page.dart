import 'package:client/view_models/system/guidance_template_management_view_model.dart';
import 'package:client/views/base/base_page.dart';
import 'package:client/views/system/guidance_item_form_dialog.dart';
import 'package:client/views/system/guidance_template_form_dialog.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

// =====================================================================
// 指导建议模板管理页：左侧为模板列表（显示顺序非空在前按值升序，每
// 行展示「模板名称 + 显示顺序 + 创建人/时间」），右侧为选中模板的项
// 目列表（每行展示「类别 + 是否个人 + 指导建议内容 + 创建人/时间」）。
// 布局与法定节假日管理同构（左右双 Card，各带 60px primaryContainer
// 面板头）；模板增删改按操作权限 9912010001/9912010002/9912010003、
// 项目增删改按 9912020001/9912020002/9912020003 灰化控制（表单经毛
// 玻璃对话框录入；删除模板时服务端连带删除其全部项目）。
// =====================================================================
class GuidanceTemplateManagementPage extends BasePage {
  const GuidanceTemplateManagementPage({super.key, required super.loginUser, required super.child});

  @override
  State<GuidanceTemplateManagementPage> createState() => _GuidanceTemplateManagementPageState();
}

class _GuidanceTemplateManagementPageState extends State<GuidanceTemplateManagementPage> {
  /// dispose 中不能再用 context 取 Provider，保存实例引用供移除监听
  late final GuidanceTemplateManagementViewModel _viewModel;

  @override
  void initState() {
    super.initState();

    // 通过 Provider 获取全局注入的实例（不再自己 new）
    _viewModel = context.read<GuidanceTemplateManagementViewModel>();
    // 每次进入页面强制重拉（保证切回本页时数据一致）；延迟到首帧后发
    // 起，避免 build 期间同步 notifyListeners
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
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onError),
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
    final viewModel = context.watch<GuidanceTemplateManagementViewModel>();

    return viewModel.loading ? const Center(child: CircularProgressIndicator()) : _buildBody(context, viewModel);
  }

  Widget _buildBody(BuildContext context, GuidanceTemplateManagementViewModel viewModel) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左侧：指导建议模板列表
        Expanded(
          flex: 4,
          child: Card(
            color: theme.colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: theme,
                  title: '指导建议模板',
                  icon: Icons.assignment_outlined,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 新增按钮按「新增指导建议模板」操作权限灰化
                      IconButton(
                        tooltip: viewModel.canTemplateCreate ? '新增指导建议模板' : '无新增操作权限',
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        onPressed: viewModel.loading || viewModel.busy || !viewModel.canTemplateCreate ? null : () => _showTemplateForm(viewModel, null),
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
                      ? const Center(child: Text('暂无指导建议模板，请新增'))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: viewModel.templates.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            indent: 12,
                            endIndent: 12,
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                          ),
                          itemBuilder: (context, index) => _buildTemplateTile(context, viewModel, viewModel.templates[index]),
                        ),
                ),
              ],
            ),
          ),
        ),

        // 右侧：选中模板的指导建议项目列表
        Expanded(
          flex: 6,
          child: Card(
            color: theme.colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: theme,
                  title: '指导建议项目',
                  icon: Icons.format_list_bulleted_outlined,
                  // 中部摘要：当前选中模板名称（未选定时给指引）
                  subtitle: viewModel.selected == null ? '未选定模板——请先在左侧选择模板' : viewModel.selected!.templateName,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 新增按钮按「新增指导建议项目」操作权限灰化，
                      // 且须先选中模板
                      IconButton(
                        tooltip: !viewModel.canItemCreate
                            ? '无新增操作权限'
                            : viewModel.selected == null
                            ? '请先在左侧选择模板'
                            : '新增指导建议',
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        onPressed: viewModel.selected == null || viewModel.itemBusy || !viewModel.canItemCreate ? null : () => _showItemForm(viewModel, viewModel.selected!, null),
                      ),
                      IconButton(
                        tooltip: '刷新项目列表',
                        icon: const Icon(Icons.refresh_outlined, size: 20),
                        onPressed: viewModel.selected == null || viewModel.itemsLoading || viewModel.itemBusy ? null : viewModel.refreshItems,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: viewModel.selected == null
                      ? const Center(child: Text('请先在左侧选择模板'))
                      : viewModel.itemsLoading
                      ? const Center(child: CircularProgressIndicator())
                      : viewModel.items.isEmpty
                      ? const Center(child: Text('该模板暂无指导建议，请新增'))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: viewModel.items.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            indent: 12,
                            endIndent: 12,
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                          ),
                          itemBuilder: (context, index) => _buildItemTile(context, viewModel, viewModel.items[index]),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 面板抬头：primaryContainer 背景条（左右两栏同款，与法定节假日/
  /// 高危因素管理页一致）。
  Widget _buildPanelHeader({
    required ThemeData theme,
    required String title,
    required IconData icon,
    String? subtitle,
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
          Text(
            title,
            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              subtitle ?? '',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  // ---------------- 左侧：模板列表 ----------------

  /// 单条模板：名称 + 显示顺序 + 创建人/时间，行尾编辑/删除按钮
  ///（按操作权限灰化）。
  Widget _buildTemplateTile(
    BuildContext context,
    GuidanceTemplateManagementViewModel viewModel,
    BaseGuidanceTemplate template,
  ) {
    final theme = Theme.of(context);
    final selected = viewModel.selected?.id == template.id;
    return Material(
      color: selected ? theme.colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
      child: InkWell(
        onTap: () => viewModel.selectTemplate(template),
        child: Padding(
          padding: const EdgeInsets.only(left: 12, top: 10, bottom: 10, right: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.assignment_outlined,
                size: 16,
                color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            template.templateName,
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (template.displayOrder != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '顺序 ${template.displayOrder}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '创建人：${template.creatorName}${(template.createTime ?? '').isEmpty ? '' : ' · ${template.createTime}'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              _buildRowActions(
                theme: theme,
                editTooltip: viewModel.canTemplateUpdate ? '编辑模板' : '无修改操作权限',
                editOnPressed: viewModel.canTemplateUpdate && !viewModel.busy ? () => _showTemplateForm(viewModel, template) : null,
                deleteTooltip: viewModel.canTemplateDelete ? '删除模板' : '无删除操作权限',
                deleteOnPressed: viewModel.canTemplateDelete && !viewModel.busy ? () => _confirmDeleteTemplate(viewModel, template) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- 右侧：项目列表 ----------------

  /// 单条项目：类别 + 是否个人标签 + 内容预览 + 创建人/时间，行尾编辑/
  /// 删除按钮（按操作权限灰化）。
  Widget _buildItemTile(
    BuildContext context,
    GuidanceTemplateManagementViewModel viewModel,
    BaseGuidanceTemplateItem item,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 10, bottom: 10, right: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.chat_bubble_outline, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (item.guidanceType?.trim().isNotEmpty ?? false) ...[
                      Flexible(
                        child: Text(
                          item.guidanceType!,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                      decoration: BoxDecoration(
                        color: item.isPersonalTemplate ? theme.colorScheme.tertiaryContainer : theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        item.isPersonalTemplate ? '个人' : '公共',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: item.isPersonalTemplate ? theme.colorScheme.onTertiaryContainer : theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.guidance,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  '创建人：${item.creatorName}${(item.createTime ?? '').isEmpty ? '' : ' · ${item.createTime}'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          _buildRowActions(
            theme: theme,
            editTooltip: viewModel.canItemUpdate ? '编辑指导建议' : '无修改操作权限',
            editOnPressed: viewModel.canItemUpdate && !viewModel.itemBusy ? () => _showItemForm(viewModel, viewModel.selected!, item) : null,
            deleteTooltip: viewModel.canItemDelete ? '删除指导建议' : '无删除操作权限',
            deleteOnPressed: viewModel.canItemDelete && !viewModel.itemBusy ? () => _confirmDeleteItem(viewModel, item) : null,
          ),
        ],
      ),
    );
  }

  /// 行尾编辑/删除按钮组（删除图标与文字用 error 色）。
  Widget _buildRowActions({
    required ThemeData theme,
    required String editTooltip,
    required VoidCallback? editOnPressed,
    required String deleteTooltip,
    required VoidCallback? deleteOnPressed,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: editTooltip,
          child: IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: editOnPressed),
        ),
        Tooltip(
          message: deleteTooltip,
          child: IconButton(
            icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
            onPressed: deleteOnPressed,
          ),
        ),
      ],
    );
  }

  // ---------------- 表单与删除确认 ----------------

  /// 新增/编辑模板（毛玻璃对话框；编辑目标 null 为新增）。
  Future<void> _showTemplateForm(GuidanceTemplateManagementViewModel viewModel, BaseGuidanceTemplate? template) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => GuidanceTemplateFormDialog(viewModel: viewModel, template: template),
    );
  }

  /// 新增/编辑指导建议（毛玻璃对话框；编辑目标 null 为新增）。
  Future<void> _showItemForm(
    GuidanceTemplateManagementViewModel viewModel,
    BaseGuidanceTemplate template,
    BaseGuidanceTemplateItem? item,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => GuidanceItemFormDialog(viewModel: viewModel, template: template, item: item),
    );
  }

  /// 删除模板（毛玻璃确认；服务端连带删除其全部项目）。
  Future<void> _confirmDeleteTemplate(GuidanceTemplateManagementViewModel viewModel, BaseGuidanceTemplate template) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
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
                  Row(
                    children: [
                      Icon(Icons.delete_outline, color: theme.colorScheme.error, size: 22),
                      const SizedBox(width: 10),
                      Text('删除确认', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '确定删除指导建议模板「${template.templateName}」吗？\n其下全部指导建议项目将一并删除。',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                      const SizedBox(width: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.error,
                          foregroundColor: theme.colorScheme.onError,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
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
    if (confirmed != true || !mounted) return;
    final ok = await viewModel.deleteTemplate(template);
    if (!mounted) return;
    if (ok) _showResultSnackBar('删除成功');
  }

  /// 删除指导建议（毛玻璃确认）。
  Future<void> _confirmDeleteItem(GuidanceTemplateManagementViewModel viewModel, BaseGuidanceTemplateItem item) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
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
                  Row(
                    children: [
                      Icon(Icons.delete_outline, color: theme.colorScheme.error, size: 22),
                      const SizedBox(width: 10),
                      Text('删除确认', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    (item.guidanceType?.trim().isNotEmpty ?? false) ? '确定删除指导建议「${item.guidanceType}」吗？' : '确定删除该指导建议吗？',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                      const SizedBox(width: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.error,
                          foregroundColor: theme.colorScheme.onError,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
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
    if (confirmed != true || !mounted) return;
    final ok = await viewModel.deleteItem(item);
    if (!mounted) return;
    if (ok) _showResultSnackBar('删除成功');
  }

  void _showResultSnackBar(String message) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimary),
        ),
        backgroundColor: theme.colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
