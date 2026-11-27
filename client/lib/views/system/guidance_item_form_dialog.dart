import 'dart:convert';

import 'package:client/view_models/system/guidance_template_management_view_model.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

// =====================================================================
// 指导建议项目表单对话框（模板管理页右侧新增/编辑共用）
//
// 毛玻璃对话框：新增模式全空待录（公共模板默认）、编辑模式回填选中
// 项目；提交期间保持打开（按钮转进度），失败保留输入并内联显示错误
// 信息，成功后关闭并由调用方刷新列表。类别可空（填则 50 字节）、内
// 容 1000 字节限长由服务端兜底校验（此处按字节即时校验给出前置提示）。
// 是否个人模板开关与【取消】/【添加】按钮同行（开关靠左、按钮靠右）。
// =====================================================================
class GuidanceItemFormDialog extends StatefulWidget {
  /// 构造函数：注入 ViewModel、所属模板与编辑目标（null 为新增）。
  const GuidanceItemFormDialog({super.key, required this.viewModel, required this.template, this.item});

  final GuidanceTemplateManagementViewModel viewModel;

  /// 所属模板（新增时挂载目标）。
  final BaseGuidanceTemplate template;

  /// 编辑的目标项目（null 表示新增）。
  final BaseGuidanceTemplateItem? item;

  @override
  State<GuidanceItemFormDialog> createState() => _GuidanceItemFormDialogState();
}

class _GuidanceItemFormDialogState extends State<GuidanceItemFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _typeCtrl;
  late final TextEditingController _guidanceCtrl;

  // 显式焦点链：类别输入框回车跳到内容输入框；内容为多行文本框不参与
  // 回车链（换行），由保存按钮提交
  final _typeFocus = FocusNode();
  final _guidanceFocus = FocusNode();

  late bool _personal;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 编辑模式回填目标项目；新增模式全空（默认公共模板）
    final item = widget.item;
    _typeCtrl = TextEditingController(text: item?.guidanceType);
    _guidanceCtrl = TextEditingController(text: item?.guidance);
    _personal = item?.isPersonalTemplate ?? false;
  }

  @override
  void dispose() {
    _typeCtrl.dispose();
    _guidanceCtrl.dispose();
    _typeFocus.dispose();
    _guidanceFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return; // 防重复提交
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    final viewModel = widget.viewModel;
    final item = widget.item;
    final type = _typeCtrl.text.trim();
    final guidance = _guidanceCtrl.text.trim();
    final personal = _personal ? BaseGuidanceTemplateItem.personalYes : BaseGuidanceTemplateItem.personalNo;
    final ok = item == null
        ? await viewModel.createItem(templateId: widget.template.id, guidanceType: type, guidance: guidance, isPersonal: personal)
        : await viewModel.updateItem(item.id, {
            'guidanceType': type,
            'guidance': guidance,
            'isPersonal': personal,
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
    final creating = widget.item == null;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
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
                      Expanded(
                        child: Text(
                          creating ? '新增指导建议——${widget.template.templateName}' : '编辑指导建议',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _typeCtrl,
                    focusNode: _typeFocus,
                    autofocus: true,
                    style: theme.textTheme.bodyMedium,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _guidanceFocus.requestFocus(),
                    decoration: _decoration(theme, '指导建议类别'),
                    validator: (v) {
                      final text = v?.trim() ?? '';
                      if (text.isNotEmpty && utf8.encode(text).length > 50) return '指导建议类别超出长度限制（50 字节）';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _guidanceCtrl,
                    focusNode: _guidanceFocus,
                    style: theme.textTheme.bodyMedium,
                    minLines: 5,
                    maxLines: 8,
                    decoration: _decoration(theme, '指导建议', required: true, alignLabelTop: true),
                    validator: (v) {
                      final text = v?.trim() ?? '';
                      if (text.isEmpty) return '请输入指导建议';
                      if (utf8.encode(text).length > 1000) return '指导建议超出长度限制（1000 字节）';
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 8),

                  // 底部操作行：【是否个人模板】开关（公共=全院可用 /
                  // 个人=仅本人初筛可选）与标签紧挨、整体靠左，【取消】/
                  //【添加】靠右（2026-11-27 需求：开关与操作按钮同行）
                  Row(
                    children: [
                      // 标签 + 开关紧挨成组（点标签也可切换）
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _saving ? null : () => setState(() => _personal = !_personal),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _personal ? '个人模板（仅本人可见）' : '公共模板（全院可见）',
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(width: 8),
                              Switch(
                                value: _personal,
                                onChanged: _saving ? null : (v) => setState(() => _personal = v),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
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

  /// 统一的毛玻璃输入框装饰（同模板表单对话框；多行文本标签随内容
  /// 顶部对齐）。
  InputDecoration _decoration(ThemeData theme, String label, {bool required = false, bool alignLabelTop = false}) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color),
    );
    return InputDecoration(
      alignLabelWithHint: alignLabelTop,
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
