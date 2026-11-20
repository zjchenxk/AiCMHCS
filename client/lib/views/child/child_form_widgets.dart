import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// 儿童建档表单共用小部件：毛玻璃输入框装饰、分组标题、布尔下拉等，
/// 供基本信息/扩展信息/监护人三个表单复用（样式与 user_info_form 的
/// glassDecoration 同款，跟随主题，不硬编码颜色）。

/// 统一的毛玻璃输入框装饰（required 时标签带红色星号）。
InputDecoration childGlassDecoration(ThemeData theme, String label, {bool required = false, String? helper}) {
  OutlineInputBorder glassBorder(ThemeData theme, Color color) => OutlineInputBorder(
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
                  style: TextStyle(color: theme.colorScheme.error), // 红色星号
                ),
              ],
            ),
          )
        : Text(label, style: theme.textTheme.bodyMedium),
    helperText: helper,
    counterText: '', // 隐藏 maxLength 计数器（保留输入截断）
    filled: true,
    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: glassBorder(theme, theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
    enabledBorder: glassBorder(theme, theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
    focusedBorder: glassBorder(theme, theme.colorScheme.primary),
  );
}

/// 表单分组标题（左侧主题色竖条 + 加粗标题）。
Widget childSectionTitle(ThemeData theme, String title) {
  return Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: Row(
      children: [
        Container(width: 4, height: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
      ],
    ),
  );
}

/// 有无/是否类下拉（值 0/1，显示 无/有；entries 可覆盖为三态等），
/// disabled 时灰化并显示提示。
Widget childFlagDropdown({
  GlobalKey<FormFieldState<String>>? fieldKey,
  required ThemeData theme,
  required String label,
  required String? value,
  required ValueChanged<String?> onChanged,
  required bool enabled,
  Map<String, String> entries = const {'0': '无', '1': '有'},
  bool required = false,
}) {
  final canEdit = enabled && entries.isNotEmpty;
  return DropdownButtonFormField<String>(
    key: fieldKey,
    // 存量值不在当前选项内（如老档案 SGA_TYPE 存「轻度SGA」而选项已改
    // 匀称型/非匀称型）时回退空值显示 hint，避免下拉断言崩溃；重新选择
    // 后按新值域保存
    initialValue: entries.keys.contains(value) ? value : null,
    isExpanded: true,
    items: canEdit
        ? entries.entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, style: theme.textTheme.bodyMedium),
                ),
              )
              .toList()
        : null,
    hint: Text('请选择$label', style: theme.textTheme.bodyMedium),
    decoration: childGlassDecoration(theme, label, required: required),
    style: theme.textTheme.bodyMedium,
    validator: required ? (v) => (v == null || v.trim().isEmpty) ? '请选择$label' : null : null,
    onChanged: canEdit ? onChanged : null,
  );
}

/// 表单文本输入框（显式 FocusNode 回车链：onFieldSubmitted 定向跳转到
/// nextNode；末框由调用方传 onFieldSubmitted: 提交）。
Widget childTextField({
  GlobalKey<FormFieldState<String>>? fieldKey,
  required ThemeData theme,
  required TextEditingController controller,
  required String label,
  bool required = false,
  bool enabled = true,
  bool readOnly = false,
  int? maxLength,
  FocusNode? focusNode,
  FocusNode? nextNode,
  void Function(String)? onFieldSubmitted,
  List<TextInputFormatter>? inputFormatters,
  TextInputType? keyboardType,
  String? Function(String?)? validator,
  int maxLines = 1,
}) {
  return TextFormField(
    key: fieldKey,
    controller: controller,
    enabled: enabled,
    readOnly: readOnly,
    maxLength: maxLength,
    focusNode: focusNode,
    textInputAction: nextNode != null ? TextInputAction.next : TextInputAction.done,
    onFieldSubmitted: (value) {
      if (onFieldSubmitted != null) {
        onFieldSubmitted(value);
        return;
      }
      nextNode?.requestFocus();
    },
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    maxLines: maxLines,
    autovalidateMode: AutovalidateMode.disabled,
    decoration: childGlassDecoration(theme, label, required: required),
    style: theme.textTheme.bodyMedium,
    validator: validator,
  );
}
