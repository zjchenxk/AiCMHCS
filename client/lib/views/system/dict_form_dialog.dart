import 'package:client/view_models/system/dict_management_view_model.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

// =====================================================================
// 数据字典表单对话框（字典管理页新增/编辑共用）
//
// 毛玻璃对话框：新增模式全空待录（挂载目标取自 ViewModel 的新增状态，
// 页面发起前经 startCreate 设置）、编辑模式回填选中字典；提交期间
// 保持打开（按钮转进度），失败保留输入并内联显示错误信息，成功后
// 关闭并由调用方提示。
// =====================================================================
class DictFormDialog extends StatefulWidget {
  /// 构造函数：注入 ViewModel 与编辑目标（null 为新增）。
  const DictFormDialog({super.key, required this.viewModel, this.dict});

  final DictManagementViewModel viewModel;

  /// 编辑的目标字典（null 表示新增）。
  final Dict? dict;

  @override
  State<DictFormDialog> createState() => _DictFormDialogState();
}

class _DictFormDialogState extends State<DictFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _orderCtrl;

  // 显式焦点链：回车定向跳到下一输入框（nextFocus 依遍历序前进，在
  // 部分平台与输入动作自动跳格叠加会连跳两步、跳过字典名称）
  final _codeFocus = FocusNode();
  final _nameFocus = FocusNode();
  final _orderFocus = FocusNode();

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 编辑模式回填目标字典；新增模式全空
    final dict = widget.dict;
    _codeCtrl = TextEditingController(text: dict?.dictCode);
    _nameCtrl = TextEditingController(text: dict?.dictName);
    _orderCtrl = TextEditingController(text: dict?.displayOrder);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _orderCtrl.dispose();
    _codeFocus.dispose();
    _nameFocus.dispose();
    _orderFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return; // 防回车重复提交
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    final viewModel = widget.viewModel;
    final dict = widget.dict;
    final order = _orderCtrl.text.trim();
    final displayOrder = order.isEmpty ? null : order;
    final ok = dict == null
        ? await viewModel.createDict(
            dictCode: _codeCtrl.text.trim(),
            dictName: _nameCtrl.text.trim(),
            displayOrder: displayOrder,
          )
        : await viewModel.updateDict(dict.id, {
            'dictCode': _codeCtrl.text.trim(),
            'dictName': _nameCtrl.text.trim(),
            'displayOrder': displayOrder,
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
    final creating = widget.dict == null;

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
                        creating ? Icons.library_add_outlined : Icons.edit_outlined,
                        color: theme.colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        creating ? '新增数据字典' : '编辑数据字典',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  if (creating) ...[
                    const SizedBox(height: 8),
                    // 挂载位置说明（新增发起前由页面经 startCreate 设置）
                    Text(
                      widget.viewModel.createTargetLabel,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _codeCtrl,
                    focusNode: _codeFocus,
                    autofocus: true,
                    maxLength: 10,
                    style: theme.textTheme.bodyMedium,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _nameFocus.requestFocus(),
                    decoration: _decoration(theme, '字典编码', required: true),
                    validator: (v) => (v == null || v.trim().isEmpty) ? '请输入字典编码' : null,
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _nameCtrl,
                    focusNode: _nameFocus,
                    maxLength: 50,
                    style: theme.textTheme.bodyMedium,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _orderFocus.requestFocus(),
                    decoration: _decoration(theme, '字典名称', required: true),
                    validator: (v) => (v == null || v.trim().isEmpty) ? '请输入字典名称' : null,
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _orderCtrl,
                    focusNode: _orderFocus,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: theme.textTheme.bodyMedium,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: _decoration(theme, '显示顺序'),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return null; // 可选字段
                      final n = int.tryParse(t);
                      if (n == null || n < 0 || n > 32767) return '显示顺序须为 0-32767 的整数';
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
                            : Icon(creating ? Icons.library_add_outlined : Icons.save_outlined, size: 18),
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

  /// 统一的毛玻璃输入框装饰（同角色表单）。
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
      counterText: '',
    );
  }
}
