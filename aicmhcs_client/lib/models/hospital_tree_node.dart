/// 医院树节点（支持上下级，用于医联体）
class HospitalTreeNode {
  final String id;
  final String name;
  final String? parentId; // 为 null 表示根节点（顶级医院）
  final List<HospitalTreeNode> children;
  bool expanded;

  HospitalTreeNode({
    required this.id,
    required this.name,
    this.parentId,
    List<HospitalTreeNode>? children,
    this.expanded = true,
  }) : children = children ?? [];

  bool get isLeaf => children.isEmpty;

  /// 深拷贝（刷新树时使用，避免直接修改旧引用）
  HospitalTreeNode copy() {
    final node = HospitalTreeNode(
      id: id,
      name: name,
      parentId: parentId,
      expanded: expanded,
    );
    for (final c in children) {
      node.children.add(c.copy());
    }
    return node;
  }

  /// 递归查找节点
  HospitalTreeNode? find(String id) {
    if (this.id == id) return this;
    for (final c in children) {
      final r = c.find(id);
      if (r != null) return r;
    }
    return null;
  }
}
