import 'package:client/main.dart';
import 'package:client/models/user_tree_node.dart';
import 'package:client/services/department_service.dart';
import 'package:client/services/role_service.dart';
import 'package:client/services/user_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 用户管理右侧表单形态：空态 / 编辑选中用户 / 在某科室下新增。
enum UserFormMode { empty, edit, create }

/// 用户管理 ViewModel：用户归属当前登录用户的所属医院（hospId）。
/// 左侧为「科室 → 下级科室 → 用户」树（科室来自科室管理、用户挂其
/// DEPT_ID 对应科室下，未挂科室的收入「未分配科室」虚拟节点）；医院
/// 尚未设置任何科室时左侧显示引导提示（未添加科室，不能新增用户）。
/// 右侧为选中用户的信息表单（含角色多选，角色来自本医院的角色列表）
/// 或在某科室下新增用户的表单。
///
/// 增改成功后重拉用户列表并重建树，选中用户与展开状态尽量保留。
/// 每次进入页面 loadData 都强制重拉——科室管理、角色管理等兄弟页面
/// 可能已改动数据，跳过缓存才能保证切回时树一致。
class UserManagementViewModel extends ChangeNotifier {
  /// 构造函数：注入用户、科室与角色服务（缺省从服务定位器取，测试可覆写）。
  UserManagementViewModel({
    UserService? userService,
    DepartmentService? departmentService,
    RoleService? roleService,
  }) : _userService = userService ?? getIt<UserService>(),
       _departmentService = departmentService ?? getIt<DepartmentService>(),
       _roleService = roleService ?? getIt<RoleService>();

  final UserService _userService;
  final DepartmentService _departmentService;
  final RoleService _roleService;

  /// 「未分配科室」虚拟节点 ID（DEPT_ID 为空或科室已删除的用户收入
  /// 此节点，只读、不可在其下新增）。
  static const String unassignedId = '__unassigned';

  final List<Department> _departments = [];
  final List<User> _users = [];
  final List<Role> _roles = [];
  final List<UserTreeNode> _roots = [];
  String? _hospId;
  bool _loaded = false;
  User? _selectedUser;
  UserTreeNode? _createParent;
  bool _creating = false;
  bool _loading = false;
  bool _busy = false;
  String? _errorMsg;

  /// 表单当前勾选的角色 ID 集合（新增/保存时的目标全量）。
  final Set<String> _checkedRoleIds = {};

  /// 当前医院的科室列表（扁平）。
  List<Department> get departments => _departments;

  /// 当前医院的用户列表（扁平，含各自角色 ID）。
  List<User> get users => _users;

  /// 当前医院的角色列表（多选数据源，按创建顺序）。
  List<Role> get roles => _roles;

  /// 左侧树根节点列表（顶级科室；含「未分配科室」虚拟节点时为末位根）。
  List<UserTreeNode> get roots => _roots;

  /// 当前选中用户（左侧树用户节点点击，右侧表单编辑目标）。
  User? get selectedUser => _selectedUser;

  /// 新增用户的目标挂载科室节点（department 非 null）。
  UserTreeNode? get createParent => _createParent;

  /// 首屏加载中。
  bool get loading => _loading;

  /// 用户新增/保存操作进行中（防重复提交）。
  bool get busy => _busy;

  String? get errorMsg => _errorMsg;

  /// 当前绑定的医院 ID（未加载为 null）。
  String? get hospId => _hospId;

  /// 登录用户未设置所属医院（页面据此显示引导提示而非空列表）。
  bool get unbound => _loaded && (_hospId == null || _hospId!.isEmpty);

  /// 已加载且医院尚未设置任何科室（左侧显示「未添加科室，不能新增
  /// 用户」，右侧表单不可新增）。
  bool get departmentEmpty => _loaded && _departments.isEmpty;

  /// 右侧表单形态：新增中为 create，选中用户为 edit，否则 empty。
  UserFormMode get formMode => _creating ? UserFormMode.create : (_selectedUser == null ? UserFormMode.empty : UserFormMode.edit);

  /// 表单当前勾选的角色 ID 集合。
  Set<String> get checkedRoleIds => _checkedRoleIds;

  // ---------------- 加载 ----------------

  /// 加载登录用户所属医院的科室、用户与角色（进入页面时调用）。
  ///
  /// hospId 为空视为未绑定：清空列表并置提示；每次调用都强制重拉
  /// （兄弟页面可能已改动数据，切回本页须重新拉取），选中用户与展开
  /// 状态尽量保留。
  Future<bool> loadData(String? hospId) async {
    final h = hospId?.trim() ?? '';

    _hospId = h;
    if (h.isEmpty) {
      _loaded = true;
      _clearAll();
      _errorMsg = '当前登录用户未设置所属医院，无法管理用户';
      notifyListeners();
      return false;
    }

    _loading = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final departments = await _departmentService.getByHospital(h);
      final users = await _userService.getByHospital(h);
      final roles = await _roleService.getByHospital(h);
      _departments
        ..clear()
        ..addAll(departments);
      _users
        ..clear()
        ..addAll(users);
      _roles
        ..clear()
        ..addAll(roles);
      _loaded = true;
      // 科室被兄弟页面清空后，新增/选中态已无挂载意义，一并回退
      if (departments.isEmpty) {
        _creating = false;
        _createParent = null;
        _selectedUser = null;
        _checkedRoleIds.clear();
      }
      _rebuildTree();
      _restoreSelection();
      return true;
    } catch (e, st) {
      LogHelper.error('client:UserManagementViewModel.loadData', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 清空全部业务状态（未绑定医院等场景）。
  void _clearAll() {
    _departments.clear();
    _users.clear();
    _roles.clear();
    _roots.clear();
    _selectedUser = null;
    _createParent = null;
    _creating = false;
    _checkedRoleIds.clear();
  }

  /// 由扁平列表重建「科室→下级科室→用户」树（展开状态保留；用户挂
  /// DEPT_ID 对应科室下，孤儿用户收入「未分配科室」虚拟节点）。
  void _rebuildTree() {
    final old = List<UserTreeNode>.from(_roots);

    UserTreeNode buildDeptNode(Department dept) {
      final node = UserTreeNode(
        type: UserTreeNodeType.department,
        id: dept.id,
        name: dept.name,
        department: dept,
        expanded: _findByKey(old, 'department:${dept.id}')?.expanded ?? true,
      );
      // 用户在前（叶子）、下级科室在后
      node.children.addAll(
        _users
            .where((u) => u.deptId == dept.id)
            .map(
              (u) => UserTreeNode(type: UserTreeNodeType.user, id: u.id, name: u.userName, user: u),
            ),
      );
      node.children.addAll(
        _departments.where((d) => d.parentId == dept.id).map(buildDeptNode),
      );
      return node;
    }

    _roots
      ..clear()
      ..addAll(_departments.where((d) => d.parentId == null || d.parentId!.isEmpty).map(buildDeptNode));

    // 孤儿用户：DEPT_ID 为空或指向已删除科室的，收入「未分配科室」
    final knownDeptIds = _departments.map((d) => d.id).toSet();
    final orphans = _users.where((u) => u.deptId == null || !knownDeptIds.contains(u.deptId)).toList();
    if (orphans.isNotEmpty) {
      _roots.add(
        UserTreeNode(
          type: UserTreeNodeType.department,
          id: unassignedId,
          name: '未分配科室',
          expanded: _findByKey(old, 'department:$unassignedId')?.expanded ?? true,
          children: orphans.map((u) => UserTreeNode(type: UserTreeNodeType.user, id: u.id, name: u.userName, user: u)).toList(),
        ),
      );
    }
  }

  /// 树重建后按 ID 恢复选中用户与新增挂载科室（找不到即回退）。
  void _restoreSelection() {
    final selectedId = _selectedUser?.id;
    if (selectedId != null) {
      _selectedUser = _findById(selectedId);
      if (_selectedUser == null) {
        _checkedRoleIds.clear();
      }
    }
    final parentKey = _createParent?.key;
    if (parentKey != null) {
      _createParent = _findByKey(_roots, parentKey);
      // 挂载科室被删或为虚拟节点时回退新增态
      if (_createParent?.department == null) {
        _creating = false;
        _createParent = null;
      }
    }
  }

  /// 在根列表中递归查找节点（按键）。
  UserTreeNode? _findByKey(List<UserTreeNode> roots, String key) {
    for (final root in roots) {
      final hit = root.findByKey(key);
      if (hit != null) return hit;
    }
    return null;
  }

  /// 在用户列表中按 ID 查找。
  User? _findById(String id) {
    for (final u in _users) {
      if (u.id == id) return u;
    }
    return null;
  }

  // ---------------- 交互 ----------------

  /// 选中用户并回显其角色（左侧树用户节点点击，右侧表单进入编辑态）。
  void selectUser(User user) {
    if (_selectedUser?.id == user.id && !_creating) return;
    _selectedUser = user;
    _creating = false;
    _createParent = null;
    _checkedRoleIds
      ..clear()
      ..addAll(user.roleIds);
    notifyListeners();
  }

  /// 在指定科室节点下新增用户（右侧表单切新增态；虚拟节点与用户节点
  /// 不可作为挂载目标）。
  void startCreate(UserTreeNode deptNode) {
    if (deptNode.department == null) return;
    _creating = true;
    _createParent = deptNode;
    _selectedUser = null;
    _checkedRoleIds.clear();
    notifyListeners();
  }

  /// 取消新增（右侧表单回空态）。
  void cancelCreate() {
    _creating = false;
    _createParent = null;
    notifyListeners();
  }

  /// 切换科室/用户节点展开折叠。
  void toggleExpand(UserTreeNode node) {
    node.expanded = !node.expanded;
    notifyListeners();
  }

  /// 切换角色勾选（表单角色多选）。
  void toggleRole(String roleId) {
    if (_checkedRoleIds.contains(roleId)) {
      _checkedRoleIds.remove(roleId);
    } else {
      _checkedRoleIds.add(roleId);
    }
    notifyListeners();
  }

  // ---------------- 增改 ----------------

  /// 新增用户到登录用户所属医院的指定科室，成功后重拉列表、重建树并
  /// 选中新用户（退出新增态）。
  Future<bool> createUser({
    required String userCode,
    required String userName,
    required String password,
    String? userType,
    String? permissionLevel,
    String? phone,
    String? idCardNo,
    String? hisUserCode,
    String? mchisUserCode,
    String? certId,
    String? signatureImage,
    String? status,
  }) async {
    final hospId = _hospId;
    final deptId = _createParent?.department?.id;
    if (hospId == null || hospId.isEmpty || deptId == null) return false;
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final created = await _userService.create(
        hospId: hospId,
        deptId: deptId,
        userCode: userCode,
        userName: userName,
        password: password,
        userType: userType,
        permissionLevel: permissionLevel,
        phone: phone,
        idCardNo: idCardNo,
        hisUserCode: hisUserCode,
        mchisUserCode: mchisUserCode,
        certId: certId,
        signatureImage: signatureImage,
        status: status,
        roleIds: _orderedCheckedRoleIds(),
      );
      await _refreshUsers();
      _creating = false;
      _createParent = null;
      _selectedUser = _findById(created.id);
      _checkedRoleIds
        ..clear()
        ..addAll(created.roleIds);
      return true;
    } catch (e, st) {
      LogHelper.error('client:UserManagementViewModel.createUser', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 修改选中用户（changes 键同后端契约；password 非空重置口令；角色
  /// 以表单当前勾选全量覆盖），成功后重拉列表并保持选中。
  Future<bool> updateUser(String id, Map<String, Object?> changes, {String? password}) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final updated = await _userService.update(
        id,
        changes,
        password: (password == null || password.trim().isEmpty) ? null : password,
        roleIds: _orderedCheckedRoleIds(),
      );
      await _refreshUsers();
      _selectedUser = _findById(updated.id);
      _checkedRoleIds
        ..clear()
        ..addAll(updated.roleIds);
      return true;
    } catch (e, st) {
      LogHelper.error('client:UserManagementViewModel.updateUser', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 重拉当前医院的用户列表并重建树（展开/选中状态保留）。
  Future<void> _refreshUsers() async {
    final users = await _userService.getByHospital(_hospId!);
    _users
      ..clear()
      ..addAll(users);
    _rebuildTree();
    _restoreSelection();
  }

  /// 按角色列表顺序输出勾选的角色 ID（报文稳定便于排查）。
  List<String> _orderedCheckedRoleIds() => _roles.map((r) => r.id).where(_checkedRoleIds.contains).toList(growable: false);

  // ---------------- 通用 ----------------

  /// 剥离异常前缀（Exception(: ...)），取用户可读信息。
  String _messageOf(Object e) => e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');

  void clearError() {
    _errorMsg = null;
    notifyListeners();
  }
}
