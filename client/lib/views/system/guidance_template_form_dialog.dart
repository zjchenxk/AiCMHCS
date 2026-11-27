import 'dart:convert';

import 'package:client/view_models/system/guidance_template_management_view_model.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:material_ui/material_ui.dart';

// =====================================================================
// 指导建议模板表单对话框（模板管理页左侧新增/编辑共用）
//
// 毛玻璃对话框：新增模式全空待录、编辑模式回填选中模板；提交期间
// 保持打开（按钮转进度），失败保留输入并内联显示错误信息，成功后
// 关闭并由调用方刷新列表。模板名称同医院内唯一、50 字节限长由服务
// 端兜底校验（此处按字节即时校验给出前置提示）。
// =====================================================================
class GuidanceTemplateFormDialog extends StatefulWidget {
  /// 构造函数：注入 ViewModel 与编辑目标（null 为新增）。
  const GuidanceTemplateFormDialog({super.key, required this.viewModel, this.template});

  final GuidanceTemplateManagementViewModel viewModel;

  /// 编辑的目标模板（null 表示新增）。
  final BaseGuidanceTemplate? template;

  @override
  State<GuidanceTemplateFormDialog> createState() => _GuidanceTemplateFormDialogState();
}

class _GuidanceTemplateFormDialogState extends State<GuidanceTemplateFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _orderCtrl;

  // 显式焦点链：回车定向跳到下一输入框（禁止 FocusScope.nextFocus，
  // 会把焦点漏到页面其他可聚焦控件）
  final _nameFocus = FocusNode();
  final _orderFocus = FocusNode();

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 编辑模式回填目标模板；新增模式全空
    final template = widget.template;
    _nameCtrl = TextEditingController(text: template?.templateName);
    _orderCtrl = TextEditingController(text: template?.displayOrder?.toString());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _orderCtrl.dispose();
    _nameFocus.dispose();
    _orderFocus.dispose();
    super.dispose();
  }

  /// 显示顺序校验：可空；填了必须是整数且在 SMALLINT 范围内。
  String? _validateOrder(String? v) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return null;
    final value = int.tryParse(text);
    if (value == null) return '显示顺序须为整数';
    if (value < -32768 || value > 32767) return '显示顺序超出范围（-32768 ~ 32767）';
    return null;
  }

  Future<void> _submit() async {
    if (_saving) return; // 防回车重复提交
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    final viewModel = widget.viewModel;
    final template = widget.template;
    final name = _nameCtrl.text.trim();
    final orderText = _orderCtrl.text.trim();
    final order = orderText.isEmpty ? null : int.tryParse(orderText);
    final ok = template == null
        ? await viewModel.createTemplate(templateName: name, displayOrder: order)
        : await viewModel.updateTemplate(template.id, {
            'templateName': name,
            'displayOrder': order,
          });

    if (!mounted) return;
    if (!ok) {
      // 保留输入与对话框，内联展示错误（对话框遮罩会挡住页面 SnackBar）
      setState(() {
        _saving = false;
        _error = viewModel.errorMsg ?? '保存失败，请重试';
      });
      viewModel.clearError();
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final creating = widget.template == null;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassPanel(
          blur: 24,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  Row(
                    children: [
                      Icon(
                        creating ? Icons.playlist_add_outlined : Icons.edit_outlined,
                        color: theme.colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        creating ? '新增指导建议模板' : '编辑指导建议模板',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _nameCtrl,
                    focusNode: _nameFocus,
                    autofocus: true,
                    style: theme.textTheme.bodyMedium,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _orderFocus.requestFocus(),
                    decoration: _decoration(theme, '模板名称', required: true),
                    validator: (v) {
                      final text = v?.trim() ?? '';
                      if (text.isEmpty) return '请输入模板名称';
                      if (utf8.encode(text).length > 50) return '模板名称超出长度限制（50 字节）';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _orderCtrl,
                    focusNode: _orderFocus,
                    style: theme.textTheme.bodyMedium,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: _decoration(theme, '显示顺序'),
                    validator: _validateOrder,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving ? null : () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _saving ? null : _submit,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(creating ? Icons.playlist_add_outlined : Icons.save_outlined, size: 18),
                        label: Text(creating ? '添加' : '保 存'),
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

  /// 统一的毛玻璃输入框装饰（同角色表单对话框）。
  InputDecoration _decoration(ThemeData theme, String label, {bool required = false}) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color),
    );
    return InputDecoration(
      label: required
          ? Text.rich(
              TextSpan(
                text: label,
                style: theme.textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: ' *',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ),
            )
          : Text(label, style: theme.textTheme.bodyMedium),
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      enabledBorder: border(theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      focusedBorder: border(theme.colorScheme.primary),
    );
  }
}
