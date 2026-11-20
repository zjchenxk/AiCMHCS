import 'package:client/main.dart';
import 'package:client/services/high_risk_factor_exclusion_service.dart';
import 'package:client/services/high_risk_factor_service.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 右侧信息表单模式（同高危因素管理）。
enum HighRiskFactorExclusionFormMode {
  /// 未选中任何互斥规则（表单区显示提示）。
  empty,

  /// 编辑选中的互斥规则。
  edit,

  /// 新增模式（表单清空待录）。
  create,
}

/// 高危因素互斥规则管理 ViewModel：左侧互斥规则列表，右侧信息表单
/// 三态（未选中 / 编辑选中 / 新增）。
///
/// 规则涉及的高危因素名称由本类按 ID 从本院高危因素字典解析（列表
/// 展示与下拉候选用同一份数据）；字典项被删除后按「已删除」占位展示，
/// 编辑时须重新选择。每次进入页面 loadData 都强制重拉规则、高危因素
/// 与当前登录角色的操作权限编码（/api/menu/operations，角色经会话
/// 服务端推导、切换角色后重进即生效），按钮级显隐经 canXxx getter 判定。
class HighRiskFactorExclusionManagementViewModel extends ChangeNotifier {
  /// 操作权限：新增互斥规则。
  static const String opCreate = '9910000001';

  /// 操作权限：修改互斥规则。
  static const String opUpdate = '9910000002';

  /// 操作权限：删除互斥规则。
  static const String opDelete = '9910000003';

  /// 构造函数：注入互斥规则、高危因素与菜单服务（缺省从服务定位器取，
  /// 测试可覆写；高危因素服务用于名称解析与下拉候选，菜单服务仅用于
  /// 拉取角色操作权限编码）。
  HighRiskFactorExclusionManagementViewModel({
    HighRiskFactorExclusionService? exclusionService,
    HighRiskFactorService? highRiskFactorService,
    MenuService? menuService,
  }) : _service = exclusionService ?? getIt<HighRiskFactorExclusionService>(),
       _factorService = highRiskFactorService ?? getIt<HighRiskFactorService>(),
       _menuService = menuService ?? getIt<MenuService>();

  final HighRiskFactorExclusionService _service;
  final HighRiskFactorService _factorService;
  final MenuService _menuService;

  final List<BaseHighRiskFactorExclusion> _exclusions = [];
  final List<BaseHighRiskFactor> _factors = [];
  final Set<String> _operationCodes = {};

  BaseHighRiskFactorExclusion? _selected;
  bool _creating = false;
  bool _loaded = false;
  bool _loading = false;
  bool _busy = false;
  String? _errorMsg;

  /// 本院全部互斥规则（按创建顺序）。
  List<BaseHighRiskFactorExclusion> get exclusions => _exclusions;

  /// 本院全部高危因素（下拉候选与名称解析数据源）。
  List<BaseHighRiskFactor> get factors => _factors;

  /// 下拉候选用高危因素：按高危颜色（绿/黄/橙/红/紫 → 未设置）分组
  /// 顺序排列，同色内按编码、名称升序，便于快速定位。
  List<BaseHighRiskFactor> get sortedFactors {
    final list = List<BaseHighRiskFactor>.of(_factors);
    int colorRank(String? color) {
      final name = color?.trim() ?? '';
      final index = BaseHighRiskFactor.riskColors.indexOf(name);
      return index < 0 ? BaseHighRiskFactor.riskColors.length : index;
    }

    list.sort((a, b) {
      final byColor = colorRank(a.riskColor).compareTo(colorRank(b.riskColor));
      if (byColor != 0) return byColor;
      final byCode = a.riskFactorCode.compareTo(b.riskFactorCode);
      if (byCode != 0) return byCode;
      return a.riskFactorName.compareTo(b.riskFactorName);
    });
    return list;
  }

  /// 当前选中的互斥规则（编辑态表单回填）。
  BaseHighRiskFactorExclusion? get selected => _selected;

  /// 右侧表单当前模式。
  HighRiskFactorExclusionFormMode get formMode {
    if (_creating) return HighRiskFactorExclusionFormMode.create;
    if (_selected == null) return HighRiskFactorExclusionFormMode.empty;
    return HighRiskFactorExclusionFormMode.edit;
  }

  /// 首屏加载中。
  bool get loading => _loading;

  /// 增删改操作进行中（防重复提交）。
  bool get busy => _busy;

  String? get errorMsg => _errorMsg;

  /// 已加载且本院无任何互斥规则（左侧显示空态引导）。
  bool get isEmpty => _loaded && _exclusions.isEmpty;

  /// 已加载且本院无任何高危因素（表单提示先维护字典）。
  bool get hasNoFactors => _loaded && _factors.isEmpty;

  // ---------------- 操作权限 ----------------

  /// 是否拥有「新增互斥规则」权限。
  bool get canCreate => _operationCodes.contains(opCreate);

  /// 是否拥有「修改互斥规则」权限（保存按钮与表单可编辑性依据）。
  bool get canUpdate => _operationCodes.contains(opUpdate);

  /// 是否拥有「删除互斥规则」权限。
  bool get canDelete => _operationCodes.contains(opDelete);

  // ---------------- 高危因素解析 ----------------

  /// 按 ID 查找本院高危因素（不存在返回 null）。
  BaseHighRiskFactor? factorById(String id) {
    for (final factor in _factors) {
      if (factor.id == id) return factor;
    }
    return null;
  }

  /// 规则一项高危因素的显示名（字典项已删除时给出占位文案）。
  String factorNameOf(String id) => factorById(id)?.riskFactorName ?? '（高危因素已删除）';

  /// 规则一项高危因素的高危颜色（字典项不存在时为 null）。
  String? factorColorOf(String id) => factorById(id)?.riskColor;

  /// 规则一项高危因素的编码（字典项不存在时为空串）。
  String factorCodeOf(String id) => factorById(id)?.riskFactorCode ?? '';

  /// 规则中是否存在本院已不存在的高危因素（编辑时须重新选择）。
  bool hasMissingFactors(BaseHighRiskFactorExclusion rule) => rule.riskFactorIds.any((id) => factorById(id) == null);

  // ---------------- 加载 ----------------

  /// 加载互斥规则、高危因素与操作权限（进入页面时调用）。每次调用都
  /// 强制重拉，选中项按 ID 刷新引用。
  Future<bool> loadData() async {
    _loading = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _refreshPermissions();
      await _refreshFactors();
      await _refreshExclusions();
      _loaded = true;
      return true;
    } catch (e, st) {
      LogHelper.error('client:HighRiskFactorExclusionManagementViewModel.loadData', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 拉取当前登录角色的操作权限编码（编码集整体覆盖；失败随 loadData
  /// 统一报错，编码集保持为空——按钮全部灰化）。
  Future<void> _refreshPermissions() async {
    final codes = await _menuService.queryOperationCodes();
    _operationCodes
      ..clear()
      ..addAll(codes);
  }

  /// 拉取本院全部高危因素（名称解析与下拉候选数据源）。
  Future<void> _refreshFactors() async {
    final factors = await _factorService.queryAll();
    _factors
      ..clear()
      ..addAll(factors);
  }

  /// 拉取本院全部互斥规则（选中项按 ID 刷新引用）。
  Future<void> _refreshExclusions() async {
    final exclusions = await _service.queryAll();
    _exclusions
      ..clear()
      ..addAll(exclusions);
    final selectedId = _selected?.id;
    if (selectedId != null) {
      _selected = _findById(selectedId);
    }
  }

  // ---------------- 交互 ----------------

  /// 选中左侧互斥规则（右侧切换为编辑态；无修改权限时表单只读）。
  void selectExclusion(BaseHighRiskFactorExclusion exclusion) {
    if (_selected?.id == exclusion.id && !_creating) return;
    _creating = false;
    _selected = exclusion;
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

  // ---------------- 增删改 ----------------

  /// 新增互斥规则，成功后整表重拉、退出新增态并选中新规则。
  Future<bool> createExclusion({
    required String firstRiskFactorId,
    required String secondRiskFactorId,
    String? thirdRiskFactorId,
  }) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final created = await _service.create(
        firstRiskFactorId: firstRiskFactorId,
        secondRiskFactorId: secondRiskFactorId,
        thirdRiskFactorId: thirdRiskFactorId,
      );
      await _refreshExclusions();
      _creating = false;
      _selected = _findById(created.id);
      return true;
    } catch (e, st) {
      LogHelper.error('client:HighRiskFactorExclusionManagementViewModel.createExclusion', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 修改互斥规则（changes 键同后端契约），成功后整表重拉。
  Future<bool> updateExclusion(String id, Map<String, Object?> changes) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _service.update(id, changes);
      await _refreshExclusions();
      _selected = _findById(id);
      return true;
    } catch (e, st) {
      LogHelper.error('client:HighRiskFactorExclusionManagementViewModel.updateExclusion', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 删除互斥规则，成功后整表重拉；删除选中项时回退空态。
  Future<bool> deleteExclusion(BaseHighRiskFactorExclusion exclusion) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _service.delete(exclusion.id);
      if (_selected?.id == exclusion.id) {
        _selected = null;
        _creating = false;
      }
      await _refreshExclusions();
      return true;
    } catch (e, st) {
      LogHelper.error('client:HighRiskFactorExclusionManagementViewModel.deleteExclusion', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ---------------- 通用 ----------------

  /// 按 ID 在已加载列表中查找（不存在返回 null）。
  BaseHighRiskFactorExclusion? _findById(String id) {
    for (final exclusion in _exclusions) {
      if (exclusion.id == id) return exclusion;
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
