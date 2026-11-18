import 'package:client/main.dart';
import 'package:client/models/high_risk_factor_tree_node.dart';
import 'package:client/services/high_risk_factor_service.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:client/utils/risk_color.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 右侧信息表单模式（同科室/菜单管理）。
enum HighRiskFactorFormMode {
  /// 未选中任何高危因素（表单区显示提示）。
  empty,

  /// 编辑选中的高危因素。
  edit,

  /// 新增模式（表单清空待录）。
  create,
}

/// 高危因素管理 ViewModel：左侧按高危颜色分组的「大类→小类→名称」
/// 树，右侧信息表单三态（未选中 / 编辑选中 / 新增）。
///
/// 树数据来自 /api/highRiskFactor/query 的扁平列表、由本类按
/// RISK_COLOR 分组并把「大类→小类→名称」组织为树：大类为空时因素
/// 直接置颜色组顶层，小类为空时因素直挂大类下；各层按
/// RISK_FACTOR_CODE 升序排列（大类/小类取其下因素的最小编码参与排序），
/// 保证组内整体呈现编码从小到大。每次进入页面 loadData 都强制重拉——
/// 保证切回本页时数据一致，同时重拉当前登录角色的操作权限编码
/// （/api/menu/operations，角色经会话服务端推导、切换角色后重进即
/// 生效），按钮级显隐经 canXxx getter 判定。
class HighRiskFactorManagementViewModel extends ChangeNotifier {
  /// 操作权限：新增高危因素。
  static const String opCreate = '9909000001';

  /// 操作权限：修改高危因素。
  static const String opUpdate = '9909000002';

  /// 操作权限：删除高危因素。
  static const String opDelete = '9909000003';

  /// 构造函数：注入高危因素与菜单服务（缺省从服务定位器取，测试可覆写；
  /// 菜单服务仅用于拉取角色操作权限编码）。
  HighRiskFactorManagementViewModel({
    HighRiskFactorService? highRiskFactorService,
    MenuService? menuService,
  }) : _service = highRiskFactorService ?? getIt<HighRiskFactorService>(),
       _menuService = menuService ?? getIt<MenuService>();

  final HighRiskFactorService _service;
  final MenuService _menuService;

  final List<BaseHighRiskFactor> _factors = [];
  final List<HighRiskFactorGroup> _groups = [];
  final Set<String> _operationCodes = {};

  /// 已折叠的大类/小类节点 key（默认全部展开）。
  final Set<String> _collapsed = {};

  BaseHighRiskFactor? _selected;
  bool _creating = false;
  bool _loaded = false;
  bool _loading = false;
  bool _busy = false;
  String? _errorMsg;

  /// 按颜色分组后的树（组序：绿/黄/橙/红/紫 → 其他颜色 → 未设置）。
  List<HighRiskFactorGroup> get groups => _groups;

  /// 当前选中的高危因素（编辑态表单回填）。
  BaseHighRiskFactor? get selected => _selected;

  /// 右侧表单当前模式。
  HighRiskFactorFormMode get formMode {
    if (_creating) return HighRiskFactorFormMode.create;
    if (_selected == null) return HighRiskFactorFormMode.empty;
    return HighRiskFactorFormMode.edit;
  }

  /// 首屏加载中。
  bool get loading => _loading;

  /// 增删改操作进行中（防重复提交）。
  bool get busy => _busy;

  String? get errorMsg => _errorMsg;

  /// 已加载且本院无任何高危因素（左侧显示空态引导）。
  bool get isEmpty => _loaded && _factors.isEmpty;

  // ---------------- 操作权限 ----------------

  /// 是否拥有「新增高危因素」权限（新增按钮显隐依据）。
  bool get canCreate => _operationCodes.contains(opCreate);

  /// 是否拥有「修改高危因素」权限（保存按钮与表单可编辑性依据）。
  bool get canUpdate => _operationCodes.contains(opUpdate);

  /// 是否拥有「删除高危因素」权限（删除按钮显隐依据）。
  bool get canDelete => _operationCodes.contains(opDelete);

  // ---------------- 加载 ----------------

  /// 加载全部高危因素并组树（进入页面时调用）。每次调用都强制重拉，
  /// 展开与选中状态尽量保留。
  Future<bool> loadData() async {
    _loading = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _refreshPermissions();
      await _refreshFactors();
      _loaded = true;
      return true;
    } catch (e, st) {
      LogHelper.error('client:HighRiskFactorManagementViewModel.loadData', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 拉取当前登录角色的操作权限编码（编码集整体覆盖；失败随 loadData
  /// 统一报错，编码集保持为空——按钮全隐藏）。
  Future<void> _refreshPermissions() async {
    final codes = await _menuService.queryOperationCodes();
    _operationCodes
      ..clear()
      ..addAll(codes);
  }

  /// 拉取全部高危因素并重建颜色分组树（选中项按 ID 刷新引用）。
  Future<void> _refreshFactors() async {
    final factors = await _service.queryAll();
    _factors
      ..clear()
      ..addAll(factors);
    final selectedId = _selected?.id;
    _rebuildGroups();
    if (selectedId != null) {
      _selected = _findById(selectedId);
    }
  }

  /// 按颜色分组并构建「大类→小类→名称」树。
  ///
  /// 颜色优先级：[RiskColorPalette.names] 固定顺序 → 其他非空颜色
  /// （按名称）→ 未设置（null 最后）。组内：大类为空的因素置顶层；
  /// 大类非空时建大类节点，小类为空的因素直挂大类下，否则建小类
  /// 节点；各层按名称排序、同名因素再按编码排序。
  void _rebuildGroups() {
    final byColor = <String?, List<BaseHighRiskFactor>>{};
    for (final factor in _factors) {
      final color = factor.riskColor?.trim() ?? '';
      final key = color.isEmpty ? null : color;
      byColor.putIfAbsent(key, () => []).add(factor);
    }

    final colorOrder = <String?>[
      ...RiskColorPalette.names.where(byColor.containsKey),
      ...byColor.keys.where((c) => c != null && !RiskColorPalette.names.contains(c)).toList()..sort(),
      if (byColor.containsKey(null)) null,
    ];

    _groups
      ..clear()
      ..addAll(
        colorOrder.map(
          (color) => HighRiskFactorGroup(colorName: color, roots: _buildColorRoots(color, byColor[color] ?? const [])),
        ),
      );
  }

  /// 构建单个颜色组内的树（根为大类节点、无大类但有子类的小类节点、
  /// 以及大类/小类均为空的散落因素，按名称混排）。
  List<HighRiskFactorTreeNode> _buildColorRoots(String? color, List<BaseHighRiskFactor> factors) {
    final roots = <HighRiskFactorTreeNode>[];
    final byCategory = <String, List<BaseHighRiskFactor>>{};
    final rootSubcategories = <String, List<BaseHighRiskFactor>>{};
    for (final factor in factors) {
      final category = factor.riskFactorCategory?.trim() ?? '';
      final subcategory = factor.riskFactorSubcategory?.trim() ?? '';
      if (category.isEmpty) {
        // 大类为空：小类也为空时名称置顶层，仅小类非空时以小类节点置顶层
        if (subcategory.isEmpty) {
          roots.add(_factorNode(factor));
        } else {
          rootSubcategories.putIfAbsent(subcategory, () => []).add(factor);
        }
      } else {
        byCategory.putIfAbsent(category, () => []).add(factor);
      }
    }

    // 无大类、仅小类的因素：小类节点直接置颜色组顶层
    for (final subcategory in rootSubcategories.keys) {
      roots.add(
        _subcategoryNode(
          color: color,
          category: '',
          subcategory: subcategory,
          factors: rootSubcategories[subcategory]!,
        ),
      );
    }

    for (final category in byCategory.keys) {
      final categoryKey = 'cat:${color ?? ''}|$category';
      final categoryChildren = <HighRiskFactorTreeNode>[];
      final bySubcategory = <String, List<BaseHighRiskFactor>>{};
      for (final factor in byCategory[category]!) {
        final subcategory = factor.riskFactorSubcategory?.trim() ?? '';
        if (subcategory.isEmpty) {
          categoryChildren.add(_factorNode(factor));
        } else {
          bySubcategory.putIfAbsent(subcategory, () => []).add(factor);
        }
      }
      for (final subcategory in bySubcategory.keys) {
        categoryChildren.add(
          _subcategoryNode(
            color: color,
            category: category,
            subcategory: subcategory,
            factors: bySubcategory[subcategory]!,
          ),
        );
      }
      categoryChildren.sort(_compareNodes);
      roots.add(
        HighRiskFactorTreeNode(
          key: categoryKey,
          name: category,
          kind: HighRiskFactorNodeKind.category,
          children: categoryChildren,
          expanded: !_collapsed.contains(categoryKey),
        ),
      );
    }

    roots.sort(_compareNodes);
    return roots;
  }

  /// 小类节点（按颜色+大类+小类名生成稳定 key，重建时保留展开状态）。
  HighRiskFactorTreeNode _subcategoryNode({
    required String? color,
    required String category,
    required String subcategory,
    required List<BaseHighRiskFactor> factors,
  }) {
    final key = 'sub:${color ?? ''}|$category|$subcategory';
    final leaves = factors.map(_factorNode).toList()..sort(_compareNodes);
    return HighRiskFactorTreeNode(
      key: key,
      name: subcategory,
      kind: HighRiskFactorNodeKind.subcategory,
      children: leaves,
      expanded: !_collapsed.contains(key),
    );
  }

  /// 因素叶子节点（名称 + 原始字典行）。
  HighRiskFactorTreeNode _factorNode(BaseHighRiskFactor factor) => HighRiskFactorTreeNode(
    key: 'factor:${factor.id}',
    name: factor.riskFactorName,
    kind: HighRiskFactorNodeKind.factor,
    factor: factor,
  );

  /// 节点排序：因素按 RISK_FACTOR_CODE 升序；大类/小类按其后代因素
  /// 的最小编码升序（无编码时依次回退名称、节点类型）。
  int _compareNodes(HighRiskFactorTreeNode a, HighRiskFactorTreeNode b) {
    final byCode = a.sortCode.compareTo(b.sortCode);
    if (byCode != 0) return byCode;
    final byName = a.name.compareTo(b.name);
    if (byName != 0) return byName;
    return a.kind.index.compareTo(b.kind.index);
  }

  // ---------------- 交互 ----------------

  /// 选中左侧高危因素（右侧切换为编辑态；无修改权限时表单只读）。
  void selectFactor(BaseHighRiskFactor factor) {
    if (_selected?.id == factor.id && !_creating) return;
    _creating = false;
    _selected = factor;
    notifyListeners();
  }

  /// 进入新增模式（右侧表单清空；取消后回到原选中项编辑态）。
  void startCreate() {
    if (_creating) return;
    _creating = true;
    notifyListeners();
  }

  /// 取消新增，回到原选中项编辑态（无选中则回到空态）。
  void cancelCreate() {
    if (!_creating) return;
    _creating = false;
    notifyListeners();
  }

  /// 切换大类/小类节点展开折叠（因素叶子不响应）。
  void toggleNode(HighRiskFactorTreeNode node) {
    if (node.isLeaf) return;
    node.expanded = !node.expanded;
    if (node.expanded) {
      _collapsed.remove(node.key);
    } else {
      _collapsed.add(node.key);
    }
    notifyListeners();
  }

  // ---------------- 增删改 ----------------

  /// 新增高危因素，成功后整表重拉、退出新增态并选中新因素。
  Future<bool> createFactor({
    required String riskFactorCode,
    required String riskFactorName,
    String? riskFactorCategory,
    String? riskFactorSubcategory,
    String? riskColor,
    String? riskLevel,
    String? riskScore,
  }) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final created = await _service.create(
        riskFactorCode: riskFactorCode,
        riskFactorName: riskFactorName,
        riskFactorCategory: riskFactorCategory,
        riskFactorSubcategory: riskFactorSubcategory,
        riskColor: riskColor,
        riskLevel: riskLevel,
        riskScore: riskScore,
      );
      await _refreshFactors();
      _creating = false;
      _selected = _findById(created.id);
      return true;
    } catch (e, st) {
      LogHelper.error('client:HighRiskFactorManagementViewModel.createFactor', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 修改高危因素（changes 键同后端契约），成功后整表重拉。
  Future<bool> updateFactor(String id, Map<String, Object?> changes) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _service.update(id, changes);
      await _refreshFactors();
      _selected = _findById(id);
      return true;
    } catch (e, st) {
      LogHelper.error('client:HighRiskFactorManagementViewModel.updateFactor', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 删除高危因素，成功后整表重拉；删除选中项时回退空态。
  Future<bool> deleteFactor(BaseHighRiskFactor factor) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _service.delete(factor.id);
      if (_selected?.id == factor.id) {
        _selected = null;
        _creating = false;
      }
      await _refreshFactors();
      return true;
    } catch (e, st) {
      LogHelper.error('client:HighRiskFactorManagementViewModel.deleteFactor', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ---------------- 通用 ----------------

  /// 按 ID 在已加载列表中查找（不存在返回 null）。
  BaseHighRiskFactor? _findById(String id) {
    for (final factor in _factors) {
      if (factor.id == id) return factor;
    }
    return null;
  }

  /// 剥离异常前缀（Exception(: ...)），取用户可读信息。
  String _messageOf(Object e) => e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');

  void clearError() {
    _errorMsg = null;
    notifyListeners();
  }
}
