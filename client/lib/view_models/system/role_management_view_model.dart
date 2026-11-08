import 'package:client/main.dart';
import 'package:client/models/menu_tree_node.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/services/role_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 角色管理 ViewModel：角色归属当前登录用户的所属医院（hospId）。
/// 左侧为该医院的角色列表（增删改经表单对话框与确认对话框发起）；
/// 右侧为选中角色的菜单权限树——数据来自菜单管理全量列表、按
/// ITEM_CODE 逐级排序，勾选级联（勾/取消父项目连带整棵子树，父项目
/// 复选框按后代勾选情况显示全选/半选三态），支持全选/取消全选与
/// 整体保存（后端全量覆盖）。
///
/// 增删与保存成功后按需重拉对应数据，选中角色与展开状态尽量保留。
/// 每次进入页面 loadData 都强制重拉——菜单管理等兄弟页面可能已改动
/// 菜单数据，跳过缓存才能保证切回时权限树一致。
class RoleManagementViewModel extends ChangeNotifier {
  /// 构造函数：注入角色与菜单服务（缺省从服务定位器取，测试可覆写）。
  RoleManagementViewModel({RoleService? roleService, MenuService? menuService}) : _roleService = roleService ?? getIt<RoleService>(), _menuService = menuService ?? getIt<MenuService>();

  final RoleService _roleService;
  final MenuService _menuService;

  final List<Role> _roles = [];
  final List<Menu> _menus = [];
  final List<MenuTreeNode> _menuRoots = [];
  String? _hospId;
  bool _loaded = false;
  Role? _selectedRole;
  bool _loading = false;
  bool _busy = false;
  bool _permLoading = false;
  bool _permBusy = false;
  String? _errorMsg;

  /// 已勾选（含半选父项目代表的「目标全量」语义：勾选即整棵子树
  /// 全在集合内）的菜单 ID 集合。
  final Set<String> _checkedIds = {};

  /// 最近一次加载/保存成功的勾选集合（脏检查基线）。
  Set<String> _savedIds = {};

  /// 当前医院的角色列表（按创建顺序）。
  List<Role> get roles => _roles;

  /// 当前选中角色（左侧列表高亮、右侧权限面板目标）。
  Role? get selectedRole => _selectedRole;

  /// 首屏加载中。
  bool get loading => _loading;

  /// 角色增删改操作进行中（防重复提交）。
  bool get busy => _busy;

  /// 选中角色的权限加载中。
  bool get permLoading => _permLoading;

  /// 权限保存进行中（防重复提交）。
  bool get permBusy => _permBusy;

  String? get errorMsg => _errorMsg;

  /// 当前绑定的医院 ID（未加载为 null）。
  String? get hospId => _hospId;

  /// 登录用户未设置所属医院（页面据此显示引导提示而非空列表）。
  bool get unbound => _loaded && (_hospId == null || _hospId!.isEmpty);

  /// 菜单权限树根节点列表（逐级按 ITEM_CODE 排序；未加载为空）。
  List<MenuTreeNode> get menuRoots => _menuRoots;

  /// 已加载且库中无任何菜单项目（右侧显示空态引导）。
  bool get menuEmpty => _loaded && _menus.isEmpty;

  /// 当前勾选是否已保存（无勾选变更时保存按钮置灰）。
  bool get permDirty => _selectedRole != null && !_permLoading && !_setEquals(_checkedIds, _savedIds);

  /// 是否已全选（全部菜单项目均勾选；无菜单视为否）。
  bool get allChecked => _menus.isNotEmpty && _checkedIds.containsAll(_menus.map((m) => m.id));

  /// 勾选中的菜单数量（面板头计数展示）。
  int get checkedCount => _checkedIds.length;

  // ---------------- 加载 ----------------

  /// 加载登录用户所属医院的角色与菜单全量列表（进入页面时调用）。
  ///
  /// hospId 为空视为未绑定：清空列表并置提示；每次调用都强制重拉
  /// （兄弟页面可能已改动数据，切回本页须重新拉取），选中角色与
  /// 展开/勾选状态尽量保留（勾选按现存菜单过滤，防悬空 ID）。
  Future<bool> loadData(String? hospId) async {
    final h = hospId?.trim() ?? '';

    _hospId = h;
    if (h.isEmpty) {
      _loaded = true;
      _roles.clear();
      _selectedRole = null;
      _checkedIds.clear();
      _savedIds = {};
      _errorMsg = '当前登录用户未设置所属医院，无法管理角色';
      notifyListeners();
      return false;
    }

    _loading = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _refreshRoles();
      await _refreshMenus();
      _loaded = true;
      return true;
    } catch (e, st) {
      LogHelper.error('client:RoleManagementViewModel.loadData', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 重拉当前医院的全量角色（选中角色被删时回退空态并清权限）。
  Future<void> _refreshRoles() async {
    final roles = await _roleService.getByHospital(_hospId!);
    _roles
      ..clear()
      ..addAll(roles);
    final selectedId = _selectedRole?.id;
    if (selectedId != null) {
      _selectedRole = _findById(selectedId);
      if (_selectedRole == null) {
        _checkedIds.clear();
        _savedIds = {};
      }
    }
  }

  /// 重拉菜单全量列表并重建权限树（逐级按 ITEM_CODE 排序，展开状态
  /// 保留）；勾选集合过滤为仅现存菜单（菜单管理删项后防悬空勾选）。
  Future<void> _refreshMenus() async {
    final menus = await _menuService.queryAll();
    _menus
      ..clear()
      ..addAll(menus);
    final old = List<MenuTreeNode>.from(_menuRoots);
    _menuRoots
      ..clear()
      ..addAll(_buildTree(old));

    // 过滤悬空勾选（指向已删除菜单的 ID 不再参与保存）
    final knownIds = _menus.map((m) => m.id).toSet();
    _checkedIds.retainAll(knownIds);
    _savedIds = _savedIds.intersection(knownIds);
  }

  /// 由扁平列表组树（old 为重建前的旧根列表，保留展开状态；每级
  /// 子项按 ITEM_CODE 排序，顶级同为多根列表）。
  List<MenuTreeNode> _buildTree(List<MenuTreeNode> old) {
    int compare(Menu a, Menu b) => a.itemCode.compareTo(b.itemCode);
    MenuTreeNode buildNode(Menu menu) {
      final node = MenuTreeNode(
        id: menu.id,
        menu: menu,
        expanded: _findByKey(old, 'menu:${menu.id}')?.expanded ?? true,
      );
      final children = _menus.where((m) => m.id != menu.id && m.parentId == menu.id).toList()..sort(compare);
      for (final child in children) {
        node.children.add(buildNode(child));
      }
      return node;
    }

    final roots = _menus.where((m) => m.parentId == null || m.parentId!.isEmpty).toList()..sort(compare);
    return roots.map(buildNode).toList();
  }

  /// 在根列表中递归查找节点（按键）。
  MenuTreeNode? _findByKey(List<MenuTreeNode> roots, String key) {
    for (final root in roots) {
      final hit = root.findByKey(key);
      if (hit != null) return hit;
    }
    return null;
  }

  /// 在列表中按 ID 查找角色。
  Role? _findById(String id) {
    for (final r in _roles) {
      if (r.id == id) return r;
    }
    return null;
  }

  // ---------------- 交互 ----------------

  /// 选中角色并加载其菜单权限（左侧列表点击）。
  Future<void> selectRole(Role role) async {
    if (_selectedRole?.id == role.id) return;
    _selectedRole = role;
    _checkedIds.clear();
    _savedIds = {};
    _permLoading = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final menuIds = await _roleService.queryPermissionMenuIds(role.id);
      // 仅保留现存菜单（历史勾选的菜单被删后不再展示/保存）
      final knownIds = _menus.map((m) => m.id).toSet();
      final valid = menuIds.where(knownIds.contains).toSet();
      _checkedIds
        ..clear()
        ..addAll(valid);
      _savedIds = {...valid};
    } catch (e, st) {
      LogHelper.error('client:RoleManagementViewModel.selectRole', e, st);
      _errorMsg = _messageOf(e);
    } finally {
      _permLoading = false;
      notifyListeners();
    }
  }

  /// 切换节点复选框：整棵子树级联勾选/取消（父项目半选时点击视为
  /// 全选该子树）。
  void toggleNodeCheck(MenuTreeNode node) {
    final target = nodeCheckState(node) != true;
    node.visit((n) {
      if (target) {
        _checkedIds.add(n.id);
      } else {
        _checkedIds.remove(n.id);
      }
    });
    notifyListeners();
  }

  /// 节点勾选三态：true 全选（自身与全部后代均已勾）、false 全不选、
  /// null 半选（部分勾选）。
  bool? nodeCheckState(MenuTreeNode node) {
    var all = true;
    var none = true;
    node.visit((n) {
      if (_checkedIds.contains(n.id)) {
        none = false;
      } else {
        all = false;
      }
    });
    if (all) return true;
    if (none) return false;
    return null;
  }

  /// 全选/取消全选（针对全部菜单项目；无选中角色时不可用）。
  void toggleCheckAll() {
    if (allChecked) {
      _checkedIds.clear();
    } else {
      _checkedIds.addAll(_menus.map((m) => m.id));
    }
    notifyListeners();
  }

  /// 切换节点展开/折叠。
  void toggleExpand(MenuTreeNode node) {
    node.expanded = !node.expanded;
    notifyListeners();
  }

  // ---------------- 增删改 ----------------

  /// 新增角色到登录用户所属医院，成功后重拉列表并选中新角色（权限
  /// 为空，待右侧勾选保存）。
  Future<bool> createRole({
    required String roleCode,
    required String roleName,
    String? remark,
  }) async {
    final hospId = _hospId;
    if (hospId == null || hospId.isEmpty) return false;
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final created = await _roleService.create(
        hospId: hospId,
        roleCode: roleCode,
        roleName: roleName,
        remark: remark,
      );
      await _refreshRoles();
      _selectedRole = _findById(created.id);
      _checkedIds.clear();
      _savedIds = {};
      return true;
    } catch (e, st) {
      LogHelper.error('client:RoleManagementViewModel.createRole', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 修改角色（changes 键同后端契约：roleCode/roleName/remark；归属
  /// 医院不可改），成功后重拉列表。
  Future<bool> updateRole(String id, Map<String, Object?> changes) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final updated = await _roleService.update(id, changes);
      await _refreshRoles();
      _selectedRole = _findById(updated.id);
      return true;
    } catch (e, st) {
      LogHelper.error('client:RoleManagementViewModel.updateRole', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 删除角色（后端连带清空其权限关联），成功后重拉列表；删除选中
  /// 角色时回退空态。
  Future<bool> deleteRole(Role role) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _roleService.delete(role.id);
      await _refreshRoles();
      return true;
    } catch (e, st) {
      LogHelper.error('client:RoleManagementViewModel.deleteRole', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 保存选中角色的菜单权限（全量覆盖），成功后以当前勾选为已保存
  /// 基线。
  Future<bool> savePermissions() async {
    final role = _selectedRole;
    if (role == null) return false;
    _permBusy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      // 按菜单列表顺序输出，报文稳定便于排查
      final menuIds = _menus.map((m) => m.id).where(_checkedIds.contains).toList(growable: false);
      await _roleService.savePermissionMenuIds(role.id, menuIds);
      _savedIds = {..._checkedIds};
      return true;
    } catch (e, st) {
      LogHelper.error('client:RoleManagementViewModel.savePermissions', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _permBusy = false;
      notifyListeners();
    }
  }

  // ---------------- 通用 ----------------

  /// 集合相等（脏检查用）。
  bool _setEquals(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

  /// 剥离异常前缀（Exception(: ...)），取用户可读信息。
  String _messageOf(Object e) => e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');

  void clearError() {
    _errorMsg = null;
    notifyListeners();
  }
}
