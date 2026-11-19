import 'package:client/widgets/glass_panel.dart';
import 'package:material_ui/material_ui.dart';

/// 高危因素备注编辑对话框：单行备注输入（≤100 字）+【确定】/【取消】。
///
/// 返回输入的备注文本；点【取消】/关闭返回 null（区别于「确定清空」：
/// 确定时输入为空返回空串，表示清除该高危因素的备注）。
class HighRiskFactorRemarkDialog extends StatefulWidget {
  const HighRiskFactorRemarkDialog({super.key, required this.factorName, this.initialRemark});

  /// 高危因素名称（标题展示）。
  final String factorName;

  /// 已有备注（编辑时回填）。
  final String? initialRemark;

  /// 打开对话框，返回备注文本（空串=清除备注）；取消返回 null。
  static Future<String?> show(BuildContext context, {required String factorName, String? initialRemark}) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => HighRiskFactorRemarkDialog(factorName: factorName, initialRemark: initialRemark),
    );
  }

  @override
  State<HighRiskFactorRemarkDialog> createState() => _HighRiskFactorRemarkDialogState();
}

class _HighRiskFactorRemarkDialogState extends State<HighRiskFactorRemarkDialog> {
  final GlobalKey<FormFieldState<String>> _remarkKey = GlobalKey<FormFieldState<String>>();
  late final TextEditingController _ctrl = TextEditingController(text: widget.initialRemark ?? '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _confirm() {
    setState(() => _ctrl.text = _ctrl.text.trim());
    Navigator.of(context).pop(_ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
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
                    //Icon(Icons.edit_note_outlined, color: theme.colorScheme.primary, size: 22),
                    //const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '备注',
                        style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: _remarkKey,
                  controller: _ctrl,
                  maxLength: 100,
                  autofocus: true,
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    labelText: '备注',
                    labelStyle: theme.textTheme.bodyMedium,
                    helperText: '留空并确定可清除备注',
                    counterText: '',
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
                  onFieldSubmitted: (_) => _confirm(),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
                    const SizedBox(width: 12),
                    FilledButton(onPressed: _confirm, child: const Text('确定')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
