import 'package:client/utils/risk_color.dart';
import 'package:client/view_models/system/high_risk_factor_management_view_model.dart';
import 'package:client/widgets/dict_dropdown_form_field.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

// =====================================================================
// 高危因素信息表单（高危因素管理页右侧面板）
//
// 编辑模式（回填选中高危因素）与新增模式（表单清空待录）共用；以
// 模式+因素 ID 为 ValueKey 由页面在切换时重建，实现清空/回填。
// 高危颜色为中文五色下拉，高危等级绑定数据字典 DICT_CODE=99010001
// （存 BASE_DICT_ITEM.ITEM_VALUE）。无修改权限时表单整体只读。
// =====================================================================
class HighRiskFactorInfoForm extends StatefulWidget {
  /// 构造函数：注入 ViewModel（表单模式与选中项均由 ViewModel 提供）。
  const HighRiskFactorInfoForm({super.key, required this.viewModel});

  final HighRiskFactorManagementViewModel viewModel;

  @override
  State<HighRiskFactorInfoForm> createState() => _HighRiskFactorInfoFormState();
}

class _HighRiskFactorInfoFormState extends State<HighRiskFactorInfoForm> {
  /// 高危等级数据字典编码（BASE_DICT.DICT_CODE，存数据项 ITEM_VALUE）。
  static const String _riskLevelDictCode = '99010001';

  /// 各字段长度上限（与表列宽对齐，超长前后端一致拦截）。
  static const int _codeMaxLength = 20;
  static const int _nameMaxLength = 200;
  static const int _categoryMaxLength = 50;
  static const int _subcategoryMaxLength = 50;

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _subcategoryCtrl;
  late final TextEditingController _scoreCtrl;

  // 显式焦点链（回车定向跳格，模式同科室/字典表单）：下拉选择框不
  // 参与回车链（从小类直接跳到高危分值）。
  late final FocusNode _codeFocus;
  late final FocusNode _nameFocus;
  late final FocusNode _categoryFocus;
  late final FocusNode _subcategoryFocus;
  late final FocusNode _scoreFocus;

  /// 高危等级下拉字段键（提交时统一取值，避免额外维护 onChanged 状态）。
  final _levelFieldKey = GlobalKey<FormFieldState<String>>();

  /// 当前选中的高危颜色（中文五色；null 为未设置）。
  String? _color;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final viewModel = widget.viewModel;
    // 编辑模式回填选中高危因素；新增模式全空
    final factor = viewModel.formMode == HighRiskFactorFormMode.edit ? viewModel.selected : null;
    _codeCtrl = TextEditingController(text: factor?.riskFactorCode);
    _nameCtrl = TextEditingController(text: factor?.riskFactorName);
    _categoryCtrl = TextEditingController(text: factor?.riskFactorCategory);
    _subcategoryCtrl = TextEditingController(text: factor?.riskFactorSubcategory);
    _scoreCtrl = TextEditingController(text: factor?.riskScore);
    final color = factor?.riskColor?.trim();
    _color = RiskColorPalette.names.contains(color) ? color : null;
    _codeFocus = FocusNode();
    _nameFocus = FocusNode();
    _categoryFocus = FocusNode();
    _subcategoryFocus = FocusNode();
    _scoreFocus = FocusNode();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _subcategoryCtrl.dispose();
    _scoreCtrl.dispose();
    _codeFocus.dispose();
    _nameFocus.dispose();
    _categoryFocus.dispose();
    _subcategoryFocus.dispose();
    _scoreFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final viewModel = widget.viewModel;
    if (_saving || viewModel.busy) return;
    if (!_formKey.currentState!.validate()) return;

    final creating = viewModel.formMode == HighRiskFactorFormMode.create;
    if (creating ? !viewModel.canCreate : !viewModel.canUpdate) return;

    setState(() => _saving = true);
    final category = _emptyToNull(_categoryCtrl.text);
    final subcategory = _emptyToNull(_subcategoryCtrl.text);
    final score = _emptyToNull(_scoreCtrl.text);
    // 高危等级值经表单字段读取（下拉不额外维护 onChanged 状态）
    final level = _levelFieldKey.currentState?.value;

    final ok = creating
        ? await viewModel.createFactor(
            riskFactorCode: _codeCtrl.text.trim(),
            riskFactorName: _nameCtrl.text.trim(),
            riskFactorCategory: category,
            riskFactorSubcategory: subcategory,
            riskColor: _color,
            riskLevel: level,
            riskScore: score,
          )
        : await viewModel.updateFactor(viewModel.selected!.id, {
            'riskFactorCategory': category,
            'riskFactorSubcategory': subcategory,
            'riskFactorCode': _codeCtrl.text.trim(),
            'riskFactorName': _nameCtrl.text.trim(),
            'riskColor': _color,
            'riskLevel': level,
            'riskScore': score,
          });

    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    // 失败提示由页面 errorMsg 监听统一弹出
    _showResultSnackBar(creating ? '新增成功' : '保存成功');
  }

  /// 删除选中高危因素（毛玻璃确认）；成功后页面回退空态。
  Future<void> _confirmDelete() async {
    final viewModel = widget.viewModel;
    final factor = viewModel.selected;
    if (factor == null || viewModel.busy || _saving) return;
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
                      Text(
                        '删除确认',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('确定删除高危因素「${factor.riskFactorName}」吗？', style: theme.textTheme.bodyMedium),
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
    final ok = await viewModel.deleteFactor(factor);
    if (!mounted) return;
    if (ok) _showResultSnackBar('删除成功');
  }

  /// 空串归一为 null（可空列清空语义）。
  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewModel = context.watch<HighRiskFactorManagementViewModel>();
    final creating = viewModel.formMode == HighRiskFactorFormMode.create;
    final selected = viewModel.selected;
    // 可编辑性：新增看新增权限，编辑看修改权限
    final editable = creating ? viewModel.canCreate : viewModel.canUpdate;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!editable) ...[
            Row(
              children: [
                Icon(Icons.lock_outline, size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 6),
                Text(
                  creating ? '无新增操作权限' : '无修改操作权限，当前为只读',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // 基本信息
          _sectionTitle(theme, '基本信息'),
          TextFormField(
            controller: _codeCtrl,
            focusNode: _codeFocus,
            enabled: editable,
            autofocus: creating,
            maxLength: _codeMaxLength,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _nameFocus.requestFocus(),
            decoration: glassDecoration(theme, '高危因素编码', required: true),
            validator: (v) => (v == null || v.trim().isEmpty) ? '请输入高危因素编码' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nameCtrl,
            focusNode: _nameFocus,
            enabled: editable,
            maxLength: _nameMaxLength,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _categoryFocus.requestFocus(),
            decoration: glassDecoration(theme, '高危因素名称', required: true),
            validator: (v) => (v == null || v.trim().isEmpty) ? '请输入高危因素名称' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _categoryCtrl,
            focusNode: _categoryFocus,
            enabled: editable,
            maxLength: _categoryMaxLength,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _subcategoryFocus.requestFocus(),
            decoration: glassDecoration(theme, '大类'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _subcategoryCtrl,
            focusNode: _subcategoryFocus,
            enabled: editable,
            maxLength: _subcategoryMaxLength,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next,
            // 回车跳过颜色/等级下拉，直接到高危分值
            onFieldSubmitted: (_) => _scoreFocus.requestFocus(),
            decoration: glassDecoration(theme, '小类'),
          ),
          const SizedBox(height: 24),

          // 分级与评分
          _sectionTitle(theme, '分级与评分'),
          DropdownButtonFormField<String>(
            initialValue: _color,
            isExpanded: true,
            items: RiskColorPalette.names
                .map(
                  (name) => DropdownMenuItem(
                    value: name,
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: RiskColorPalette.colorOf(name, theme),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(name, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                )
                .toList(),
            hint: Text('请选择高危颜色', style: theme.textTheme.bodyMedium),
            decoration: glassDecoration(theme, '高危颜色'),
            style: theme.textTheme.bodyMedium,
            onChanged: editable ? (v) => setState(() => _color = v) : null,
          ),
          const SizedBox(height: 12),
          DictDropdownFormField(
            dictCode: _riskLevelDictCode,
            label: '高危等级',
            // 新增模式不继承上一选中项（表单以 ValueKey 重建，此处再兜底）
            initialValue: creating ? null : selected?.riskLevel,
            enabled: editable,
            formFieldKey: _levelFieldKey,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _scoreCtrl,
            focusNode: _scoreFocus,
            enabled: editable,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 3,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            decoration: glassDecoration(theme, '高危分值'),
            validator: (v) {
              final text = v?.trim() ?? '';
              if (text.isEmpty) return null; // 可选字段
              final score = int.tryParse(text);
              if (score == null || score < BaseHighRiskFactor.riskScoreMin || score > BaseHighRiskFactor.riskScoreMax) {
                return '高危分值应为 ${BaseHighRiskFactor.riskScoreMin}-${BaseHighRiskFactor.riskScoreMax} 的整数';
              }
              return null;
            },
          ),
          const SizedBox(height: 32),

          // 操作按钮：删除（编辑态、独立删除权限）+ 取消（新增）+ 保存
          Row(
            children: [
              if (!creating && viewModel.canDelete)
                TextButton.icon(
                  onPressed: viewModel.busy || _saving ? null : _confirmDelete,
                  icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
                  label: Text(
                    '删除',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const Spacer(),
              if (creating) ...[
                TextButton(
                  onPressed: viewModel.busy || _saving ? null : viewModel.cancelCreate,
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
              ],
              FilledButton.icon(
                onPressed: editable && !viewModel.busy && !_saving ? _submit : null,
                icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined, size: 18),
                label: const Text('保 存'),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  OutlineInputBorder _glassBorder(ThemeData theme, Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color),
  );

  /// 统一的毛玻璃输入框装饰（与科室/字典表单同款）。
  InputDecoration glassDecoration(ThemeData theme, String label, {bool required = false}) {
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
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: _glassBorder(theme, theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      enabledBorder: _glassBorder(theme, theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      focusedBorder: _glassBorder(theme, theme.colorScheme.primary),
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
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
