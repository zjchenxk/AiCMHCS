import 'package:client/main.dart';
import 'package:client/services/holiday_service.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 右侧信息表单模式（同高危因素互斥规则管理）。
enum HolidayFormMode {
  /// 未选中任何节假日（表单区显示提示）。
  empty,

  /// 编辑选中的节假日。
  edit,

  /// 新增模式（表单清空待录）。
  create,
}

/// 法定节假日管理 ViewModel：左侧节假日列表，右侧信息表单三态
/// （未选中 / 编辑选中 / 新增）。
///
/// 每次进入页面 loadData 都强制重拉节假日与当前登录角色的操作权限
/// 编码（/api/menu/operations，角色经会话服务端推导、切换角色后重进
/// 即生效），按钮级灰化经 canXxx getter 判定。
class HolidayManagementViewModel extends ChangeNotifier {
  /// 操作权限：新增法定节假日。
  static const String opCreate = '9911000001';

  /// 操作权限：修改法定节假日。
  static const String opUpdate = '9911000002';

  /// 操作权限：删除法定节假日。
  static const String opDelete = '9911000003';

  /// 构造函数：注入节假日与菜单服务（缺省从服务定位器取，测试可覆写；
  /// 菜单服务仅用于拉取角色操作权限编码）。
  HolidayManagementViewModel({HolidayService? holidayService, MenuService? menuService}) : _service = holidayService ?? getIt<HolidayService>(), _menuService = menuService ?? getIt<MenuService>();

  final HolidayService _service;
  final MenuService _menuService;

  final List<BaseHoliday> _holidays = [];
  final Set<String> _operationCodes = {};

  BaseHoliday? _selected;
  bool _creating = false;
  bool _loaded = false;
  bool _loading = false;
  bool _busy = false;
  String? _errorMsg;

  /// 本院全部法定节假日（按起始日期倒序）。
  List<BaseHoliday> get holidays => _holidays;

  /// 当前选中的节假日（编辑态表单回填）。
  BaseHoliday? get selected => _selected;

  /// 右侧表单当前模式。
  HolidayFormMode get formMode {
    if (_creating) return HolidayFormMode.create;
    if (_selected == null) return HolidayFormMode.empty;
    return HolidayFormMode.edit;
  }

  /// 首屏加载中。
  bool get loading => _loading;

  /// 增删改操作进行中（防重复提交）。
  bool get busy => _busy;

  String? get errorMsg => _errorMsg;

  /// 已加载且本院无任何节假日（左侧显示空态引导）。
  bool get isEmpty => _loaded && _holidays.isEmpty;

  // ---------------- 操作权限 ----------------

  /// 是否拥有「新增法定节假日」权限。
  bool get canCreate => _operationCodes.contains(opCreate);

  /// 是否拥有「修改法定节假日」权限（保存按钮与表单可编辑性依据）。
  bool get canUpdate => _operationCodes.contains(opUpdate);

  /// 是否拥有「删除法定节假日」权限。
  bool get canDelete => _operationCodes.contains(opDelete);

  // ---------------- 加载 ----------------

  /// 加载节假日与操作权限（进入页面时调用）。每次调用都强制重拉，
  /// 选中项按 ID 刷新引用。
  Future<bool> loadData() async {
    _loading = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _refreshPermissions();
      await _refreshHolidays();
      _loaded = true;
      return true;
    } catch (e, st) {
      LogHelper.error('client:HolidayManagementViewModel.loadData', e, st);
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

  /// 拉取本院全部法定节假日（选中项按 ID 刷新引用）。
  Future<void> _refreshHolidays() async {
    final holidays = await _service.queryAll();
    _holidays
      ..clear()
      ..addAll(holidays);
    final selectedId = _selected?.id;
    if (selectedId != null) {
      _selected = _findById(selectedId);
    }
  }

  // ---------------- 交互 ----------------

  /// 选中左侧节假日（右侧切换为编辑态；无修改权限时表单只读）。
  void selectHoliday(BaseHoliday holiday) {
    if (_selected?.id == holiday.id && !_creating) return;
    _creating = false;
    _selected = holiday;
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

  /// 新增法定节假日，成功后整表重拉并退出新增态（自增主键由服务端
  /// 生成，新增行按起始日期排序落位，不自动选中）。
  Future<bool> createHoliday({
    required String startDate,
    required String endDate,
    required int holidayType,
  }) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _service.create(startDate: startDate, endDate: endDate, holidayType: holidayType);
      await _refreshHolidays();
      _creating = false;
      _selected = null;
      return true;
    } catch (e, st) {
      LogHelper.error('client:HolidayManagementViewModel.createHoliday', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 修改法定节假日（changes 键同后端契约），成功后整表重拉。
  Future<bool> updateHoliday(String id, Map<String, Object?> changes) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _service.update(id, changes);
      await _refreshHolidays();
      _selected = _findById(id);
      return true;
    } catch (e, st) {
      LogHelper.error('client:HolidayManagementViewModel.updateHoliday', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 删除法定节假日，成功后整表重拉；删除选中项时回退空态。
  Future<bool> deleteHoliday(BaseHoliday holiday) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _service.delete(holiday.id);
      if (_selected?.id == holiday.id) {
        _selected = null;
        _creating = false;
      }
      await _refreshHolidays();
      return true;
    } catch (e, st) {
      LogHelper.error('client:HolidayManagementViewModel.deleteHoliday', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ---------------- 通用 ----------------

  /// 按 ID 在已加载列表中查找（不存在返回 null）。
  BaseHoliday? _findById(String id) {
    for (final holiday in _holidays) {
      if (holiday.id == id) return holiday;
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
