import 'package:client/utils/menu_icons.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:material_ui/material_ui.dart';

// =====================================================================
// 图标选择器对话框（菜单管理表单的菜单图标字段触发）
//
// 数据源为生成文件 icon_map_helper 的 iconMap 全量清单（menuIconEntries
// 按名称排序，默认变体两千余项，直接进下拉菜单无法定位，故做成本
// 可搜索的毛玻璃选择面板：搜索框实时过滤 + 图标网格点选）。
//
// 返回值约定：选中图标返回其名称；「不设置」返回空串（调用方清除）；
// 取消/关闭返回 null（调用方保持不变）。
// =====================================================================

/// 打开图标选择器，返回选中的图标名（空串表示不设置、null 表示取消）。
Future<String?> showMenuIconPicker(BuildContext context, {String? current}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: GlassPanel(blur: 24, child: _MenuIconPickerPanel(current: current)),
      ),
    ),
  );
}

class _MenuIconPickerPanel extends StatefulWidget {
  const _MenuIconPickerPanel({this.current});

  /// 进入时已选中的图标名（网格内高亮）。
  final String? current;

  @override
  State<_MenuIconPickerPanel> createState() => _MenuIconPickerPanelState();
}

class _MenuIconPickerPanelState extends State<_MenuIconPickerPanel> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    //获取当前主题
    final ThemeData theme = Theme.of(context);
    final q = _query.trim().toLowerCase();
    final entries = q.isEmpty ? menuIconEntries : menuIconEntries.where((e) => e.key.toLowerCase().contains(q)).toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Row(
            children: [
              Icon(Icons.apps, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '选择菜单图标',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '关闭',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 搜索框（实时过滤图标名）
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.search,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: '搜索图标名称',
              hintStyle: theme.textTheme.bodySmall,
              prefixIcon: const Icon(Icons.search_outlined, size: 18),
              isDense: true,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.6,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.colorScheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 图标网格
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      '未找到匹配的图标',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  )
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 96,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      childAspectRatio: 0.9,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final name = entries[i].key;
                      final selected = name == widget.current;
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.pop(context, name),
                        child: Container(
                          decoration: selected
                              ? BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(10),
                                )
                              : null,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                entries[i].value,
                                size: 22,
                                color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.8),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),

          // 底部按钮：取消 / 不设置（清除图标）
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, ''),
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('不设置'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
