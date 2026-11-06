import 'package:client/utils/log_helper.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 院区新增/编辑对话框（毛玻璃风格）。
/// [initial] 为空表示新增（表单清空），否则编辑该院区；
/// [onSubmit] 由调用方注入落库逻辑（返回 true 表示成功），对话框只负责
/// 表单校验与提交中状态。
/// 返回值：保存成功时返回 true，取消时返回 null。
class CampusEditDialog extends StatefulWidget {
  final String hospitalName;
  final Campus? initial;
  final Future<bool> Function(String code, String name, String? address, String? tel) onSubmit;

  const CampusEditDialog({
    super.key,
    required this.hospitalName,
    required this.onSubmit,
    this.initial,
  });

  /// 静态方法，方便外部一行代码调用
  static Future<bool?> show(
    BuildContext context, {
    required String hospitalName,
    Campus? initial,
    required Future<bool> Function(String code, String name, String? address, String? tel) onSubmit,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false, // 防止误点背景关闭
      barrierColor: Colors.black26,
      builder: (_) => CampusEditDialog(
        hospitalName: hospitalName,
        initial: initial,
        onSubmit: onSubmit,
      ),
    );
  }

  @override
  State<CampusEditDialog> createState() => _CampusEditDialogState();
}

class _CampusEditDialogState extends State<CampusEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _telController;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.initial?.code ?? '');
    _nameController = TextEditingController(text: widget.initial?.name ?? '');
    _addressController = TextEditingController(text: widget.initial?.address ?? '');
    _telController = TextEditingController(text: widget.initial?.tel ?? '');
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _telController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.initial != null;

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
                        Icons.domain_outlined,
                        color: theme.colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        editing ? '编辑院区' : '新增院区',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '所属医院：${widget.hospitalName}（院区代码全表唯一，名称同医院内唯一）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _buildField(
                    theme,
                    controller: _codeController,
                    label: '院区代码',
                    icon: Icons.tag_outlined,
                    validator: (v) => (v == null || v.trim().isEmpty) ? '请输入院区代码' : null,
                  ),
                  const SizedBox(height: 12),

                  _buildField(
                    theme,
                    controller: _nameController,
                    label: '院区名称',
                    icon: Icons.label_outline,
                    validator: (v) => (v == null || v.trim().isEmpty) ? '请输入院区名称' : null,
                  ),
                  const SizedBox(height: 12),

                  _buildField(
                    theme,
                    controller: _addressController,
                    label: '院区地址（选填）',
                    icon: Icons.location_on_outlined,
                  ),
                  const SizedBox(height: 12),

                  _buildField(
                    theme,
                    controller: _telController,
                    label: '联系电话（选填）',
                    icon: Icons.call_outlined,
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
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      FilledButton(
                        onPressed: _submitting ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                '保存',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onPrimary,
                                ),
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

  Widget _buildField(
    ThemeData theme, {
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onPrimaryContainer,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
        ),
        // 毛玻璃底色：半透明 surface
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.6,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
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
        prefixIcon: Icon(
          icon,
          size: 20,
          color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      final ok = await widget.onSubmit(
        _codeController.text.trim(),
        _nameController.text.trim(),
        _addressController.text.trim(),
        _telController.text.trim(),
      );
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        // 失败提示由页面 errorMsg 监听统一弹出，对话框保留输入
        setState(() => _submitting = false);
      }
    } catch (e, st) {
      LogHelper.error('client:CampusEditDialog._submit', e, st);
      if (!mounted) return;
      setState(() => _submitting = false);
    }
  }
}
