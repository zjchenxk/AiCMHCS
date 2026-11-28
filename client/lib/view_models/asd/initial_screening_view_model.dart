import 'dart:async';

import 'package:client/main.dart';
import 'package:client/models/current_child.dart';
import 'package:client/services/child_service.dart';
import 'package:client/services/initial_screening_service.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/services/time_service.dart';
import 'package:client/utils/age_util.dart';
import 'package:client/utils/log_helper.dart';
import 'package:common/model.dart';
import 'package:flutter/foundation.dart';

/// 初筛记录表 TAB 定义（检查时段 CHECK_MONTH 取值 + 标签，顺序即 TAB
/// 顺序）。
const List<(int, String)> screeningTabs = [
  (3, '3月龄'),
  (6, '6月龄'),
  (8, '8月龄'),
  (12, '12月龄'),
  (18, '18月龄'),
  (24, '24月龄'),
  (30, '30月龄'),
  (36, '36月龄'),
  (48, '4岁'),
  (60, '5岁'),
  (72, '6岁'),
];

/// 孤独症初筛记录表视图模型：操作权限（按钮灰化）、当前儿童上下文
/// （主界面顶部搜索选定后同步）、该儿童全部初筛记录（按检查时段映射，
/// TAB 红点与逐月龄浏览共用）、预警征象条目按月龄缓存、检查医生候选
/// 与保存/删除流转。
///
/// 数据流：页面监听主界面「当前儿童」变化经 [syncChild] 同步，儿童变化
/// 时清空全部状态并三路并行重载（初筛记录 / 扩展档案（早产矫正年龄
/// 依据）/ 检查医生）。实足年龄推算口径见 [computeAutoTabMonth]
/// （页面每次进入按需应用，自动定位到对应时段 TAB）。预警征象条目
/// 在 TAB 首次进入时经 [ensureScaleItems] 按月龄懒加载缓存。
class InitialScreeningViewModel extends ChangeNotifier {
  /// 构造函数：可选注入服务（缺省经服务定位器取，便于测试覆写）。
  InitialScreeningViewModel({InitialScreeningService? screeningService, ChildService? childService, MenuService? menuService, TimeService? timeService})
    : _screeningService = screeningService ?? getIt<InitialScreeningService>(),
      _childService = childService ?? getIt<ChildService>(),
      _menuService = menuService ?? getIt<MenuService>(),
      _timeService = timeService ?? getIt<TimeService>();

  final InitialScreeningService _screeningService;

  final ChildService _childService;

  final MenuService _menuService;

  final TimeService _timeService;

  // ---------------- 操作权限（SYS_MENU 操作项 ITEM_CODE） ----------------

  /// 新增操作权限码。
  static const String opCreate = '0301000001';

  /// 修改操作权限码。
  static const String opUpdate = '0301000002';

  /// 保存操作权限码。
  static const String opSave = '0301000003';

  /// 删除操作权限码。
  static const String opDelete = '0301000004';

  /// 打印操作权限码。
  static const String opPrint = '0301000005';

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

  /// 是否拥有打印操作权限。
  bool get canPrint => _operationCodes.contains(opPrint);

  /// 拉取当前角色操作权限码（进页时调用）。
  Future<void> loadPermissions() async {
    try {
      final codes = await _menuService.queryOperationCodes();
      _operationCodes
        ..clear()
        ..addAll(codes);
    } catch (e, st) {
      LogHelper.error('client:InitialScreeningViewModel.loadPermissions', e, st);
      _operationCodes.clear();
    }
    notifyListeners();
  }

  // ---------------- 当前儿童与整页状态 ----------------

  CurrentChild? _child;

  /// 当前儿童（主界面顶部搜索选定；null 表示未选儿童）。
  CurrentChild? get child => _child;

  /// 是否已选定儿童。
  bool get hasChild => _child != null && _child!.id.isNotEmpty;

  String? _errorMsg;

  /// 最近一次操作的失败提示（页面 SnackBar 展示后经 [clearError] 清空）。
  String? get errorMsg => _errorMsg;

  /// 清空错误提示。
  void clearError() {
    _errorMsg = null;
  }

  /// 保存/删除进行中标记（防重入）。
  bool _busy = false;

  /// 是否保存/删除进行中。
  bool get busy => _busy;

  // ---------------- 初筛记录（按检查时段映射） ----------------

  final Map<int, InitialScreening> _recordsByMonth = {};

  /// 取指定检查时段的已保存初筛记录（无则 null）。
  InitialScreening? recordOf(int month) => _recordsByMonth[month];

  /// 指定检查时段是否已做初筛（TAB 红点依据）。
  bool hasRecord(int month) => _recordsByMonth.containsKey(month);

  /// 按当前儿童实足年龄推算应自动切换到的 TAB 检查时段（null 表示无法
  /// 推算——未选儿童或年龄早于首个筛查窗口，页面维持首签）。
  ///
  /// 按需现算（不缓存）：VM 是全局单例，页面反复进出时各自按需取值，
  /// 由页面自行保证「每儿童每次进页只应用一次」，避免缓存消费标记导致
  /// 二次进页不再自动切换。
  int? computeAutoTabMonth() => _computeAutoTabMonth();

  /// 业务当前时间（全局时间服务口径；表单默认值等业务时间统一取这里）。
  DateTime now() => _timeService.now();

  /// 扩展档案（早产矫正年龄依据：出生孕周/孕天）。
  ChildExtInfo? _ext;

  /// 扩展档案展示签名（孕周/孕天，纠正年龄依据；null 表示未装载）——
  /// 页面据此感知外部档案修改后重算纠正年龄等派生显示。
  String? get extSignature => _ext == null ? null : '${_ext!.gestationalWeek ?? ''}|${_ext!.gestationalDay ?? ''}';

  /// 装载完成后的静默失败提示（记录/医生加载失败时界面给出可重试提示）。
  bool _loadFailed = false;

  /// 整页数据装载是否失败（提供重试入口）。
  bool get loadFailed => _loadFailed;

  /// 待打开的检查时段（侧边栏「初筛儿童」列表双击记录设置，页面
  /// `_tryApplyAutoTab` 取走并切到该月龄 TAB 后清空；优先于按年龄自动
  /// 推算的 TAB，同儿童重复双击也能再次定位）。
  int? _pendingOpenMonth;

  /// 请求打开指定检查时段 TAB（初筛列表双击记录后、打开初筛页前调用；
  /// 立即通知监听者——页面已挂载时即时切换 TAB，未挂载时进页后消费）。
  ///param month: 检查时段（CHECK_MONTH，如 12 表示 12 月龄）
  void requestOpenMonth(int month) {
    _pendingOpenMonth = month;
    notifyListeners();
  }

  /// 取走待打开的检查时段（取走即清空；无待处理请求返回 null）。
  int? consumePendingOpenMonth() {
    final month = _pendingOpenMonth;
    _pendingOpenMonth = null;
    return month;
  }

  /// 同步当前儿童（按 ID 幂等去重；儿童变化即清空状态并重载）。
  ///
  /// 同一儿童但档案字段被修改（如儿童建档页改出生日期保存后经
  /// MainViewModel.setCurrentChild 重新下发，ID 不变）时，快照有变仍需
  /// 替换——工具栏摘要、实足年龄、自动 TAB 推算均由快照派生；初筛记录
  /// 与医生候选不随档案字段变化、不重载，孕周/孕天（纠正年龄依据）单独
  /// 重载扩展档案。
  ///param selected: 主界面顶部搜索选定的儿童（null 表示未选定，清空）
  Future<void> syncChild(CurrentChild? selected) async {
    final nextId = selected?.id ?? '';
    final currentId = _child?.id ?? '';
    if (nextId == currentId) {
      if (nextId.isEmpty) {
        return;
      }
      final current = _child!;
      if (current.name == selected!.name && current.gender == selected.gender && current.birthDate == selected.birthDate) {
        return;
      }
      _child = selected;
      notifyListeners();
      unawaited(_reloadExt());
      return;
    }
    _child = selected;
    _resetChildState();
    notifyListeners();
    if (nextId.isEmpty) {
      return;
    }
    await _loadChildData(nextId);
  }

  /// 重载扩展档案（出生孕周/孕天，早产纠正年龄依据；可在儿童建档页修改）。
  /// 静默失败——保留旧值，仅影响纠正年龄口径。
  Future<void> _reloadExt() async {
    final childId = _child?.id ?? '';
    if (childId.isEmpty) {
      return;
    }
    try {
      final ext = await _childService.load(childId).then<ChildExtInfo?>((archive) => archive.$2);
      // 儿童已切换时丢弃过期响应
      if (_child?.id != childId) {
        return;
      }
      _ext = ext;
      notifyListeners();
    } catch (e, st) {
      LogHelper.error('client:InitialScreeningViewModel.reloadExt', e, st);
    }
  }

  /// 重载当前儿童整页数据（装载失败的界面重试入口）。
  Future<void> reload() async {
    final id = _child?.id ?? '';
    if (id.isEmpty) {
      return;
    }
    _resetChildState();
    notifyListeners();
    await _loadChildData(id);
  }

  /// 清空随儿童联动的状态。
  void _resetChildState() {
    _recordsByMonth.clear();
    _scaleItemsByMonth.clear();
    _scaleItemsLoading.clear();
    _doctors = const [];
    _doctorsLoaded = false;
    _ext = null;
    _loadFailed = false;
  }

  /// 三路并行装载：初筛记录 / 扩展档案 / 检查医生；完成后按实足年龄
  /// 推算自动 TAB。单路失败不阻断其余数据，标记整体失败供界面重试。
  Future<void> _loadChildData(String childId) async {
    final results = await Future.wait([
      _screeningService.query(childId).then<List<InitialScreening>?>((v) => v).catchError((Object e, StackTrace st) {
        LogHelper.error('client:InitialScreeningViewModel.query', e, st);
        return null;
      }),
      _childService.load(childId).then<ChildExtInfo?>((archive) => archive.$2).catchError((Object e, StackTrace st) {
        LogHelper.error('client:InitialScreeningViewModel.loadExt', e, st);
        return null;
      }),
      _screeningService.doctors().then<List<DoctorOption>?>((v) => v).catchError((Object e, StackTrace st) {
        LogHelper.error('client:InitialScreeningViewModel.doctors', e, st);
        return null;
      }),
    ]);
    // 儿童已切换时丢弃过期响应
    if (_child?.id != childId) {
      return;
    }
    var failed = false;
    final records = results[0] as List<InitialScreening>?;
    if (records != null) {
      _recordsByMonth
        ..clear()
        ..addEntries([for (final r in records) MapEntry(r.checkMonth, r)]);
    } else {
      failed = true;
    }
    _ext = results[1] as ChildExtInfo?;
    final doctors = results[2] as List<DoctorOption>?;
    if (doctors != null) {
      _doctors = doctors;
      _doctorsLoaded = true;
    } else {
      failed = true;
    }
    _loadFailed = failed;
    notifyListeners();
  }

  /// 按实足年龄推算应自动切换到的检查时段（需求口径：各月龄窗口按
  /// 「下限月龄+15 天」或整月边界划分；早于首个窗口保持首个 TAB）。
  ///
  /// 实足年龄以（总月数, 天）二元组与窗口端点比较：
  /// 3 月龄 [2月15天, 5月15天)、6 月龄 [5月15天, 7月15天)、
  /// 8 月龄 [7月15天, 11月15天)、12 月龄 [11月15天, 17月)、
  /// 18 月龄 [17月, 23月)、24 月龄 [23月, 29月)、30 月龄 [29月, 35月)、
  /// 36 月龄 [35月, 47月)、4 岁 [47月, 59月)、5 岁 [59月, 71月)、
  /// 6 岁 ≥71月。
  int? _computeAutoTabMonth() {
    final child = _child;
    if (child == null || child.id.isEmpty) {
      return null;
    }
    final now = _timeService.now();
    final parts = AgeUtil.ageParts(child.birthDate, now);
    final totalMonths = parts.years * 12 + parts.months;
    final days = parts.days;
    // (月, 天) 二元组比较
    bool ge(int m, int d) => totalMonths > m || (totalMonths == m && days >= d);
    bool lt(int m, int d) => totalMonths < m || (totalMonths == m && days < d);
    if (ge(2, 15) && lt(5, 15)) return 3;
    if (ge(5, 15) && lt(7, 15)) return 6;
    if (ge(7, 15) && lt(11, 15)) return 8;
    if (ge(11, 15) && lt(17, 0)) return 12;
    if (ge(17, 0) && lt(23, 0)) return 18;
    if (ge(23, 0) && lt(29, 0)) return 24;
    if (ge(29, 0) && lt(35, 0)) return 30;
    if (ge(35, 0) && lt(47, 0)) return 36;
    if (ge(47, 0) && lt(59, 0)) return 48;
    if (ge(59, 0) && lt(71, 0)) return 60;
    if (ge(71, 0)) return 72;
    return null;
  }

  // ---------------- 预警征象条目（按月龄缓存） ----------------

  final Map<int, List<WscmbdItem>> _scaleItemsByMonth = {};

  final Set<int> _scaleItemsLoading = {};

  /// 取指定月龄已缓存的预警征象条目（未加载为 null，已加载无条目为空
  /// 列表——字典未录入提示依据）。
  List<WscmbdItem>? scaleItemsOf(int month) => _scaleItemsByMonth[month];

  /// 指定月龄条目是否加载中。
  bool scaleItemsLoading(int month) => _scaleItemsLoading.contains(month);

  /// 按月龄懒加载预警征象条目（已加载/加载中跳过）。
  Future<void> ensureScaleItems(int month) async {
    if (_scaleItemsByMonth.containsKey(month) || _scaleItemsLoading.contains(month)) {
      return;
    }
    _scaleItemsLoading.add(month);
    notifyListeners();
    try {
      final items = await _screeningService.wscmbdItems(month);
      // 儿童已切换时丢弃过期响应（_resetChildState 已清缓存）
      if (!_scaleItemsLoading.contains(month)) {
        return;
      }
      _scaleItemsByMonth[month] = items;
    } catch (e, st) {
      LogHelper.error('client:InitialScreeningViewModel.ensureScaleItems', e, st);
      _errorMsg = '预警征象条目加载失败，请稍后重试';
      // 失败不缓存，允许重试（移除加载中标记即可再次进入）
    } finally {
      _scaleItemsLoading.remove(month);
      notifyListeners();
    }
  }

  // ---------------- 检查医生候选 ----------------

  List<DoctorOption> _doctors = const [];

  /// 检查医生候选（当前登录用户所属科室的同科室启用医生）。
  List<DoctorOption> get doctors => List.unmodifiable(_doctors);

  /// 医生候选是否已加载（false 时界面显示加载中）。
  bool _doctorsLoaded = false;
  bool get doctorsLoaded => _doctorsLoaded;

  // ---------------- 年龄计算 ----------------

  /// 按检查日期计算实足年龄三段（出生日期缺失/晚于检查日期返回 null）。
  ({int years, int months, int days})? actualAgePartsFor(DateTime checkDate) {
    final child = _child;
    if (child == null || child.id.isEmpty) {
      return null;
    }
    if (!checkDate.isAfter(child.birthDate)) {
      return null;
    }
    return AgeUtil.ageParts(child.birthDate, checkDate);
  }

  /// 按检查日期计算早产矫正年龄三段（非早产/超出矫正窗口/检查日期早于
  /// 预产期返回 null——界面隐藏纠正年龄三段，保存落 null）。
  ({int years, int months, int days})? correctedAgePartsFor(DateTime checkDate) {
    final child = _child;
    if (child == null || child.id.isEmpty) {
      return null;
    }
    return AgeUtil.correctedAgeParts(
      birthDate: child.birthDate,
      now: checkDate,
      gestationalWeek: _ext?.gestationalWeek,
      gestationalDay: _ext?.gestationalDay,
    );
  }

  // ---------------- 保存 / 删除 ----------------

  /// 保存初筛记录（新增/修改由服务端按「儿童+时段」查重自动判定），
  /// 成功后更新记录映射并返回 true。
  Future<bool> saveRecord(InitialScreening record) async {
    if (_busy) {
      return false;
    }
    _busy = true;
    notifyListeners();
    try {
      final saved = await _screeningService.save(record);
      _recordsByMonth[saved.checkMonth] = saved;
      _errorMsg = null;
      return true;
    } catch (e, st) {
      LogHelper.error('client:InitialScreeningViewModel.saveRecord', e, st);
      _errorMsg = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 删除指定检查时段的初筛记录，成功后移除映射并返回 true。
  Future<bool> deleteRecord(int month) async {
    final record = _recordsByMonth[month];
    if (record == null || _busy) {
      return false;
    }
    _busy = true;
    notifyListeners();
    try {
      await _screeningService.delete(record.id!);
      _recordsByMonth.remove(month);
      _errorMsg = null;
      return true;
    } catch (e, st) {
      LogHelper.error('client:InitialScreeningViewModel.deleteRecord', e, st);
      _errorMsg = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
