import 'package:client/main.dart';
import 'package:client/services/guidance_template_service.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 指导建议模板管理 ViewModel：左侧模板列表，右侧为选中模板的项目
/// 列表，两侧各自增删改。
///
/// 每次进入页面 loadData 都强制重拉模板与当前登录角色的操作权限编码
/// （/api/menu/operations，角色经会话服务端推导、切换角色后重进即生
/// 效），按钮级灰化经 canTemplateXxx / canItemXxx getter 判定。选中
/// 模板后按需加载其项目；删除模板时服务端连带删除其全部项目，客户端
/// 清空右侧列表。
class GuidanceTemplateManagementViewModel extends ChangeNotifier {
  // ---------------- 操作权限（模板 9912010001-3 / 项目 9912020001-3） ----------------

  /// 操作权限：新增指导建议模板。
  static const String opTemplateCreate = '9912010001';

  /// 操作权限：修改指导建议模板。
  static const String opTemplateUpdate = '9912010002';

  /// 操作权限：删除指导建议模板。
  static const String opTemplateDelete = '9912010003';

  /// 操作权限：新增指导建议项目。
  static const String opItemCreate = '9912020001';

  /// 操作权限：修改指导建议项目。
  static const String opItemUpdate = '9912020002';

  /// 操作权限：删除指导建议项目。
  static const String opItemDelete = '9912020003';

  /// 构造函数：注入模板与菜单服务（缺省从服务定位器取，测试可覆写；
  /// 菜单服务仅用于拉取角色操作权限编码）。
  GuidanceTemplateManagementViewModel({GuidanceTemplateService? guidanceTemplateService, MenuService? menuService})
    : _service = guidanceTemplateService ?? getIt<GuidanceTemplateService>(),
      _menuService = menuService ?? getIt<MenuService>();

  final GuidanceTemplateService _service;
  final MenuService _menuService;

  final List<BaseGuidanceTemplate> _templates = [];
  final List<BaseGuidanceTemplateItem> _items = [];
  final Set<String> _operationCodes = {};

  BaseGuidanceTemplate? _selected;
  bool _loading = false;
  bool _itemsLoading = false;
  bool _busy = false;
  bool _itemBusy = false;
  bool _loaded = false;
  String? _errorMsg;

  /// 本院全部指导建议模板（显示顺序非空在前按值升序）。
  List<BaseGuidanceTemplate> get templates => _templates;

  /// 当前选中的模板（null = 未选中，右侧显示空态引导）。
  BaseGuidanceTemplate? get selected => _selected;

  /// 选中模板下的全部项目（按创建时间正序）。
  List<BaseGuidanceTemplateItem> get items => _items;

  /// 首屏加载中。
  bool get loading => _loading;

  /// 右侧项目列表加载中（切选模板时）。
  bool get itemsLoading => _itemsLoading;

  /// 增删改操作进行中（防重复提交）。
  bool get busy => _busy;

  /// 项目增删改操作进行中（防重复提交）。
  bool get itemBusy => _itemBusy;

  String? get errorMsg => _errorMsg;

  /// 已加载且本院无任何模板（左侧显示空态引导）。
  bool get isEmpty => _loaded && _templates.isEmpty;

  // ---------------- 操作权限 ----------------

  /// 是否拥有「新增指导建议模板」权限。
  bool get canTemplateCreate => _operationCodes.contains(opTemplateCreate);

  /// 是否拥有「修改指导建议模板」权限。
  bool get canTemplateUpdate => _operationCodes.contains(opTemplateUpdate);

  /// 是否拥有「删除指导建议模板」权限。
  bool get canTemplateDelete => _operationCodes.contains(opTemplateDelete);

  /// 是否拥有「新增指导建议项目」权限。
  bool get canItemCreate => _operationCodes.contains(opItemCreate);

  /// 是否拥有「修改指导建议项目」权限。
  bool get canItemUpdate => _operationCodes.contains(opItemUpdate);

  /// 是否拥有「删除指导建议项目」权限。
  bool get canItemDelete => _operationCodes.contains(opItemDelete);

  // ---------------- 加载 ----------------

  /// 加载模板与操作权限（进入页面时调用）。每次调用都强制重拉，选中
  /// 项按 ID 刷新引用，右侧项目随选中项重拉。
  Future<bool> loadData() async {
    _loading = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _refreshPermissions();
      final templates = await _service.queryTemplates();
      _templates
        ..clear()
        ..addAll(templates);
      final selectedId = _selected?.id;
      if (selectedId != null) {
        _selected = _findTemplate(selectedId);
      }
      if (_selected == null) {
        _items.clear();
      } else {
        await _refreshItems();
      }
      _loaded = true;
      return true;
    } catch (e, st) {
      LogHelper.error('client:GuidanceTemplateManagementViewModel.loadData', e, st);
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

  /// 拉取选中模板的全部项目。
  Future<void> _refreshItems() async {
    final selectedId = _selected?.id;
    if (selectedId == null) {
      _items.clear();
      return;
    }
    final items = await _service.queryItems(selectedId);
    _items
      ..clear()
      ..addAll(items);
  }

  // ---------------- 模板交互 ----------------

  /// 选中左侧模板（右侧加载其项目列表）。
  Future<void> selectTemplate(BaseGuidanceTemplate template) async {
    if (_selected?.id == template.id) return;
    _selected = template;
    _itemsLoading = true;
    notifyListeners();
    try {
      await _refreshItems();
    } catch (e, st) {
      LogHelper.error('client:GuidanceTemplateManagementViewModel.selectTemplate', e, st);
      _errorMsg = _messageOf(e);
    } finally {
      _itemsLoading = false;
      notifyListeners();
    }
  }

  /// 手动重拉选中模板的项目列表（右栏【刷新】按钮；无选中项时为空操作）。
  Future<void> refreshItems() async {
    if (_selected == null || _itemsLoading || _itemBusy) return;
    _itemsLoading = true;
    notifyListeners();
    try {
      await _refreshItems();
    } catch (e, st) {
      LogHelper.error('client:GuidanceTemplateManagementViewModel.refreshItems', e, st);
      _errorMsg = _messageOf(e);
    } finally {
      _itemsLoading = false;
      notifyListeners();
    }
  }

  /// 新增模板，成功后整表重拉并选中新模板。
  Future<bool> createTemplate({required String templateName, int? displayOrder}) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final created = await _service.createTemplate(templateName: templateName, displayOrder: displayOrder);
      final templates = await _service.queryTemplates();
      _templates
        ..clear()
        ..addAll(templates);
      _selected = _findTemplate(created.id) ?? created;
      await _refreshItems();
      return true;
    } catch (e, st) {
      LogHelper.error('client:GuidanceTemplateManagementViewModel.createTemplate', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 修改模板（changes 键同后端契约：templateName / displayOrder），
  /// 成功后整表重拉并刷新选中项引用。
  Future<bool> updateTemplate(String id, Map<String, Object?> changes) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _service.updateTemplate(id, changes);
      final templates = await _service.queryTemplates();
      _templates
        ..clear()
        ..addAll(templates);
      _selected = _findTemplate(id);
      return true;
    } catch (e, st) {
      LogHelper.error('client:GuidanceTemplateManagementViewModel.updateTemplate', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 删除模板（服务端连带删除其全部项目），成功后整表重拉；删除选中
  /// 项时右侧回退空态。
  Future<bool> deleteTemplate(BaseGuidanceTemplate template) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _service.deleteTemplate(template.id);
      if (_selected?.id == template.id) {
        _selected = null;
        _items.clear();
      }
      final templates = await _service.queryTemplates();
      _templates
        ..clear()
        ..addAll(templates);
      return true;
    } catch (e, st) {
      LogHelper.error('client:GuidanceTemplateManagementViewModel.deleteTemplate', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ---------------- 项目交互 ----------------

  /// 新增指导建议项目，成功后重拉项目列表。
  Future<bool> createItem({
    required String templateId,
    String? guidanceType,
    required String guidance,
    required String isPersonal,
  }) async {
    _itemBusy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _service.createItem(templateId: templateId, guidanceType: guidanceType, guidance: guidance, isPersonal: isPersonal);
      await _refreshItems();
      return true;
    } catch (e, st) {
      LogHelper.error('client:GuidanceTemplateManagementViewModel.createItem', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _itemBusy = false;
      notifyListeners();
    }
  }

  /// 修改指导建议项目（changes 键同后端契约：guidanceType / guidance /
  /// isPersonal），成功后重拉项目列表。
  Future<bool> updateItem(String id, Map<String, Object?> changes) async {
    _itemBusy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _service.updateItem(id, changes);
      await _refreshItems();
      return true;
    } catch (e, st) {
      LogHelper.error('client:GuidanceTemplateManagementViewModel.updateItem', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _itemBusy = false;
      notifyListeners();
    }
  }

  /// 删除指导建议项目，成功后重拉项目列表。
  Future<bool> deleteItem(BaseGuidanceTemplateItem item) async {
    _itemBusy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _service.deleteItem(item.id);
      await _refreshItems();
      return true;
    } catch (e, st) {
      LogHelper.error('client:GuidanceTemplateManagementViewModel.deleteItem', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _itemBusy = false;
      notifyListeners();
    }
  }

  // ---------------- 通用 ----------------

  /// 按 ID 在已加载列表中查找（不存在返回 null）。
  BaseGuidanceTemplate? _findTemplate(String id) {
    for (final template in _templates) {
      if (template.id == id) return template;
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
