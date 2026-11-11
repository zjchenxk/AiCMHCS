import 'package:client/main.dart' as app;
import 'package:client/models/child_info.dart';
import 'package:client/models/menu_item.dart';
import 'package:client/services/account_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:client/utils/menu_icons.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

class MainViewModel extends ChangeNotifier {
  /// 可选注入账户服务（便于测试替换）；为空时运行期经 getIt 解析。
  MainViewModel({AccountService? accountService}) : _accountService = accountService;

  final AccountService? _accountService;
  // 登录用户角色
  List<Map<String, String>> _roles = const [];
  List<Map<String, String>> get roles => _roles;

  void setRoles(List<Map<String, String>> roles) {
    _roles = roles;
    notifyListeners();
  }

  // 登录用户信息（登录前为空占位，登录成功后经 syncLoginUser 刷新为真实身份；
  // 医院/院区/科室均为登录接口关联下发的真实数据，未设置的字段保持 null，
  // 由界面按需隐藏对应展示项）
  LoginUser loginUser = const LoginUser(
    id: 0,
    userCode: '',
    userName: '',
    userType: '',
    roleId: '',
  );

  /// 登录成功后以全局 loginUser 刷新工作副本
  void syncLoginUser() {
    final user = app.loginUser;
    if (user == null) return;
    loginUser = user;
    notifyListeners();
  }

  // 儿童信息（示例数据，实际可从接口获取）
  ChildInfo child = ChildInfo(
    cardNo: 'JZK202601001',
    patientId: 'P00012345',
    name: '王小明',
    gender: '男',
    birthDate: DateTime(2024, 3, 15),
    gestationalWeek: '38+2',
    actualAge: '12岁10月20天',
    correctedAge: '12岁11月10天',
    phone: '13800138000',
  );

  // 功能菜单（登录成功后经 setRoleMenus 以所选角色的权限菜单构建，
  // 数据源为登录响应下发的 SYS_ROLE_PERMISSION ∩ SYS_MENU 可见模块/菜单）
  List<MenuItem> _menus = const [];
  List<MenuItem> get menus => _menus;

  /// 以登录响应下发的角色菜单构建侧边栏树：模块（ITEM_TYPE=1）为一级
  /// 项目、菜单（ITEM_TYPE=2）挂其下，各层按 ITEM_CODE 排序；上级模块
  /// 未授权的散落菜单兜底挂根级（权限数据异常时不丢失入口）。图标经
  /// iconMap 解析、查不到按项目类型回退，与角色管理权限树同一套规则。
  void setRoleMenus(List<Menu> roleMenus) {
    final sorted = [...roleMenus]..sort((a, b) => a.itemCode.compareTo(b.itemCode));

    final hasParent = <String>{};
    for (final m in sorted) {
      final p = m.parentId?.trim() ?? '';
      if (p.isNotEmpty) hasParent.add(m.id);
    }

    final childrenByParent = <String, List<MenuItem>>{};
    for (final m in sorted) {
      final p = m.parentId?.trim() ?? '';
      if (p.isEmpty) continue;
      childrenByParent.putIfAbsent(p, () => []).add(_menuToItem(m));
    }

    // 顶层 = 没有 parentId 的项（无论 itemType），按编码顺序输出
    final result = <MenuItem>[];
    for (final m in sorted) {
      final p = m.parentId?.trim() ?? '';
      if (p.isEmpty) {
        result.add(_menuToItem(m, childrenByParent[m.id] ?? []));
      }
    }

    _menus = result;
    // 菜单集已整体更换：清空选中项、展开态与搜索过滤缓存
    _selectedMenuId = null;
    _breadcrumbs = [];
    _expandedIds.clear();
    _filterCacheKey = '';
    _cachedFilteredMenus = null;
    notifyListeners();
  }

  /// 数据库菜单项目转侧边栏菜单项（图标名解析失败时按项目类型回退）。
  MenuItem _menuToItem(Menu menu, [List<MenuItem> children = const []]) => MenuItem(
    id: menu.id,
    title: menu.itemName,
    icon: menuIconOrFallback(menu.menuIcon, fallback: menuItemTypeIcon(menu.itemType)),
    route: menu.menuRoute,
    children: children,
  );

  // 状态
  String? _selectedMenuId;
  String? get selectedMenuId => _selectedMenuId;

  String? get selectedMenuTitle {
    for (final m in menus) {
      if (m.id == _selectedMenuId) return m.title;
      for (final c in m.children) {
        if (c.id == _selectedMenuId) return c.title;
      }
    }
    return null;
  }

  List<String> _breadcrumbs = [];
  List<String> get breadcrumbs => _breadcrumbs;

  String _searchKeyword = '';
  String get searchKeyword => _searchKeyword;

  String _filterCacheKey = ''; // 上次计算时使用的关键词
  List<MenuItem>? _cachedFilteredMenus; // 上次过滤的结果

  bool _collapsed = false;
  bool get collapsed => _collapsed;

  final Set<String> _expandedIds = {};

  String get userName => loginUser.userName;

  /// 当前登录角色名称（从该用户拥有的角色列表按当前角色 ID 解析；
  /// 列表未加载、角色 ID 为空或不在列表中时为 null，界面按需隐藏。
  /// 切换角色后 loginUser 已整体替换，本 getter 随新 roleId 解析新名称）
  String? get roleName {
    final roleId = loginUser.roleId;
    if (roleId.isEmpty) return null;
    for (final role in _roles) {
      if (role['id'] == roleId) return role['roleName'];
    }
    return null;
  }

  // 方法
  void selectMenu(MenuItem menu, List<String> path) {
    _selectedMenuId = menu.id;
    _breadcrumbs = path;
    notifyListeners();
  }

  void setSearchKeyword(String keyword) {
    _searchKeyword = keyword;
    if (keyword.isNotEmpty) _collectParentIds(menus);
    notifyListeners();
  }

  void toggleCollapse() {
    _collapsed = !_collapsed;
    notifyListeners();
  }

  void toggleExpand(String menuId) {
    _expandedIds.contains(menuId) ? _expandedIds.remove(menuId) : _expandedIds.add(menuId);
    notifyListeners();
  }

  bool isExpanded(String menuId) => _expandedIds.contains(menuId);

  List<MenuItem> get filteredMenus {
    // 关键词没变 → 直接返回缓存，不再递归过滤
    if (_filterCacheKey == _searchKeyword && _cachedFilteredMenus != null) {
      return _cachedFilteredMenus!;
    }
    // 关键词变了 → 重新计算并更新缓存
    _filterCacheKey = _searchKeyword;
    _cachedFilteredMenus = _searchKeyword.isEmpty ? menus : _filterMenus(menus, _searchKeyword);
    return _cachedFilteredMenus!;
  }

  List<MenuItem> _filterMenus(List<MenuItem> menus, String keyword) {
    final result = <MenuItem>[];
    for (final menu in menus) {
      final children = _filterMenus(menu.children, keyword);
      if (menu.title.contains(keyword) || children.isNotEmpty) {
        result.add(
          MenuItem(
            id: menu.id,
            title: menu.title,
            icon: menu.icon,
            children: children,
          ),
        );
      }
    }
    return result;
  }

  void _collectParentIds(List<MenuItem> menus) {
    for (final menu in menus) {
      if (menu.children.isNotEmpty) {
        _expandedIds.add(menu.id);
        _collectParentIds(menu.children);
      }
    }
  }

  MenuItem? findMenuById(String? id) {
    if (id == null) return null;

    MenuItem? find(List<MenuItem> list) {
      for (final m in list) {
        if (m.id == id) return m;
        final r = find(m.children);
        if (r != null) return r;
      }
      return null;
    }

    return find(menus);
  }

  // 切换角色
  bool _switchingRole = false;
  bool get switchingRole => _switchingRole;

  String? _errorMsg;
  String? get errorMsg => _errorMsg;

  /// 切换角色：调后端校验目标角色归属并更新会话角色，成功后以响应下发
  /// 的用户信息与角色权限菜单刷新全局登录用户与侧边栏（菜单集整体更换，
  /// 选中/展开/搜索态由 setRoleMenus 清空）。
  ///param roleId: 目标角色 ID
  ///returns: 是否切换成功（失败时 errorMsg 带提示，原会话与菜单不变）
  Future<bool> switchRole(String roleId) async {
    if (_switchingRole) return false;
    _switchingRole = true;
    _errorMsg = null;
    notifyListeners();

    try {
      final service = _accountService ?? app.getIt<AccountService>();
      final result = await service.switchRole(roleId);

      // 更新全局登录用户（携带新角色 ID，供主界面信息栏与各业务页取用）
      app.loginUser = result.user;
      // 以全局值同步工作副本——替换整个实例而非改字段，否则
      // Selector<MainViewModel, LoginUser> 因引用未变不会刷新顶部显示
      loginUser = result.user;

      // 以新角色下发的菜单重建侧边栏
      setRoleMenus(result.menus);

      return true;
    } catch (e, st) {
      LogHelper.error('client:MainViewModel.switchRole', e, st);
      _errorMsg = e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');
      return false;
    } finally {
      _switchingRole = false;
      notifyListeners();
    }
  }

  /// 重新登录前的状态清理
  void resetForRelogin() {
    _selectedMenuId = null;
    _breadcrumbs = [];
    _searchKeyword = '';
    _filterCacheKey = '';
    _cachedFilteredMenus = null;
    _expandedIds.clear();
    _collapsed = false;
    _menus = const [];
    notifyListeners();
  }

  /// 打开帮助中心（伪菜单 id，不出现在侧边栏，仅驱动内容区）
  void openHelpCenter() {
    _selectedMenuId = 'help-center';
    _breadcrumbs = ['帮助中心'];
    notifyListeners();
  }
}
