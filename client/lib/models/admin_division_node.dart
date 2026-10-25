import 'package:common/model.dart';

/// 行政区划树节点（懒加载：children 首次展开时才从后端拉取）。
///
/// hasChildren 由列表接口附带（决定是否显示展开箭头），
/// childrenLoaded 标记子级是否已加载，避免重复请求。
class AdminDivisionNode {
  /// 构造函数：注入区划代码、名称、上级代码、是否有下级。
  AdminDivisionNode({
    required this.code,
    required this.name,
    this.parentCode,
    this.hasChildren = false,
    this.expanded = false,
    List<AdminDivisionNode>? children,
  }) : children = children ?? [];

  /// 行政区划代码（主键，修改后经 [changeCode] 同步本地树）。
  String code;

  /// 行政区划名称（可改名，随保存更新）。
  String name;

  /// 上级行政区划代码（省级为 null；父节点改码时同步更新）。
  String? parentCode;

  /// 后端标记的是否存在下级（子级未加载时据此显示展开箭头）。
  bool hasChildren;

  /// 是否村/居委会级（12 位代码为最末级，不允许再添加下级）。
  bool get isVillageLevel => code.length >= 12;

  /// 是否展开。
  bool expanded;

  /// 子级是否已从后端加载（懒加载一次性标记）。
  bool childrenLoaded = false;

  /// 子节点列表（按代码升序维护）。
  final List<AdminDivisionNode> children;

  /// 从接口模型构建节点。
  factory AdminDivisionNode.fromDivision(AdminDivision division) {
    return AdminDivisionNode(
      code: division.code,
      name: division.name,
      parentCode: division.parentCode,
      hasChildren: division.hasChildren,
    );
  }

  /// 按代码升序插入子节点，保持与后端排序一致。
  void insertChild(AdminDivisionNode child) {
    var index = children.indexWhere((c) => c.code.compareTo(child.code) > 0);
    if (index < 0) index = children.length;
    children.insert(index, child);
    hasChildren = true;
    childrenLoaded = true;
  }

  /// 变更自身代码并同步直接子级的父引用（与服务端级联更新口径一致）。
  void changeCode(String newCode) {
    code = newCode;
    for (final c in children) {
      c.parentCode = newCode;
    }
  }

  /// 递归查找节点。
  AdminDivisionNode? find(String code) {
    if (this.code == code) return this;
    for (final c in children) {
      final r = c.find(code);
      if (r != null) return r;
    }
    return null;
  }
}
