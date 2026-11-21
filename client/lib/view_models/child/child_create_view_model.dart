import 'package:client/main.dart';
import 'package:client/utils/captured_photo.dart';
import 'package:client/utils/relative_time.dart';
import 'package:client/services/admin_divisions_service.dart';
import 'package:client/services/child_service.dart';
import 'package:client/services/high_risk_factor_exclusion_service.dart';
import 'package:client/services/high_risk_factor_service.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/utils/high_risk_auto_screening.dart';
import 'package:client/utils/log_helper.dart';
import 'package:common/model.dart';
import 'package:flutter/foundation.dart';

/// 儿童建档表单模式：empty-未载入档案（仅可新增）、browse-浏览已载入
/// 档案、create-新增录入、edit-修改已载入档案。
enum ChildFormMode { empty, browse, create, edit }

/// 儿童建档视图模型：操作权限（按钮灰化）、整档装载与增删改流转、
/// 新增/修改/删除流转、监护人本地工作列表（随整单保存）、高危因素
/// 勾选集合（五色卡片树随整单保存）、五级居住地址级联（基本信息表单
/// 用）。
///
/// 数据流：主界面顶部搜索选定「当前儿童」后，建档页经 [selectChild]
/// 自动载入整档进入浏览态；【新增】/【修改】进入录入态，三个 Tab 表单
/// 各自持控制器，【保存】时由页面收集表单数据经 [save] 整单提交；
/// 监护人行的增删改仅操作本地列表（不做权限控制），随整单保存一并
/// 入库；高危因素勾选集合亦随整单保存（绿色「无高危因素」与其余四色
/// 互斥；同一互斥规则内的项目只能选其一，勾选时自动清除冲突项）。扩展
/// 信息触发字段变更后经 [applyHighRiskAutoScreening] 自动筛查勾选/清除
/// 对应高危因素（见 HighRiskAutoScreening）。
class ChildCreateViewModel extends ChangeNotifier {
  /// 构造函数：可选注入服务（缺省经服务定位器取，便于测试覆写）。
  ChildCreateViewModel({
    ChildService? childService,
    MenuService? menuService,
    AdminDivisionsService? adminDivisionsService,
    HighRiskFactorService? highRiskFactorService,
    HighRiskFactorExclusionService? highRiskFactorExclusionService,
  }) : _childService = childService ?? getIt<ChildService>(),
       _menuService = menuService ?? getIt<MenuService>(),
       _divisionsService = adminDivisionsService ?? getIt<AdminDivisionsService>(),
       _highRiskFactorService = highRiskFactorService ?? getIt<HighRiskFactorService>(),
       _highRiskFactorExclusionService = highRiskFactorExclusionService ?? getIt<HighRiskFactorExclusionService>();

  final ChildService _childService;

  final MenuService _menuService;

  final AdminDivisionsService _divisionsService;

  final HighRiskFactorService _highRiskFactorService;

  final HighRiskFactorExclusionService _highRiskFactorExclusionService;

  // ---------------- 操作权限（SYS_MENU 操作项 ITEM_CODE） ----------------

  /// 新增操作权限码。
  static const String opCreate = '0201000001';

  /// 修改操作权限码。
  static const String opUpdate = '0201000002';

  /// 保存操作权限码。
  static const String opSave = '0201000003';

  /// 删除操作权限码。
  static const String opDelete = '0201000004';

  /// 当前角色已授权的操作权限码集合（未加载/失败时为空集，按钮全灰化——
  /// 权限未知不放行）。
  final Set<String> _operationCodes = {};

  /// 是否拥有新增操作权限。
  bool get canCreate => _operationCodes.contains(opCreate);

  /// 是否拥有修改操作权限。
  bool get canUpdate => _operationCodes.contains(opUpdate);

  /// 是否拥有保存操作权限。
  bool get canSave => _operationCodes.contains(opSave);

  /// 是否拥有删除操作权限。
  bool get canDelete => _operationCodes.contains(opDelete);

  /// 拉取当前角色操作权限码（进页时调用）。
  Future<void> loadPermissions() async {
    try {
      final codes = await _menuService.queryOperationCodes();
      _operationCodes
        ..clear()
        ..addAll(codes);
    } catch (e, st) {
      LogHelper.error('client:ChildCreateViewModel.loadPermissions', e, st);
      _operationCodes.clear();
    }
    notifyListeners();
  }

  // ---------------- 模式与档案状态 ----------------

  ChildFormMode _mode = ChildFormMode.empty;

  /// 当前表单模式。
  ChildFormMode get mode => _mode;

  /// 是否浏览态（已载入档案、未编辑）。
  bool get browsing => _mode == ChildFormMode.browse;

  /// 是否新增录入态。
  bool get creating => _mode == ChildFormMode.create;

  /// 是否修改录入态。
  bool get editing => _mode == ChildFormMode.edit;

  bool _loading = false;

  /// 首屏/载档中。
  bool get loading => _loading;

  int _dataRevision = 0;

  /// 档案数据版本：整档（重）载入或保存成功后递增。页面以「版本:儿童
  /// ID」作表单键身份——进入/退出修改态不递增（表单 State 与已回显
  /// 输入保留，仅切换可编辑性），载入/取消/保存后递增（表单以最新数据
  /// 重建），切修改态因此无需销毁重建全部表单。
  int get dataRevision => _dataRevision;

  bool _busy = false;

  /// 保存/删除等写操作进行中（防重复提交）。
  bool get busy => _busy;

  String? _errorMsg;

  /// 最近一次操作的错误信息（页面展示后调 [clearError] 防重复弹出）。
  String? get errorMsg => _errorMsg;

  /// 清空错误信息。
  void clearError() {
    _errorMsg = null;
    notifyListeners();
  }

  ChildInfo? _child;

  /// 当前载入/编辑中的儿童基本信息（新增录入态为 null）。
  ChildInfo? get child => _child;

  ChildExtInfo? _ext;

  /// 当前载入/编辑中的儿童扩展信息。
  ChildExtInfo? get ext => _ext;

  /// 当前儿童档案 ID（未载入为空串）。
  String get currentChildId => _child?.id ?? '';

  ChildPhoto? _latestPhoto;

  /// 库内最近一次拍照记录（浏览/修改态回显头像与相对时间）。
  ChildPhoto? get latestPhoto => _latestPhoto;

  CapturedPhoto? _pendingPhoto;

  /// 本次拍照的待保存结果（拍照对话框确定后写入，随【保存】一并入库；
  /// 显示优先级高于 [latestPhoto]）。
  CapturedPhoto? get pendingPhoto => _pendingPhoto;

  /// 界面显示用头像 base64：本次拍照优先，否则取库内最近记录。
  String? get displayAvatarBase64 => _pendingPhoto?.avatarBase64 ?? _latestPhoto?.avatarBase64;

  /// 界面显示用拍照时间文案：本次拍照为「刚刚拍摄」，库内记录为相对
  /// 时间（{d}天前/{m}月前/{y}年{m}月前），无照片为 null。
  String? get displayPhotoTimeLabel {
    if (_pendingPhoto != null) return '刚刚拍摄';
    final createTime = _latestPhoto?.createTime;
    if (createTime == null || createTime.isEmpty) return null;
    final parsed = DateTime.tryParse(createTime);
    return parsed == null ? null : photoAgeLabel(parsed);
  }

  String _messageOf(Object e) => e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');

  /// 重复建档检查：按「姓名+性别+出生日期」查本院已有档案（修改态自动
  /// 排除自身）。失败时返回空列表并记日志（查重是保存前的辅助确认，
  /// 查询异常不应阻断保存流程）。
  Future<List<ChildInfo>> checkDuplicate(ChildInfo child) async {
    try {
      return await _childService.duplicateCheck(
        name: child.name,
        sex: child.sex,
        birthDate: child.birthDate,
        excludeId: editing ? _child?.id : null,
      );
    } catch (e, st) {
      LogHelper.error('client:ChildCreateViewModel.checkDuplicate', e, st);
      return const [];
    }
  }

  /// 载入库内最近一次拍照记录（进浏览态/保存成功后刷新）。
  Future<void> loadLatestPhoto() async {
    final id = currentChildId;
    if (id.isEmpty) {
      _latestPhoto = null;
      notifyListeners();
      return;
    }
    try {
      _latestPhoto = await _childService.latestPhoto(id);
    } catch (e, st) {
      LogHelper.error('client:ChildCreateViewModel.loadLatestPhoto', e, st);
      _latestPhoto = null;
    }
    notifyListeners();
  }

  /// 记录拍照对话框的确定结果（待保存）。
  void setPendingPhoto(CapturedPhoto photo) {
    _pendingPhoto = photo;
    notifyListeners();
  }

  /// 清除本次拍照的待保存结果（未入库的儿童无库记录可移除）。
  void clearPendingPhoto() {
    if (_pendingPhoto == null) return;
    _pendingPhoto = null;
    notifyListeners();
  }

  /// 移除当前儿童当天的全部拍照记录（恢复显示历史头像或空白）。
  ///returns: 是否移除成功
  Future<bool> removeTodayPhoto() async {
    final id = currentChildId;
    if (id.isEmpty) return false;
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final (removed, latest) = await _childService.removeTodayPhotos(id);
      _latestPhoto = latest;
      _pendingPhoto = null;
      return true;
    } catch (e, st) {
      LogHelper.error('client:ChildCreateViewModel.removeTodayPhoto', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 载入指定儿童整档并进入浏览态（含居住地址级联回显）。
  Future<bool> selectChild(String id) async {
    _loading = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final (child, ext, guardians) = await _childService.load(id);
      _child = child;
      _ext = ext;
      _guardians = guardians;
      _mode = ChildFormMode.browse;
      _pendingPhoto = null;
      await initAddressFromChild(child);
      await loadLatestPhoto();
      await loadHighRiskData();
      // 档案数据版本递增：页面表单键身份随之变化，表单以最新数据重建
      // （同一儿童重载如取消修改也会换键，避免残留未保存输入）
      _dataRevision++;
      return true;
    } catch (e, st) {
      LogHelper.error('client:ChildCreateViewModel.selectChild', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 进入新增录入态（清空全部编辑数据，建档时间由表单默认当前时间）。
  Future<void> startCreate() async {
    _child = null;
    _ext = null;
    _guardians = [];
    _latestPhoto = null;
    _pendingPhoto = null;
    _checkedHighRiskIds.clear();
    _autoScreenedIds.clear();
    _lastScreeningTargetNames.clear();
    _mode = ChildFormMode.create;
    // 新增态默认勾选绿色卡片【无母亲及胎儿、新生儿的高危因素】
    // （字典未加载时为空操作，后续 loadHighRiskData 会再兜底一次）
    _applyDefaultHighRiskSelection();
    clearAdminDivisions();
    await getProvinces();
    notifyListeners();
  }

  /// 进入修改录入态（保留已载入档案数据，表单可编辑；不递增数据版本
  /// ——页面表单键身份不变，表单 State 与已回显输入保留，仅各表单经
  /// watch 切换可编辑性）。
  void startEdit() {
    if (_child == null) return;
    _mode = ChildFormMode.edit;
    notifyListeners();
  }

  /// 取消录入：已载入档案时重载整档回到浏览态（丢弃未保存修改），
  /// 否则回到空态。
  Future<void> cancelEdit() async {
    final id = _child?.id ?? '';
    if (id.isEmpty) {
      _mode = ChildFormMode.empty;
      _child = null;
      _ext = null;
      _guardians = [];
      _latestPhoto = null;
      _pendingPhoto = null;
      notifyListeners();
      return;
    }
    await selectChild(id);
  }

  /// 整单保存：新增录入态走新增、修改录入态走修改，成功后以入库结果
  /// 进入浏览态。
  ///
  ///param child: 基本信息（基本 Tab 收集）
  ///param ext: 扩展信息（扩展 Tab 收集，null 表示清空扩展信息）
  ///param guardians: 监护人列表（监护人 Tab 本地工作列表）
  ///returns: true 表示保存成功
  Future<bool> save({required ChildInfo child, ChildExtInfo? ext, List<ChildGuardianInfo>? guardians}) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final guardianList = guardians ?? _guardians;
      final pending = _pendingPhoto;
      final highRiskFactors = _buildHighRiskSelections();
      final ChildArchive archive;
      if (_mode == ChildFormMode.edit) {
        archive = await _childService.update(
          id: _child!.id,
          child: child,
          ext: ext,
          guardians: guardianList,
          photoBase64: pending?.photoBase64,
          avatarBase64: pending?.avatarBase64,
          highRiskFactors: highRiskFactors,
        );
      } else {
        archive = await _childService.create(
          child: child,
          ext: ext,
          guardians: guardianList,
          photoBase64: pending?.photoBase64,
          avatarBase64: pending?.avatarBase64,
          highRiskFactors: highRiskFactors,
        );
      }
      _child = archive.$1;
      _ext = archive.$2;
      _guardians = archive.$3;
      _mode = ChildFormMode.browse;
      _pendingPhoto = null;
      _checkedHighRiskIds.clear();
      await loadLatestPhoto();
      await loadHighRiskData();
      _dataRevision++;
      return true;
    } catch (e, st) {
      LogHelper.error('client:ChildCreateViewModel.save', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 删除当前已载入的儿童档案（连带扩展信息与监护人），成功后回到
  /// 空态。
  Future<bool> deleteCurrent() async {
    final id = _child?.id ?? '';
    if (id.isEmpty) return false;
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _childService.delete(id);
      _child = null;
      _ext = null;
      _guardians = [];
      _latestPhoto = null;
      _pendingPhoto = null;
      _mode = ChildFormMode.empty;
      return true;
    } catch (e, st) {
      LogHelper.error('client:ChildCreateViewModel.deleteCurrent', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ---------------- 监护人本地工作列表（随整单保存） ----------------

  List<ChildGuardianInfo> _guardians = [];

  /// 当前编辑中的监护人列表（行的增删改不做权限控制、不直接落库）。
  List<ChildGuardianInfo> get guardians => List.unmodifiable(_guardians);

  /// 新增或更新监护人到工作列表。
  ///
  ///param guardian: 监护人数据
  ///param index: 替换的工作列表行下标（修改已载入行/本地未入库行时传
  /// 其下标；null 时按 id 匹配替换，匹配不到即追加为新行）
  void addOrUpdateGuardian(ChildGuardianInfo guardian, {int? index}) {
    if (index != null && index >= 0 && index < _guardians.length) {
      _guardians[index] = guardian;
    } else {
      final byId = guardian.id == null ? -1 : _guardians.indexWhere((g) => g.id == guardian.id);
      if (byId >= 0) {
        _guardians[byId] = guardian;
      } else {
        _guardians.add(guardian);
      }
    }
    notifyListeners();
  }

  /// 按下标移除监护人。
  void removeGuardianAt(int index) {
    if (index < 0 || index >= _guardians.length) return;
    _guardians.removeAt(index);
    notifyListeners();
  }

  // ---------------- 高危因素勾选集合（随整单保存） ----------------

  /// 绿色卡片的「无高危因素」特殊项名称（与其余四色互斥）。
  static const String noneHighRiskFactorName = '无母亲及胎儿、新生儿的高危因素';

  List<BaseHighRiskFactor> _highRiskDict = const [];

  /// 高危因素字典全量清单（本院，五色卡片数据源）。
  List<BaseHighRiskFactor> get highRiskDict => _highRiskDict;

  final Set<String> _checkedHighRiskIds = {};

  /// 已勾选的高危因素 ID 集合（随【保存】整表替换入库；绿色「无高危
  /// 因素」标记项不代表真实高危，保存时过滤、不落库）。
  Set<String> get checkedHighRiskIds => Set.unmodifiable(_checkedHighRiskIds);

  /// Tab 标签显示的高危因素计数：排除绿色【无高危因素】标记项（该标记
  /// 不代表真实高危、不落库，仅勾选它时计数显示为 0）。
  int get savedHighRiskCount {
    final none = _noneFactor;
    var count = _checkedHighRiskIds.length;
    if (none != null && _checkedHighRiskIds.contains(none.id)) {
      count--;
    }
    return count;
  }

  /// 指定颜色卡片中已勾选的高危因素数（供快捷导航按钮展示选中项计数；
  /// 绿色卡片另含「无高危因素」标记项，按需由调用方决定是否展示）。
  int checkedHighRiskCountOfColor(String colorName) {
    var count = 0;
    for (final f in _highRiskDict) {
      if (f.riskColor == colorName && _checkedHighRiskIds.contains(f.id)) {
        count++;
      }
    }
    return count;
  }

  /// 高危因素备注（factorId → 备注文本；随整单保存落 CHILD_HIGH_RISK_FACTOR.REMARK）。
  final Map<String, String> _highRiskRemarks = {};

  /// 当前各高危因素的备注映射（无备注的项不出现）。
  Map<String, String> get highRiskRemarks => Map.unmodifiable(_highRiskRemarks);

  /// 取某高危因素的备注（无则为空串）。
  String highRiskRemarkOf(String factorId) => _highRiskRemarks[factorId] ?? '';

  /// 设置/清除某高危因素的备注（空串清除）。
  void setHighRiskRemark(String factorId, String remark) {
    final v = remark.trim();
    if (v.isEmpty) {
      _highRiskRemarks.remove(factorId);
    } else {
      _highRiskRemarks[factorId] = v;
    }
    notifyListeners();
  }

  /// 字典中的绿色「无高危因素」特殊项（未配置时为 null）。
  BaseHighRiskFactor? get _noneFactor {
    for (final f in _highRiskDict) {
      if (f.riskColor == '绿色' && f.riskFactorName == noneHighRiskFactorName) {
        return f;
      }
    }
    return null;
  }

  /// 互斥规则映射：高危因素 ID → 与其互斥（不能同时勾选）的其他 ID 集合
  /// （由 BASE_HIGH_RISK_FACTOR_EXCLUSION 的无序组合展开）。
  final Map<String, Set<String>> _exclusionMap = {};

  /// 与指定高危因素互斥的其他高危因素 ID 集合（无规则时为空集）。
  Set<String> exclusiveHighRiskIdsOf(String factorId) => Set.unmodifiable(_exclusionMap[factorId] ?? const <String>{});

  /// 加载本院高危因素互斥规则并展开为「ID → 互斥 ID 集合」映射。
  ///
  /// 失败时清空映射（互斥降级为仅「无高危因素」标记规则，不影响其余
  /// 功能），记日志不抛出。互斥名单唯一来源为互斥规则表
  /// （BASE_HIGH_RISK_FACTOR_EXCLUSION），自动筛查不含自带互斥。
  Future<void> _loadHighRiskExclusions() async {
    _exclusionMap.clear();
    try {
      final rules = await _highRiskFactorExclusionService.queryAll();
      for (final rule in rules) {
        final ids = rule.riskFactorIds;
        for (final id in ids) {
          _exclusionMap.putIfAbsent(id, () => {}).addAll(ids.where((other) => other != id));
        }
      }
    } catch (e, st) {
      LogHelper.error('client:ChildCreateViewModel.loadHighRiskExclusions', e, st);
    }
  }

  /// 勾选 [factorId] 前清除同一互斥规则下其他已勾选项及其备注（自动
  /// 清除而非灰化禁用；备注依附于选中项，随清除一并移除）。
  void _clearExclusiveSelections(String factorId) {
    final conflicts = _exclusionMap[factorId];
    if (conflicts == null || conflicts.isEmpty) return;
    for (final id in conflicts) {
      _checkedHighRiskIds.remove(id);
      _highRiskRemarks.remove(id);
    }
  }

  /// 无勾选时默认勾选绿色【无母亲及胎儿、新生儿的高危因素】（新增态
  /// 与浏览态「库内无高危因素记录」共用；已有勾选或字典未加载/未配置
  /// 该项时不做任何事——用户手动取消后可保持空选）。
  void _applyDefaultHighRiskSelection() {
    if (_checkedHighRiskIds.isNotEmpty) return;
    final none = _noneFactor;
    if (none != null) {
      _checkedHighRiskIds.add(none.id);
    }
  }

  /// 绿色「无高危因素」是否已勾选。
  bool get greenNoneChecked {
    final none = _noneFactor;
    return none != null && _checkedHighRiskIds.contains(none.id);
  }

  /// 其余四色是否存在已勾选项（仅语义查询，用于互斥清除判断；不再用于
  /// 界面灰化——需求改为「自动清除对方选择」而非禁用）。
  bool get anyNonGreenChecked => _checkedHighRiskIds.any((id) {
    for (final f in _highRiskDict) {
      if (f.id == id) {
        return f.riskColor != null && f.riskColor != '绿色';
      }
    }
    return false;
  });

  /// 指定高危因素当前是否可勾选（仅浏览态禁用；互斥项不灰化——勾选
  /// 绿色「无高危因素」会自动清除四色勾选、反之亦然，见
  /// [toggleHighRiskFactor]）。
  bool canToggleHighRisk(BaseHighRiskFactor factor, {required bool editable}) => editable;

  /// 加载高危因素数据：字典全量清单 + 本院互斥规则 + 当前儿童已保存的
  /// 勾选与备注（浏览/修改态回显）；无已保存记录（新增态或库内为空）时
  /// 默认勾选绿色【无母亲及胎儿、新生儿的高危因素】。
  ///
  /// 三路请求**并行**（互不依赖；此前字典→互斥→记录串行三次往返，浏览
  /// 态开档多等两个往返）：各路自捕获异常记日志降级，不中断其余。
  Future<void> loadHighRiskData() async {
    final id = currentChildId;
    _checkedHighRiskIds.clear();
    _highRiskRemarks.clear();
    final results = await Future.wait<dynamic>([
      _loadDict(),
      _loadHighRiskExclusions(),
      id.isEmpty ? Future.value(const <ChildHighRiskFactor>[]) : _loadSavedFactors(id),
    ]);
    _highRiskDict = results[0] as List<BaseHighRiskFactor>;
    final rows = results[2] as List<ChildHighRiskFactor>;
    _checkedHighRiskIds.addAll(rows.map((f) => f.highRiskFactorId));
    for (final row in rows) {
      final remark = row.remark?.trim() ?? '';
      if (remark.isNotEmpty) {
        _highRiskRemarks[row.highRiskFactorId] = remark;
      }
    }
    // 无已保存记录（新增态或库内为空）→ 默认勾选绿色「无高危因素」标记项
    _applyDefaultHighRiskSelection();
    // 按已载入扩展信息重算自动筛查命中（新增态 ext 为 null 按空档案处理）；
    // 命中基线与自动管理集合随载入重置（本次命中的库记录纳入自动集合，
    // 后续编辑触发字段时按其增量清选）
    _autoScreenedIds.clear();
    _lastScreeningTargetNames.clear();
    applyHighRiskAutoScreening(_ext ?? _emptyExt());
    notifyListeners();
  }

  /// 拉取高危因素字典清单（失败记日志、降级为空清单）。
  Future<List<BaseHighRiskFactor>> _loadDict() async {
    try {
      return await _highRiskFactorService.queryAll();
    } catch (e, st) {
      LogHelper.error('client:ChildCreateViewModel.loadHighRiskData(dict)', e, st);
      return const [];
    }
  }

  /// 拉取儿童已保存的高危因素记录（失败记日志、降级为空列表）。
  Future<List<ChildHighRiskFactor>> _loadSavedFactors(String id) async {
    try {
      return await _childService.highRiskFactors(id);
    } catch (e, st) {
      LogHelper.error('client:ChildCreateViewModel.loadHighRiskData(checked)', e, st);
      return const [];
    }
  }

  /// 空扩展信息（新增态自动筛查的推导输入）。
  ChildExtInfo _emptyExt() => const ChildExtInfo(childId: '', creatorId: '', creatorName: '', hospId: '', hospName: '');

  /// 构建提交给服务端的高危因素选择项：过滤绿色【无高危因素】标记项
  /// （仅界面标记，不落库），其余项附各自备注。
  List<({String factorId, String? remark})> _buildHighRiskSelections() {
    final none = _noneFactor;
    return [
      for (final id in _checkedHighRiskIds)
        if (none == null || id != none.id) (factorId: id, remark: _highRiskRemarks[id]),
    ];
  }

  /// 切换某高危因素的勾选状态。
  ///
  /// 互斥规则两层：① 界面标记规则——勾选绿色「无高危因素」清空其余四色
  /// 勾选，勾选其余四色任一项则取消该标记项；② 互斥规则表——勾选某项时
  /// 自动清除与其互斥的已勾选项（BASE_HIGH_RISK_FACTOR_EXCLUSION）。
  ///
  /// 取消勾选时同步清除该项已录入的备注（备注依附于选中项）；互斥清除
  /// 时同样清除被清除项的备注，避免残留数据。
  void toggleHighRiskFactor(BaseHighRiskFactor factor, bool checked) {
    _setCheckedHighRisk(factor, checked);
    notifyListeners();
  }

  /// 勾选/取消勾选的内部实现（界面切换与自动筛查共用）。
  void _setCheckedHighRisk(BaseHighRiskFactor factor, bool checked) {
    final none = _noneFactor;
    final isNone = none != null && factor.id == none.id;
    if (!checked) {
      _checkedHighRiskIds.remove(factor.id);
      _highRiskRemarks.remove(factor.id);
    } else if (isNone) {
      _checkedHighRiskIds
        ..clear()
        ..add(factor.id);
      _highRiskRemarks.clear();
    } else {
      if (factor.riskColor != '绿色' && none != null) {
        _checkedHighRiskIds.remove(none.id);
      }
      _clearExclusiveSelections(factor.id);
      _checkedHighRiskIds.add(factor.id);
    }
  }

  /// 上次自动筛查命中的名称集合：与本次相同则直接返回（不重算、不
  /// 通知）——建档页整树监听本 VM，逐键通知会在 debug 模式下造成整页
  /// 重建卡顿；只有命中集合真正变化才值得重建一次。
  Set<String> _lastScreeningTargetNames = {};

  /// 由自动筛查勾选的高危因素 ID 集合：条件不再满足时仅清除这些项
  /// ——用户手动勾选的项不受筛查影响（可自由勾选并保存，需求 2026-11-21
  /// 明确）；载入档案后命中的库记录同样纳入本集合，编辑扩展信息时按
  /// 其增量清选。
  final Set<String> _autoScreenedIds = {};

  /// 高危因素自动筛查：按当前扩展信息重算命中项。
  ///
  /// ① 清除——此前由筛查勾选（[ _autoScreenedIds]，含载入时命中的库
  /// 记录）而本次未命中的项取消勾选并清除备注；用户手动勾选的项不在
  /// 该集合内，一律保留。② 勾选——本次命中且未勾选的项自动勾选（沿用
  /// 「无高危因素」标记互斥与同组互斥清除）并纳入自动管理集合。扩展
  /// 信息表单在筛查触发字段变更后调用；载入档案/保存后由
  /// [loadHighRiskData] 以已存扩展信息重算一次（命中集为基线）。
  void applyHighRiskAutoScreening(ChildExtInfo ext) {
    final names = HighRiskAutoScreening.targetFactorNames(ext);
    if (_lastScreeningTargetNames.length == names.length && _lastScreeningTargetNames.containsAll(names)) {
      return;
    }
    final idByName = <String, String>{};
    for (final f in _highRiskDict) {
      idByName.putIfAbsent(f.riskFactorName, () => f.id);
    }
    final targetIds = {
      for (final name in names)
        if (idByName[name] != null) idByName[name]!,
    };
    // ① 清除此前由筛查勾选、本次未命中的项（手动勾选不在集合内，保留）
    for (final id in _autoScreenedIds.difference(targetIds)) {
      if (_checkedHighRiskIds.remove(id)) {
        _highRiskRemarks.remove(id);
      }
    }
    _autoScreenedIds
      ..clear()
      ..addAll(targetIds);
    // ② 自动勾选本次命中且未勾选的项
    for (final id in targetIds) {
      if (!_checkedHighRiskIds.contains(id)) {
        _setCheckedHighRisk(_highRiskDict.firstWhere((f) => f.id == id), true);
      }
    }
    _lastScreeningTargetNames = names;
    notifyListeners();
  }

  /// 快速新增高危因素成功后：刷新字典清单并自动勾选新增项（保留其余
  /// 已勾选项；新增项为黄/橙/红/紫时按互斥规则清除绿色「无高危因素」，
  /// 并清除规则表中与其互斥的已勾选项——新增项 ID 通常尚无规则，兜底
  /// 防字典值复用时残留冲突）。
  void addCreatedFactor(BaseHighRiskFactor factor) {
    if (!_highRiskDict.any((f) => f.id == factor.id)) {
      _highRiskDict = [..._highRiskDict, factor];
    }
    if (factor.riskColor != null && factor.riskColor != '绿色') {
      final none = _noneFactor;
      if (none != null) {
        _checkedHighRiskIds.remove(none.id);
      }
    }
    _clearExclusiveSelections(factor.id);
    _checkedHighRiskIds.add(factor.id);
    notifyListeners();
  }

  // ---------------- 居住地址级联（基本 Tab 表单用，含村级） ----------------

  List<Province>? _provinces;
  List<City>? _cities;
  List<County>? _counties;
  List<Town>? _towns;
  List<Village>? _villages;

  /// 省/直辖市/自治区列表（null = 未加载）。
  List<Province>? get provinces => _provinces;

  /// 市/自治州/地区列表。
  List<City>? get cities => _cities;

  /// 县/区/旗列表。
  List<County>? get counties => _counties;

  /// 乡/镇/街道列表。
  List<Town>? get towns => _towns;

  /// 村/居委会列表。
  List<Village>? get villages => _villages;

  Province? _selectedProvince;
  City? _selectedCity;
  County? _selectedCounty;
  Town? _selectedTown;
  Village? _selectedVillage;

  /// 已选省/直辖市/自治区。
  Province? get selectedProvince => _selectedProvince;

  /// 已选市/自治州/地区。
  City? get selectedCity => _selectedCity;

  /// 已选县/区/旗。
  County? get selectedCounty => _selectedCounty;

  /// 已选乡/镇/街道。
  Town? get selectedTown => _selectedTown;

  /// 已选村/居委会。
  Village? get selectedVillage => _selectedVillage;

  bool _addressLoading = false;

  /// 地址级联加载中。
  bool get addressLoading => _addressLoading;

  /// 居住地址编码：取最深一级行政区划代码（村>乡镇>县>市>省）。
  String? get addressCode => _selectedVillage?.code ?? _selectedTown?.code ?? _selectedCounty?.code ?? _selectedCity?.code ?? _selectedProvince?.code;

  /// 清空行政区划选择与下级缓存（进入新增/切换档案时调用）。
  void clearAdminDivisions() {
    _selectedProvince = null;
    _selectedCity = null;
    _selectedCounty = null;
    _selectedTown = null;
    _selectedVillage = null;
    _cities = null;
    _counties = null;
    _towns = null;
    _villages = null;
    notifyListeners();
  }

  /// 获取省/直辖市/自治区列表。
  ///
  /// 幂等：已加载过直接跳过（重复拉取会生成新的 Province 对象，使
  /// 已选中的省与下拉 items 身份失配触发 DropdownButton 断言）。
  ///returns: true 表示获取成功
  Future<bool> getProvinces() async {
    if (_provinces != null) {
      return true;
    }
    try {
      _addressLoading = true;
      notifyListeners();
      _provinces = await _divisionsService.getProvinces() ?? [];
      return true;
    } catch (e, st) {
      LogHelper.error('client:ChildCreateViewModel.getProvinces', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _addressLoading = false;
      notifyListeners();
    }
  }

  /// 选择省后清空下游并加载市列表。
  Future<bool> selectProvince(Province? p) async {
    _selectedProvince = p;
    _selectedCity = null;
    _selectedCounty = null;
    _selectedTown = null;
    _selectedVillage = null;
    _cities = null;
    _counties = null;
    _towns = null;
    _villages = null;
    notifyListeners();
    if (p == null) return true;
    try {
      _addressLoading = true;
      notifyListeners();
      _cities = await _divisionsService.getCitiesByProvince(p.code) ?? [];
      return true;
    } catch (e, st) {
      LogHelper.error('client:ChildCreateViewModel.selectProvince', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _addressLoading = false;
      notifyListeners();
    }
  }

  /// 选择市后清空下游并加载县列表。
  Future<bool> selectCity(City? c) async {
    _selectedCity = c;
    _selectedCounty = null;
    _selectedTown = null;
    _selectedVillage = null;
    _counties = null;
    _towns = null;
    _villages = null;
    notifyListeners();
    if (c == null) return true;
    try {
      _addressLoading = true;
      notifyListeners();
      _counties = await _divisionsService.getCountiesByCity(c.code) ?? [];
      return true;
    } catch (e, st) {
      LogHelper.error('client:ChildCreateViewModel.selectCity', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _addressLoading = false;
      notifyListeners();
    }
  }

  /// 选择县后清空下游并加载乡镇列表。
  Future<bool> selectCounty(County? c) async {
    _selectedCounty = c;
    _selectedTown = null;
    _selectedVillage = null;
    _towns = null;
    _villages = null;
    notifyListeners();
    if (c == null) return true;
    try {
      _addressLoading = true;
      notifyListeners();
      _towns = await _divisionsService.getTownsByCounty(c.code) ?? [];
      return true;
    } catch (e, st) {
      LogHelper.error('client:ChildCreateViewModel.selectCounty', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _addressLoading = false;
      notifyListeners();
    }
  }

  /// 选择乡镇后清空下游并加载村列表。
  Future<bool> selectTown(Town? t) async {
    _selectedTown = t;
    _selectedVillage = null;
    _villages = null;
    notifyListeners();
    if (t == null) return true;
    try {
      _addressLoading = true;
      notifyListeners();
      _villages = await _divisionsService.getVillagesByTown(t.code) ?? [];
      return true;
    } catch (e, st) {
      LogHelper.error('client:ChildCreateViewModel.selectTown', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _addressLoading = false;
      notifyListeners();
    }
  }

  /// 选择村/居委会。
  Future<bool> selectVillage(Village? v) async {
    _selectedVillage = v;
    notifyListeners();
    return true;
  }

  /// 按已载入档案的行政区划名称逐级回显级联选择（每步 await 恰好触发
  /// 下一级加载；找不到对应名称时停在已匹配层级）。
  Future<void> initAddressFromChild(ChildInfo child) async {
    clearAdminDivisions();
    if (_provinces == null) {
      await getProvinces();
    }
    final provinces = _provinces ?? const <Province>[];
    final province = provinces.cast<Province?>().firstWhere((e) => e!.name == child.addressProvince, orElse: () => null);
    if (province == null) return;
    await selectProvince(province);
    final cities = _cities ?? const <City>[];
    final city = cities.cast<City?>().firstWhere((e) => e!.name == child.addressCity, orElse: () => null);
    if (city == null) return;
    await selectCity(city);
    final counties = _counties ?? const <County>[];
    final county = counties.cast<County?>().firstWhere((e) => e!.name == child.addressCounty, orElse: () => null);
    if (county == null) return;
    await selectCounty(county);
    if ((child.addressTown ?? '').isEmpty) return;
    final towns = _towns ?? const <Town>[];
    final town = towns.cast<Town?>().firstWhere((e) => e!.name == child.addressTown, orElse: () => null);
    if (town == null) return;
    await selectTown(town);
    if ((child.addressVillage ?? '').isEmpty) return;
    final villages = _villages ?? const <Village>[];
    final village = villages.cast<Village?>().firstWhere((e) => e!.name == child.addressVillage, orElse: () => null);
    if (village == null) return;
    await selectVillage(village);
  }
}
