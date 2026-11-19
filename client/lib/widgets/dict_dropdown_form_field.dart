import 'package:client/utils/dict_options.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 数据字典下拉表单字段：按字典编码异步加载数据项（经 [DictOptions]
/// 公共缓存），值存 BASE_DICT_ITEM.ITEM_VALUE、显示项目值，供各业务
/// 表单统一绑定数据字典。
///
/// 加载中/字典未配置/加载失败时下拉禁用并给出提示；[autoSelectDefault]
/// 为 true（新增场景）且未指定初值时自动选中 IS_DEFAULT='1' 的默认项。
class DictDropdownFormField extends StatefulWidget {
  const DictDropdownFormField({
    super.key,
    required this.dictCode,
    required this.label,
    this.initialValue,
    this.onChanged,
    this.validator,
    this.enabled = true,
    this.required = false,
    this.autoSelectDefault = false,
    this.formFieldKey,
  });

  /// 数据字典编码（BASE_DICT.DICT_CODE，如 0101001-国籍）。
  final String dictCode;

  /// 字段标签（hint/校验文案用）。
  final String label;

  /// 当前值（ITEM_VALUE）。
  final String? initialValue;

  /// 值变更回调（disabled 时不触发）。
  final ValueChanged<String?>? onChanged;

  /// 校验器（缺省按 [required] 生成必选校验）。
  final String? Function(String?)? validator;

  /// 是否可编辑（外部联动灰化控制入口）。
  final bool enabled;

  /// 是否必选（必填红星 + 缺省必选校验）。
  final bool required;

  /// 新增场景无初值时自动选中字典默认项。
  final bool autoSelectDefault;

  /// 表单字段全局键（长表单校验定位用）。
  final GlobalKey<FormFieldState<String>>? formFieldKey;

  @override
  State<DictDropdownFormField> createState() => _DictDropdownFormFieldState();
}

class _DictDropdownFormFieldState extends State<DictDropdownFormField> {
  /// 数据项（null = 加载中；空列表 = 未配置/加载失败）。
  List<DictItem>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await DictOptions.instance.itemsOf(widget.dictCode);
      if (mounted) {
        setState(() => _items = items);
      }
    } catch (_) {
      // 加载失败按空字典处理（下拉禁用显示提示，不阻塞整页表单）
      if (mounted) {
        setState(() => _items = const []);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;
    final ready = items != null && items.isNotEmpty;
    final enabled = widget.enabled && ready;

    // 新增场景：无初值且已就绪时选中默认项
    String? initialValue = widget.initialValue;
    if (initialValue == null && widget.autoSelectDefault && items != null) {
      for (final item in items) {
        if (item.isDefault == '1') {
          initialValue = item.itemValue;
          break;
        }
      }
    }

    // 下拉候选项：字典就绪后按数据项构建；存量值不在当前字典项中
    // （字典项被删除/改值）时补一个同名候选项，避免下拉断言崩溃，
    // 用户可重新选择现行字典项。
    final options = ready
        ? items
              .map(
                (e) => DropdownMenuItem(
                  value: e.itemValue,
                  child: Text(e.itemValue, style: theme.textTheme.bodyMedium),
                ),
              )
              .toList()
        : <DropdownMenuItem<String>>[];
    if (ready && initialValue != null && !options.any((e) => e.value == initialValue)) {
      options.insert(
        0,
        DropdownMenuItem(
          value: initialValue,
          child: Text(initialValue, style: theme.textTheme.bodyMedium),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      key: widget.formFieldKey,
      initialValue: initialValue,
      isExpanded: true,
      items: ready ? options : null,
      // 可编辑性显式由 enabled 决定（material_ui 1.8.0 起新增该参数，
      // 显式传入不依赖「onChanged 为 null 即禁用」的兼容路径）；禁用态
      // 下 onChanged 不会触发。调用方可以不传 onChanged（值经
      // formFieldKey 在提交时统一收集），此时下拉同样可正常选择
      enabled: enabled,
      hint: Text(
        items == null ? '加载中...' : (items.isEmpty ? '字典未配置' : '请选择${widget.label}'),
        style: theme.textTheme.bodyMedium,
      ),
      decoration: _glassDecoration(theme, widget.label, required: widget.required),
      style: theme.textTheme.bodyMedium,
      validator: widget.validator ?? (widget.required ? (v) => (v == null || v.trim().isEmpty) ? '请选择${widget.label}' : null : null),
      onChanged: (v) {
        widget.onChanged?.call(v);
      },
    );
  }

  /// 统一的毛玻璃输入框装饰（与 user_info_form 的 glassDecoration 同款）。
  InputDecoration _glassDecoration(ThemeData theme, String label, {bool required = false}) {
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
      counterText: '', // 隐藏 maxLength 计数器（保留输入截断）
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.6,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: glassBorder(
        theme,
        theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
      ),
      enabledBorder: glassBorder(
        theme,
        theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
      ),
      focusedBorder: glassBorder(theme, theme.colorScheme.primary),
    );
  }
}
