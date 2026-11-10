import 'package:client/utils/icon_map_helper.dart';
import 'package:material_ui/material_ui.dart';

/// 菜单管理模块的图标工具：可选图标清单与项目类型标签。
///
/// 图标数据源为生成文件 icon_map_helper 的 iconMap（全量映射，按名称
/// 排序），供表单选择与树节点展示共用；查不到的存量名经
/// iconFromNameOrFallback 兜底。

/// 全量可选图标清单（iconMap 按名称排序）。
final List<MapEntry<String, IconData>> menuIconEntries = iconMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

/// 项目类型标签（对应 SYS_MENU.ITEM_TYPE）。
const Map<String, String> menuItemTypeLabels = {
  '1': '模块',
  '2': '菜单',
  '3': '操作',
};

const Map<String, String> menuItemVisibleLabels = {
  '0': '隐藏',
  '1': '显示',
};

/// 项目类型标签（未知类型回退原值展示）。
String menuItemTypeLabel(String itemType) => menuItemTypeLabels[itemType] ?? itemType;

/// 按图标名取 IconData：经 iconFromNameOrFallback 兜底，仍查不到给
/// 占位图标；空值直接给占位图标。
IconData menuIconOrFallback(String? name, {IconData fallback = Icons.widgets_outlined}) {
  if (name == null || name.isEmpty) return fallback;
  return iconFromNameOrFallback(name, fallback: fallback);
}

/// 项目类型默认图标（未设置 MENU_ICON 时树节点与表单预览按类型回退）。
IconData menuItemTypeIcon(String itemType) => switch (itemType) {
  '1' => Icons.widgets_outlined,
  '2' => Icons.menu_book_outlined,
  '3' => Icons.touch_app_outlined,
  _ => Icons.widgets_outlined,
};
