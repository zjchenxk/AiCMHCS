import 'package:material_ui/material_ui.dart';

import 'glass_panel.dart';

/// 弹出毛玻璃月份选择对话框（单选一个月）。
///
///param context: 构建对话框的上下文
///param title: 对话框标题（如「选择起始月」「选择截止月」）
///param initialMonth: 初始定位月份（'yyyy-MM'，所在年份为宫格展示年份）
///param firstMonth: 可选最早月（'yyyy-MM'，含；null 不限）
///param lastMonth: 可选最晚月（'yyyy-MM'，含；null 不限）
///returns: 选中月份 'yyyy-MM'；取消（点击遮罩）返回 null
Future<String?> showMonthPickerDialog({
  required BuildContext context,
  required String title,
  required String initialMonth,
  String? firstMonth,
  String? lastMonth,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _MonthPickerDialog(
      title: title,
      initialMonth: initialMonth,
      firstMonth: firstMonth,
      lastMonth: lastMonth,
    ),
  );
}

class _MonthPickerDialog extends StatefulWidget {
  final String title;
  final String initialMonth;
  final String? firstMonth;
  final String? lastMonth;

  const _MonthPickerDialog({required this.title, required this.initialMonth, this.firstMonth, this.lastMonth});

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _displayYear;

  @override
  void initState() {
    super.initState();
    _displayYear = int.parse(widget.initialMonth.substring(0, 4));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: GlassPanel(
          blur: 24,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _buildYearSwitcher(theme),
                const SizedBox(height: 8),
                _buildMonthGrid(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 年份切换行：‹ 年份 ›（越界年侧禁用，避免空转）
  Widget _buildYearSwitcher(ThemeData theme) {
    final minYear = widget.firstMonth != null ? int.parse(widget.firstMonth!.substring(0, 4)) : null;
    final maxYear = widget.lastMonth != null ? int.parse(widget.lastMonth!.substring(0, 4)) : null;
    final canPrev = minYear == null || _displayYear > minYear;
    final canNext = maxYear == null || _displayYear < maxYear;

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_outlined),
          tooltip: '上一年',
          onPressed: canPrev ? () => setState(() => _displayYear--) : null,
        ),
        Expanded(
          child: Center(
            child: Text('$_displayYear 年', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_outlined),
          tooltip: '下一年',
          onPressed: canNext ? () => setState(() => _displayYear++) : null,
        ),
      ],
    );
  }

  // 3×4 月宫格：窗口外的月份禁用
  Widget _buildMonthGrid(ThemeData theme) {
    final cells = <Widget>[];
    for (var month = 1; month <= 12; month++) {
      String two(int n) => n.toString().padLeft(2, '0');
      final key = '$_displayYear-${two(month)}';
      final enabled = _isEnabled(key);
      final selected = widget.initialMonth == key;

      cells.add(
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? () => Navigator.of(context).pop(key) : null,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? theme.colorScheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: enabled ? 0.4 : 0.15),
                width: 0.5,
              ),
            ),
            child: Text(
              '$month 月',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: selected
                    ? theme.colorScheme.onPrimary
                    : enabled
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.6,
      children: cells,
    );
  }

  bool _isEnabled(String monthKey) {
    final first = widget.firstMonth;
    final last = widget.lastMonth;
    if (first != null && monthKey.compareTo(first) < 0) {
      return false;
    }
    if (last != null && monthKey.compareTo(last) > 0) {
      return false;
    }
    return true;
  }
}
