import 'package:common/model.dart';

/// 高危因素树节点类型：大类 / 小类 / 因素（叶子）。
enum HighRiskFactorNodeKind {
  /// 大类（RISK_FACTOR_CATEGORY）。
  category,

  /// 小类（RISK_FACTOR_SUBCATEGORY）。
  subcategory,

  /// 高危因素名称（叶子，携带原始字典行）。
  factor,
}

/// 高危因素管理树节点（左侧按「颜色 → 大类 → 小类 → 名称」组织）。
///
/// 大类/小类节点为展示层虚拟节点（无数据库实体），因素节点携带
/// BASE_HIGH_RISK_FACTOR 行；大类/小类为空时名称直接上提（无大类
/// 置颜色组顶层，无小类直挂大类下）。节点 key 稳定用于重建时保留
/// 展开状态。
class HighRiskFactorTreeNode {
  /// 构造函数：注入节点 key、显示名、类型与子节点。
  HighRiskFactorTreeNode({
    required this.key,
    required this.name,
    required this.kind,
    this.factor,
    List<HighRiskFactorTreeNode>? children,
    this.expanded = true,
  }) : children = children ?? [];

  /// 树内唯一键（`cat:` / `sub:` / `factor:` 前缀）。
  final String key;

  /// 显示名称（大类/小类名，或因素名称）。
  final String name;

  /// 节点类型。
  final HighRiskFactorNodeKind kind;

  /// 因素叶子携带的字典行（大类/小类节点为 null）。
  final BaseHighRiskFactor? factor;

  /// 子节点列表（因素叶子为空）。
  final List<HighRiskFactorTreeNode> children;

  /// 展开状态（重建树时按 key 恢复）。
  bool expanded;

  /// 是否叶子（因素节点）。
  bool get isLeaf => kind == HighRiskFactorNodeKind.factor;

  /// 本节点下因素数量（叶子为 1，分支为后代求和）。
  int get factorCount {
    if (isLeaf) return 1;
    var count = 0;
    for (final child in children) {
      count += child.factorCount;
    }
    return count;
  }

  /// 排序编码：因素为自身 RISK_FACTOR_CODE；大类/小类取后代因素的最小
  /// 编码（无后代返回空串）。同层节点按本值升序排列，使树形展示整体
  /// 呈现高危因素编码从小到大。
  String get sortCode {
    if (isLeaf) return factor?.riskFactorCode ?? '';
    String? min;
    for (final child in children) {
      final code = child.sortCode;
      if (code.isEmpty) continue;
      if (min == null || code.compareTo(min) < 0) min = code;
    }
    return min ?? '';
  }

  /// 递归查找节点（按 key）。
  HighRiskFactorTreeNode? findByKey(String key) {
    if (this.key == key) return this;
    for (final child in children) {
      final hit = child.findByKey(key);
      if (hit != null) return hit;
    }
    return null;
  }
}

/// 单个高危颜色分组（颜色语义与组内树）。
class HighRiskFactorGroup {
  /// 构造函数：注入颜色名称（null 为未设置颜色）与组内根节点。
  HighRiskFactorGroup({required this.colorName, required this.roots});

  /// 高危颜色名称（中文五色；null 表示未设置）。
  final String? colorName;

  /// 组内根节点（无大类因素与大类节点混排，按名称排序）。
  final List<HighRiskFactorTreeNode> roots;

  /// 组内因素总数。
  int get factorCount {
    var count = 0;
    for (final root in roots) {
      count += root.factorCount;
    }
    return count;
  }
}
