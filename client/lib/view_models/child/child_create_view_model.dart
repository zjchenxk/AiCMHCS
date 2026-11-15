import 'package:client/main.dart';
import 'package:client/services/admin_divisions_service.dart';
import 'package:client/services/child_service.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:common/model.dart';
import 'package:flutter/foundation.dart';

/// 儿童建档表单模式：empty-未载入档案（仅可新增）、browse-浏览已载入
/// 档案、create-新增录入、edit-修改已载入档案。
enum ChildFormMode { empty, browse, create, edit }

/// 儿童建档视图模型：操作权限（按钮显隐）、档案检索与整档装载、
/// 新增/修改/删除流转、监护人本地工作列表（随整单保存）、五级居住
/// 地址级联（基本信息表单用）。
///
/// 数据流：页面顶部查询区检索 → [selectChild] 载入整档进入浏览态；
/// 【新增】/【修改】进入录入态，三个 Tab 表单各自持控制器，【保存】
/// 时由页面收集表单数据经 [save] 整单提交；监护人行的增删改仅操作
/// 本地列表（不做权限控制），随整单保存一并入库。
class ChildCreateViewModel extends ChangeNotifier {
  /// 构造函数：可选注入服务（缺省经服务定位器取，便于测试覆写）。
  ChildCreateViewModel({
    ChildService? childService,
    MenuService? menuService,
    AdminDivisionsService? adminDivisionsService,
  }) : _childService = childService ?? getIt<ChildService>(),
       _menuService = menuService ?? getIt<MenuService>(),
       _divisionsService = adminDivisionsService ?? getIt<AdminDivisionsService>();

  final ChildService _childService;

  final MenuService _menuService;

  final AdminDivisionsService _divisionsService;

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

  /// 是否显示顶部查询区（无修改/删除权限时无需检索已有档案）。
  bool get showQueryArea => canUpdate || canDelete;

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

  List<ChildInfo> _searchResults = [];

  /// 查询区检索结果（简要档案列表）。
  List<ChildInfo> get searchResults => _searchResults;

  String _messageOf(Object e) => e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');

  /// 检索本院儿童档案（姓名/就诊卡号/保健号至少一个条件）。
  Future<bool> search({String? name, String? visitCardNo, String? healthNo}) async {
    _loading = true;
    _errorMsg = null;
    notifyListeners();
    try {
      _searchResults = await _childService.search(name: name, visitCardNo: visitCardNo, healthNo: healthNo);
      return true;
    } catch (e, st) {
      LogHelper.error('client:ChildCreateViewModel.search', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _loading = false;
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
      await initAddressFromChild(child);
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
    _searchResults = [];
    _mode = ChildFormMode.create;
    clearAdminDivisions();
    await getProvinces();
  }

  /// 进入修改录入态（保留已载入档案数据，表单可编辑）。
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
      _searchResults = [];
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
  Future<bool> save({
    required ChildInfo child,
    ChildExtInfo? ext,
    List<ChildGuardianInfo>? guardians,
  }) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final guardianList = guardians ?? _guardians;
      final ChildArchive archive;
      if (_mode == ChildFormMode.edit) {
        archive = await _childService.update(id: _child!.id, child: child, ext: ext, guardians: guardianList);
      } else {
        archive = await _childService.create(child: child, ext: ext, guardians: guardianList);
      }
      _child = archive.$1;
      _ext = archive.$2;
      _guardians = archive.$3;
      _searchResults = [];
      _mode = ChildFormMode.browse;
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
      _searchResults = [];
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
  ///returns: true 表示获取成功
  Future<bool> getProvinces() async {
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
