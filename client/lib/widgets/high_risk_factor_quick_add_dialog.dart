import 'package:client/main.dart';
import 'package:client/services/high_risk_factor_service.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 快速新增高危因素对话框（儿童建档高危因素 TAB 复用）：高危颜色下拉
/// （仅黄/橙/红/紫，必填）+ 高危因素名称输入（必填），确定后调
/// quickCreate 保存（大类默认「其它」、编码按颜色默认映射、允许重复）
/// 并返回新增的字典项。
class HighRiskFactorQuickAddDialog extends StatefulWidget {
  const HighRiskFactorQuickAddDialog({super.key});

  /// 打开对话框，返回新增的高危因素字典项；取消/失败返回 null。
  static Future<BaseHighRiskFactor?> show(BuildContext context) {
    return showDialog<BaseHighRiskFactor>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const HighRiskFactorQuickAddDialog(),
    );
  }

  @override
  State<HighRiskFactorQuickAddDialog> createState() => _HighRiskFactorQuickAddDialogState();
}

class _HighRiskFactorQuickAddDialogState extends State<HighRiskFactorQuickAddDialog> {
  /// 可选高危颜色（不含绿色——绿色卡片仅预置「无高危因素」特选项）。
  static const Map<String, String> _colorOptions = {
    '黄色': '02990000',
    '橙色': '03990000',
    '红色': '04990000',
    '紫色': '05990000',
  };

  final GlobalKey<FormFieldState<String>> _colorKey = GlobalKey<FormFieldState<String>>();
  final GlobalKey<FormFieldState<String>> _nameKey = GlobalKey<FormFieldState<String>>();
  final TextEditingController _nameCtrl = TextEditingController();
  String? _color;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final colorOk = _colorKey.currentState?.validate() ?? false;
    final nameOk = _nameKey.currentState?.validate() ?? false;
    if (!colorOk || !nameOk || _color == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final factor = await getIt<HighRiskFactorService>().quickCreate(
        riskColor: _color!,
        riskFactorName: _nameCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(factor);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassPanel(
          blur: 24,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      //Icon(Icons.add_circle_outline, color: theme.colorScheme.primary, size: 22),
                      //const SizedBox(width: 10),
                      Text(
                        '新增高危因素',
                        style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: _colorKey,
                    initialValue: _color,
                    isExpanded: true,
                    items: _colorOptions.keys
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(c, style: theme.textTheme.bodyMedium),
                          ),
                        )
                        .toList(),
                    hint: Text('请选择高危颜色', style: theme.textTheme.bodyMedium),
                    decoration: InputDecoration(
                      label: Text.rich(
                        TextSpan(
                          text: '高危颜色',
                          style: theme.textTheme.bodyMedium,
                          children: [
                            TextSpan(
                              text: ' *',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: theme.colorScheme.primary),
                      ),
                    ),
                    style: theme.textTheme.bodyMedium,
                    validator: (v) => (v == null || v.isEmpty) ? '请选择高危颜色' : null,
                    onChanged: (v) => setState(() => _color = v),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: _nameKey,
                    controller: _nameCtrl,
                    maxLength: 200,
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      label: Text.rich(
                        TextSpan(
                          text: '高危因素名称',
                          style: theme.textTheme.bodyMedium,
                          children: [
                            TextSpan(
                              text: ' *',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: theme.colorScheme.primary),
                      ),
                      counterText: '',
                    ),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (v) => (v == null || v.trim().isEmpty) ? '请输入高危因素名称' : null,
                  ),
                  const SizedBox(height: 8),
                  if (_error != null) Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving ? null : () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _saving ? null : _confirm,
                        child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('确定'),
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
}
