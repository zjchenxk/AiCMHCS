import 'package:client/utils/menu_icons.dart';
import 'package:client/view_models/system/menu_management_view_model.dart';
import 'package:client/views/system/menu_icon_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

// =====================================================================
// 菜单项目信息表单（菜单管理页右侧面板）
//
// 编辑模式（回填选中项目，顶部显示归属位置）与新增模式（表单清空待录，
// 顶部显示挂载位置——上级项目 / 顶级）。以模式+目标为 ValueKey 由页面
// 在切换时重建，实现清空/回填。
//
// 字段联动：项目类型为菜单（'2'）时显示菜单路由（可选，占位菜单可
// 暂不配置）；项目类型为操作（'3'）时隐藏菜单图标；类型切换后提交按
// 目标类型归一（非菜单类型清空路由、操作类型清空图标）。
// =====================================================================
class MenuInfoForm extends StatefulWidget {
  final MenuManagementViewModel viewModel;

  const MenuInfoForm({
    super.key,
    required this.viewModel,
  });

  @override
  State<MenuInfoForm> createState() => _MenuInfoFormState();
}

class _MenuInfoFormState extends State<MenuInfoForm> {
  /// 各字段长度上限（与表列宽对齐，超长前后端一致拦截）。
  static const int _codeMaxLength = 10;
  static const int _nameMaxLength = 50;
  static const int _routeMaxLength = 100;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _routeCtrl;

  /// 项目类型（'1'-模块、'2'-菜单、'3'-操作）。
  late String _itemType;

  /// 选中的图标名（null 为不设置）。
  String? _iconName;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 编辑模式回填选中项目；新增模式默认模块类型、全空
    final menu = widget.viewModel.formMode == MenuFormMode.edit ? widget.viewModel.selectedMenu : null;
    _codeCtrl = TextEditingController(text: menu?.itemCode);
    _nameCtrl = TextEditingController(text: menu?.itemName);
    _routeCtrl = TextEditingController(text: menu?.menuRoute);
    _itemType = menu?.itemType ?? '1';
    _iconName = menu?.menuIcon;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _routeCtrl.dispose();
    super.dispose();
  }

  /// 打开图标选择器（iconMap 全量可搜索）：选中回填、不设置清除、
  /// 取消保持不变。
  Future<void> _pickIcon() async {
    final picked = await showMenuIconPicker(context, current: _iconName);
    if (!mounted || picked == null) return;
    setState(() => _iconName = picked.isEmpty ? null : picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final viewModel = context.read<MenuManagementViewModel>();
    final creating = viewModel.formMode == MenuFormMode.create;
    final itemCode = _codeCtrl.text.trim();
    final itemName = _nameCtrl.text.trim();
    // 按目标类型归一：非菜单类型清空路由、操作类型清空图标；
    // 路由留空归一为 null（空串不落库）
    final routeText = _routeCtrl.text.trim();
    final menuRoute = _itemType == '2' && routeText.isNotEmpty ? routeText : null;
    final menuIcon = _itemType == '3' ? null : _iconName;

    final ok = creating
        ? await viewModel.createMenu(
            itemCode: itemCode,
            itemName: itemName,
            itemType: _itemType,
            menuRoute: menuRoute,
            menuIcon: menuIcon,
            visible: '1',
          )
        : await viewModel.updateMenu(viewModel.selectedMenu!.id, {
            'itemCode': itemCode,
            'itemName': itemName,
            'itemType': _itemType,
            'menuRoute': menuRoute,
            'menuIcon': menuIcon,
            'visible': '1',
          });

    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    // 失败提示由页面 errorMsg 监听统一弹出
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          creating ? '新增成功' : '保存成功',
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

  @override
  Widget build(BuildContext context) {
    //获取当前主题
    final ThemeData theme = Theme.of(context);
    final viewModel = context.watch<MenuManagementViewModel>();
    final creating = viewModel.formMode == MenuFormMode.create;
    // 顶部位置说明：新增显示挂载目标，编辑显示归属位置
    final locationLabel = creating ? viewModel.createTargetLabel : viewModel.selectedLocationLabel;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 归属位置（只读展示）
          _sectionTitle(theme, '归属位置'),
          Text(
            locationLabel.isEmpty ? '—' : locationLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),

          // 基本信息
          _sectionTitle(theme, '基本信息'),
          TextFormField(
            controller: _codeCtrl,
            autofocus: creating,
            maxLength: _codeMaxLength,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next, // 回车键显示"下一项"
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(), // 回车跳下一个
            decoration: glassDecoration(theme, '项目编码', required: true),
            validator: (v) => (v == null || v.trim().isEmpty) ? '请输入项目编码' : null,
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _nameCtrl,
            maxLength: _nameMaxLength,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: glassDecoration(theme, '项目名称', required: true),
            validator: (v) => (v == null || v.trim().isEmpty) ? '请输入项目名称' : null,
          ),
          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            initialValue: menuItemTypeLabels.containsKey(_itemType) ? _itemType : null,
            isExpanded: true,
            style: theme.textTheme.bodyMedium,
            items: [
              for (final entry in menuItemTypeLabels.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: viewModel.busy || _saving
                ? null
                : (v) {
                    if (v == null) return;
                    setState(() => _itemType = v);
                  },
            decoration: glassDecoration(theme, '项目类型', required: true),
            validator: (v) => (v == null || v.isEmpty) ? '请选择项目类型' : null,
          ),
          const SizedBox(height: 24),

          // 菜单配置（类型为操作时隐藏路由；图标仅模块/菜单类型可选）
          _sectionTitle(theme, '菜单配置'),
          if (_itemType == '2') ...[
            TextFormField(
              controller: _routeCtrl,
              maxLength: _routeMaxLength,
              style: theme.textTheme.bodyMedium,
              textInputAction: TextInputAction.done, // 最后一个显示"完成"
              onFieldSubmitted: (_) => _submit(), // 回车直接保存
              decoration: glassDecoration(theme, '菜单路由'),
            ),
            const SizedBox(height: 12),
          ],

          // 图标选择（点击弹出可搜索选择面板，数据源 iconMap 全量）
          if (_itemType != '3')
            InkWell(
              onTap: viewModel.busy || _saving ? null : _pickIcon,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: glassDecoration(
                  theme,
                  '菜单图标',
                ).copyWith(suffixIcon: const Icon(Icons.expand_more, size: 20)),
                child: Row(
                  children: [
                    Icon(
                      menuIconOrFallback(_iconName, fallback: menuItemTypeIcon(_itemType)),
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _iconName ?? '不设置（点击选择）',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _iconName == null ? theme.colorScheme.onSurface.withValues(alpha: 0.6) : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 32),

          // 操作按钮：新增模式可取消，编辑模式仅保存
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (creating) ...[
                TextButton(
                  onPressed: viewModel.busy || _saving ? null : viewModel.cancelCreate,
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: viewModel.busy || _saving ? null : _submit,
                  icon: const Icon(Icons.add_business_outlined, size: 18),
                  label: const Text('添加'),
                ),
              ] else
                FilledButton.icon(
                  onPressed: viewModel.busy || _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: const Text('保 存'),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  OutlineInputBorder glassBorder(ThemeData theme, Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color),
  );

  // 统一的毛玻璃输入框装饰
  InputDecoration glassDecoration(
    ThemeData theme,
    String label, {
    bool required = false,
  }) {
    return InputDecoration(
      label: required
          ? Text.rich(
              TextSpan(
                text: label,
                style: theme.textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: ' *',
                    style: TextStyle(color: theme.colorScheme.error), // 红色星号
                  ),
                ],
              ),
            )
          : Text(label, style: theme.textTheme.bodyMedium),
      counterText: '', // 隐藏 maxLength 计数器（保留输入截断）
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.6,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: glassBorder(
        theme,
        theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
      ),
      enabledBorder: glassBorder(
        theme,
        theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
      ),
      focusedBorder: glassBorder(theme, theme.colorScheme.primary),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(width: 4, height: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
