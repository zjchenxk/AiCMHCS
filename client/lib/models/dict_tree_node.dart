import 'package:common/model.dart';

/// 数据字典管理树节点（按 PARENT_ID 递归，用于字典管理页左侧）。
/// 节点全部来自 BASE_DICT 数据（无虚拟根），顶级字典为多根列表。
class DictTreeNode {
  /// 构造函数：注入节点 ID 与原始字典数据。
  DictTreeNode({
    required this.id,
    required this.dict,
    List<DictTreeNode>? children,
    this.expanded = true,
  }) : children = children ?? [];

  /// 字典 ID（字符串形式的自增主键）。
  final String id;

  /// 节点携带的原始字典数据。
  final Dict dict;

  /// 显示名称（随保存后的重拉更新）。
  String get name => dict.dictName;

  /// 子节点列表。
  final List<DictTreeNode> children;

  /// 展开状态（重建树时保留）。
  bool expanded;

  /// 树内唯一键。
  String get key => 'dict:$id';

  bool get isLeaf => children.isEmpty;

  /// 递归查找节点（按键）。
  DictTreeNode? findByKey(String key) {
    if (this.key == key) return this;
    for (final c in children) {
      final r = c.findByKey(key);
      if (r != null) return r;
    }
    return null;
  }

  /// 递归遍历自身与全部后代（含自身）。
  void visit(void Function(DictTreeNode node) visitor) {
    visitor(this);
    for (final c in children) {
      c.visit(visitor);
    }
  }
}
