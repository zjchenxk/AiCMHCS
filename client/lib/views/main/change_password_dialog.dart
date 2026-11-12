import 'package:client/services/user_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:common/utils/password_policy.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:material_ui/material_ui.dart';

/// 修改密码对话框（毛玻璃风格）
/// 返回值：修改成功时返回 true，取消时返回 null
class ChangePasswordDialog extends StatefulWidget {
  final String userId; // 用于服务端接口调用
  final String username; // 用于弱口令检测：密码不能包含用户名

  const ChangePasswordDialog({super.key, this.userId = '', this.username = ''});

  /// 静态方法，方便外部一行代码调用
  static Future<bool?> show(BuildContext context, {String userId = '', String username = ''}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false, // 防止误点背景关闭
      barrierColor: Colors.black26,
      builder: (_) => ChangePasswordDialog(userId: userId, username: username),
    );
  }

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _oldPwdController = TextEditingController();
  final _newPwdController = TextEditingController();
  final _confirmPwdController = TextEditingController();

  // 回车跳格用的显式焦点链：原密码→新密码→确认新密码（回车提交）
  late final FocusNode _oldPwdFocus;
  late final FocusNode _newPwdFocus;
  late final FocusNode _confirmPwdFocus;

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _oldPwdFocus = FocusNode();
    _newPwdFocus = FocusNode();
    _confirmPwdFocus = FocusNode();
  }

  @override
  void dispose() {
    _oldPwdController.dispose();
    _newPwdController.dispose();
    _confirmPwdController.dispose();
    _oldPwdFocus.dispose();
    _newPwdFocus.dispose();
    _confirmPwdFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      // 收窄对话框左右边距，让宽度由内容决定
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        // 限定内容区宽度，弹窗固定为 420
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
                        Icons.key_outlined,
                        color: theme.colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '修改密码',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  Text(
                    '密码需包含大写字母、小写字母、数字和特殊字符，长度至少 8-32 位',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 16),

                  _buildPasswordField(
                    theme,
                    controller: _oldPwdController,
                    focusNode: _oldPwdFocus,
                    label: '原密码',
                    obscure: _obscureOld,
                    onToggle: () => setState(() => _obscureOld = !_obscureOld),
                    onFieldSubmitted: (_) => _newPwdFocus.requestFocus(),
                    // 中间输入框回车跳下一框用 next，最后一个用 done（回车直接提交）
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || v.isEmpty) ? '请输入原密码' : null,
                  ),
                  const SizedBox(height: 12),

                  _buildPasswordField(
                    theme,
                    controller: _newPwdController,
                    focusNode: _newPwdFocus,
                    label: '新密码',
                    obscure: _obscureNew,
                    onToggle: () => setState(() => _obscureNew = !_obscureNew),
                    onFieldSubmitted: (_) => _confirmPwdFocus.requestFocus(),
                    textInputAction: TextInputAction.next,
                    // 便捷校验在 validator 中做，完整校验在提交时做
                    validator: PasswordPolicy.quickError,
                  ),
                  const SizedBox(height: 12),

                  _buildPasswordField(
                    theme,
                    controller: _confirmPwdController,
                    focusNode: _confirmPwdFocus,
                    label: '确认新密码',
                    obscure: _obscureConfirm,
                    onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    // 最后一个输入框回车直接提交
                    onFieldSubmitted: (_) => _submit(),
                    textInputAction: TextInputAction.done,
                    validator: (v) {
                      if (v == null || v.isEmpty) return '请再次输入新密码';
                      if (v != _newPwdController.text) return '两次输入的密码不一致';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // 操作按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                        child: Text(
                          '取消',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
                        ),
                      ),
                      const SizedBox(width: 12),

                      FilledButton(
                        onPressed: _submitting ? null : _submit,
                        style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.primary),
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
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
    );
  }

  Widget _buildPasswordField(
    ThemeData theme, {
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    required ValueChanged<String> onFieldSubmitted,
    required TextInputAction textInputAction,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      textInputAction: textInputAction,
      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
      decoration: InputDecoration(
        labelText: label,
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.colorScheme.error, width: 1.5),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20,
            color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // 表单校验通过后，再执行一次完整强密码校验（包含用户名/旧密码比对）
    final error = PasswordPolicy.strongError(
      _newPwdController.text,
      username: widget.username,
      oldPassword: _oldPwdController.text,
    );
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await UserService().changePassword(
        userId: widget.userId,
        oldPassword: _oldPwdController.text,
        newPassword: _newPwdController.text,
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e, st) {
      LogHelper.error('client:ChangePasswordDialog._submit', e, st);

      if (!mounted) return;

      setState(() => _submitting = false);

      final msg = e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('修改密码失败：$msg')));
    }
  }
}
