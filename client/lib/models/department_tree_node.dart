import 'package:common/model.dart';

/// 科室树节点类型：医院根节点（登录用户所属医院）、院区节点、科室节点。
enum DepartmentTreeNodeType { hospital, campus, department }

/// 科室管理树节点（医院 → 院区 → 科室 → 下级科室，用于科室设置页左侧）。
///
/// 医院节点为根，院区节点挂医院下（医院未设置院区时无此层），科室节点
/// 挂院区或医院下、下级科室经 PARENT_ID 递归挂上级科室下。
class DepartmentTreeNode {
  /// 构造函数：注入节点类型与各字段。
  DepartmentTreeNode({
    required this.type,
    required this.id,
    required this.name,
    this.campusId,
    this.department,
    List<DepartmentTreeNode>? children,
    this.expanded = true,
  }) : children = children ?? [];

  /// 节点类型（决定图标与可执行操作）。
  final DepartmentTreeNodeType type;

  /// 业务 ID（医院 ID / 院区 ID / 科室 ID，均为字符串）。
  final String id;

  /// 显示名称（可改名，随保存更新）。
  String name;

  /// 挂载归属的院区 ID（院区节点为其自身 ID，科室节点为所属院区 ID，
  /// 医院节点与直挂医院的科室为 null）。
  final String? campusId;

  /// 科室节点携带的原始数据（医院/院区节点为 null）。
  final Department? department;

  /// 子节点列表。
  final List<DepartmentTreeNode> children;

  /// 展开状态（重建树时保留）。
  bool expanded;

  /// 树内唯一键（院区与科室 ID 均为数字字符串可能撞号，组合类型区分）。
  String get key => '${type.name}:$id';

  bool get isLeaf => children.isEmpty;

  /// 递归查找节点（按组合键）。
  DepartmentTreeNode? findByKey(String key) {
    if (this.key == key) return this;
    for (final c in children) {
      final r = c.findByKey(key);
      if (r != null) return r;
    }
    return null;
  }

  /// 递归遍历自身与全部后代（含自身）。
  void visit(void Function(DepartmentTreeNode node) visitor) {
    visitor(this);
    for (final c in children) {
      c.visit(visitor);
    }
  }
}
