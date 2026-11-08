import 'package:client/view_models/system/role_management_view_model.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

// =====================================================================
// 角色表单对话框（角色管理页新增/编辑共用）
//
// 毛玻璃对话框：新增模式全空待录、编辑模式回填选中角色；提交期间
// 保持打开（按钮转进度），失败保留输入并内联显示错误信息，成功后
// 关闭并由调用方提示。
// =====================================================================
class RoleFormDialog extends StatefulWidget {
  /// 构造函数：注入 ViewModel 与编辑目标（null 为新增）。
  const RoleFormDialog({super.key, required this.viewModel, this.role});

  final RoleManagementViewModel viewModel;

  /// 编辑的目标角色（null 表示新增）。
  final Role? role;

  @override
  State<RoleFormDialog> createState() => _RoleFormDialogState();
}

class _RoleFormDialogState extends State<RoleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _remarkCtrl;

  // 显式焦点链：回车定向跳到下一输入框（nextFocus 依遍历序前进，在
  // 部分平台与输入动作自动跳格叠加会连跳两步、跳过角色名称）
  final _codeFocus = FocusNode();
  final _nameFocus = FocusNode();
  final _remarkFocus = FocusNode();

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 编辑模式回填目标角色；新增模式全空
    final role = widget.role;
    _codeCtrl = TextEditingController(text: role?.roleCode);
    _nameCtrl = TextEditingController(text: role?.roleName);
    _remarkCtrl = TextEditingController(text: role?.remark);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _remarkCtrl.dispose();
    _codeFocus.dispose();
    _nameFocus.dispose();
    _remarkFocus.dispose();
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
    final role = widget.role;
    final ok = role == null
        ? await viewModel.createRole(
            roleCode: _codeCtrl.text.trim(),
            roleName: _nameCtrl.text.trim(),
            remark: _remarkCtrl.text.trim(),
          )
        : await viewModel.updateRole(role.id, {
            'roleCode': _codeCtrl.text.trim(),
            'roleName': _nameCtrl.text.trim(),
            'remark': _remarkCtrl.text.trim(),
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
    final creating = widget.role == null;

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
                        creating ? Icons.add_business_outlined : Icons.edit_outlined,
                        color: theme.colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        creating ? '新增角色' : '编辑角色',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _codeCtrl,
                    focusNode: _codeFocus,
                    autofocus: true,
                    style: theme.textTheme.bodyMedium,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _nameFocus.requestFocus(),
                    decoration: _decoration(theme, '角色编码', required: true),
                    validator: (v) => (v == null || v.trim().isEmpty) ? '请输入角色编码' : null,
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _nameCtrl,
                    focusNode: _nameFocus,
                    style: theme.textTheme.bodyMedium,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _remarkFocus.requestFocus(),
                    decoration: _decoration(theme, '角色名称', required: true),
                    validator: (v) => (v == null || v.trim().isEmpty) ? '请输入角色名称' : null,
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _remarkCtrl,
                    focusNode: _remarkFocus,
                    style: theme.textTheme.bodyMedium,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: _decoration(theme, '备注'),
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
                            : Icon(creating ? Icons.add_business_outlined : Icons.save_outlined, size: 18),
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

  /// 统一的毛玻璃输入框装饰（同院区表单）。
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
