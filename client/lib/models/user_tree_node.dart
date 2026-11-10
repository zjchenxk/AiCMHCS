import 'package:common/model.dart';

/// 用户管理树节点类型：科室节点（含「未分配科室」虚拟节点）、用户节点。
enum UserTreeNodeType { department, user }

/// 用户管理树节点（科室 → 下级科室 → 用户，用于用户管理页左侧）。
///
/// 科室节点经 PARENT_ID 递归挂下级，用户节点挂其 DEPT_ID 对应科室下；
/// DEPT_ID 为空或科室已删除的用户统一收入「未分配科室」虚拟节点
///（department 为 null，仅供查看，不可在其下新增）。
class UserTreeNode {
  /// 构造函数：注入节点类型与各字段。
  UserTreeNode({
    required this.type,
    required this.id,
    required this.name,
    this.department,
    this.user,
    List<UserTreeNode>? children,
    this.expanded = true,
  }) : children = children ?? [];

  /// 节点类型（决定图标与可执行操作）。
  final UserTreeNodeType type;

  /// 业务 ID（科室 ID / 用户 ID，均为字符串；「未分配科室」虚拟节点为
  /// 固定标识 __unassigned）。
  final String id;

  /// 显示名称。
  final String name;

  /// 科室节点携带的原始数据（「未分配科室」虚拟节点与用户节点为
  /// null；在其下新增用户要求 department 非 null）。
  final Department? department;

  /// 用户节点携带的原始数据（科室节点为 null）。
  final User? user;

  /// 子节点列表。
  final List<UserTreeNode> children;

  /// 展开状态（重建树时保留）。
  bool expanded;

  /// 树内唯一键（科室与用户 ID 均为数字字符串可能撞号，组合类型区分）。
  String get key => '${type.name}:$id';

  bool get isLeaf => children.isEmpty;

  /// 递归查找节点（按组合键）。
  UserTreeNode? findByKey(String key) {
    if (this.key == key) return this;
    for (final c in children) {
      final r = c.findByKey(key);
      if (r != null) return r;
    }
    return null;
  }

  /// 递归遍历自身与全部后代（含自身）。
  void visit(void Function(UserTreeNode node) visitor) {
    visitor(this);
    for (final c in children) {
      c.visit(visitor);
    }
  }
}
