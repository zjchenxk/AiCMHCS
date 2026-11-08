import 'package:common/model.dart';

/// 菜单管理树节点（模块→菜单→操作，按 PARENT_ID 递归，用于菜单管理页
/// 左侧）。节点全部来自 SYS_MENU 数据（无虚拟根），顶级项目为多根列表。
class MenuTreeNode {
  /// 构造函数：注入节点 ID 与原始菜单数据。
  MenuTreeNode({
    required this.id,
    required this.menu,
    List<MenuTreeNode>? children,
    this.expanded = true,
  }) : children = children ?? [];

  /// 菜单项目 ID（字符串形式的自增主键）。
  final String id;

  /// 节点携带的原始菜单数据。
  final Menu menu;

  /// 显示名称（随保存后的重拉更新）。
  String get name => menu.itemName;

  /// 子节点列表。
  final List<MenuTreeNode> children;

  /// 展开状态（重建树时保留）。
  bool expanded;

  /// 树内唯一键。
  String get key => 'menu:$id';

  bool get isLeaf => children.isEmpty;

  /// 递归查找节点（按键）。
  MenuTreeNode? findByKey(String key) {
    if (this.key == key) return this;
    for (final c in children) {
      final r = c.findByKey(key);
      if (r != null) return r;
    }
    return null;
  }

  /// 递归遍历自身与全部后代（含自身）。
  void visit(void Function(MenuTreeNode node) visitor) {
    visitor(this);
    for (final c in children) {
      c.visit(visitor);
    }
  }
}
