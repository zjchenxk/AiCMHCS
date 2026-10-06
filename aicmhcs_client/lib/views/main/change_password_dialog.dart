import 'package:aicmhcs_client/widgets/glass_panel.dart';
import 'package:material_ui/material_ui.dart';

/// 修改密码对话框（毛玻璃风格）
/// 返回值：修改成功时返回 true，取消时返回 null
class ChangePasswordDialog extends StatefulWidget {
  final String username; // 用于弱口令检测：密码不能包含用户名

  const ChangePasswordDialog({super.key, this.username = ''});

  /// 静态方法，方便外部一行代码调用
  static Future<bool?> show(BuildContext context, {String username = ''}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false, // 防止误点背景关闭
      barrierColor: Colors.black26,
      builder: (_) => ChangePasswordDialog(username: username),
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

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;

  @override
  void dispose() {
    _oldPwdController.dispose();
    _newPwdController.dispose();
    _confirmPwdController.dispose();
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
                      Icon(Icons.key_outlined, color: theme.colorScheme.primary, size: 22),
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
                    '密码需包含大写字母、小写字母、数字和特殊字符，长度至少 8 位',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 16),

                  _buildPasswordField(
                    theme,
                    controller: _oldPwdController,
                    label: '原密码',
                    obscure: _obscureOld,
                    onToggle: () => setState(() => _obscureOld = !_obscureOld),
                    validator: (v) => (v == null || v.isEmpty) ? '请输入原密码' : null,
                  ),
                  const SizedBox(height: 12),

                  _buildPasswordField(
                    theme,
                    controller: _newPwdController,
                    label: '新密码',
                    obscure: _obscureNew,
                    onToggle: () => setState(() => _obscureNew = !_obscureNew),
                    // 便捷校验在 validator 中做，完整校验在提交时做
                    validator: (v) {
                      if (v == null || v.isEmpty) return '请输入新密码';
                      if (v.length < 8) return '密码长度不能少于 8 位';
                      final hasUpper = v.contains(RegExp(r'[A-Z]'));
                      final hasLower = v.contains(RegExp(r'[a-z]'));
                      final hasDigit = v.contains(RegExp(r'[0-9]'));
                      final hasSpecial = v.contains(RegExp(r'[!@#$%^&*()_+\-=\[\]{};:"\\|,.<>/?~`]'));
                      final kinds = [hasUpper, hasLower, hasDigit, hasSpecial].where((e) => e).length;
                      if (kinds < 4) return '需包含大小写字母、数字和特殊字符';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  _buildPasswordField(
                    theme,
                    controller: _confirmPwdController,
                    label: '确认新密码',
                    obscure: _obscureConfirm,
                    onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
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

  Widget _buildPasswordField(ThemeData theme, {required TextEditingController controller, required String label, required bool obscure, required VoidCallback onToggle, required String? Function(String?) validator}) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
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
          borderSide: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
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
    final error = _validateStrongPassword(_newPwdController.text, username: widget.username, oldPassword: _oldPwdController.text);
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
      // TODO: 调用服务端接口修改密码（服务端必须做同样的校验！）
      // await client.auth.changePassword(old, new);
      await Future.delayed(const Duration(milliseconds: 500)); // 模拟请求

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('修改密码失败：$e'),
        ),
      );
    }
  }

  /// 三级等保强密码校验结果
  /// 返回 null 表示通过，否则返回错误提示文本
  String? _validateStrongPassword(String password, {required String username, required String oldPassword}) {
    if (password.isEmpty) return '请输入新密码';
    if (password.length < 8) return '密码长度不能少于 8 位';
    if (password.length > 64) return '密码长度不能超过 64 位';
    if (password == oldPassword) return '新密码不能与原密码相同';
    if (username.isNotEmpty && password.toLowerCase().contains(username.toLowerCase())) {
      return '密码不能包含用户名';
    }

    final hasUpper = password.contains(RegExp(r'[A-Z]'));
    final hasLower = password.contains(RegExp(r'[a-z]'));
    final hasDigit = password.contains(RegExp(r'[0-9]'));
    final hasSpecial = password.contains(RegExp(r'''[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?~`€£¥§]'''));

    final kinds = [hasUpper, hasLower, hasDigit, hasSpecial].where((e) => e).length;
    if (kinds < 4) {
      return '密码必须同时包含大写字母、小写字母、数字和特殊字符';
    }

    // 连续字符检测（如 abc、123，正/逆序，长度≥3）
    for (int i = 0; i + 2 < password.length; i++) {
      final a = password.codeUnitAt(i);
      final b = password.codeUnitAt(i + 1);
      final c = password.codeUnitAt(i + 2);
      if (b == a + 1 && c == b + 1) return '密码不能包含连续字符（如 abc、123）';
      if (b == a - 1 && c == b - 1) return '密码不能包含连续字符（如 cba、321）';
    }

    // 重复字符检测（如 aaa、111，长度≥3）
    for (int i = 0; i + 2 < password.length; i++) {
      final a = password.codeUnitAt(i);
      if (password.codeUnitAt(i + 1) == a && password.codeUnitAt(i + 2) == a) {
        return '密码不能包含 3 个及以上重复字符';
      }
    }

    return null;
  }
}
