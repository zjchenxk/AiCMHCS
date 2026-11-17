import 'package:client/main.dart' as app;
import 'package:client/models/current_child.dart';
import 'package:client/models/menu_item.dart';
import 'package:client/services/account_service.dart';
import 'package:client/services/child_service.dart';
import 'package:client/services/time_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:client/utils/menu_icons.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

class MainViewModel extends ChangeNotifier {
  /// 可选注入账户/儿童服务（便于测试替换）；为空时运行期经 getIt 解析。
  MainViewModel({AccountService? accountService, ChildService? childService}) : _accountService = accountService, _childService = childService;

  final AccountService? _accountService;

  final ChildService? _childService;
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
    id: '',
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

  // 当前儿童上下文（默认空占位；主界面顶部搜索框精确检索选中后写入，
  // 随 BasePage 分发到各功能页，儿童建档页据此自动载入整档）
  // 未选定儿童时的空占位（epoch 0 明确「无值」语义；占位值从不参与
  // 年龄计算与展示，选定真实档案后经 setCurrentChild 整体覆盖）
  CurrentChild child = CurrentChild(
    visitCardNo: '',
    patientId: '',
    name: '',
    gender: '',
    birthDate: DateTime.fromMillisecondsSinceEpoch(0),
    phone: '',
  );

  /// 是否已选定当前儿童（id 非空即视为已选定）。
  bool get hasCurrentChild => child.id.isNotEmpty;

  /// 顶部搜索框精确检索儿童（姓名/就诊卡号/证件号码/电话号码任一精确
  /// 命中，服务端按医院隔离并解密下发）。
  ///param keyword: 搜索关键词（同一关键词同时投给多个条件）
  ///returns: 命中的儿童简要档案列表；接口失败时抛出原异常（调用方提示）
  Future<List<ChildInfo>> searchChildren(String keyword) async {
    final kw = keyword.trim();
    final service = _childService ?? app.getIt<ChildService>();
    return service.search(name: kw, visitCardNo: kw, certificateNo: kw, phone: kw);
  }

  /// 将选中的儿童档案写入当前儿童上下文（显示字段由档案字段映射，
  /// 实际年龄按出生日期实时计算）。
  ///param info: 检索/保存得到的儿童档案（服务端已解密的明文）
  void setCurrentChild(ChildInfo info) {
    final birth = DateTime.tryParse(info.birthDate) ?? DateTime.fromMillisecondsSinceEpoch(0);
    child = CurrentChild(
      id: info.id,
      visitCardNo: info.visitCardNo ?? '',
      patientId: info.patientId ?? '',
      name: info.name,
      gender: switch (info.sex) {
        '1' => '男',
        '2' => '女',
        _ => '',
      },
      birthDate: birth,
      actualAge: _formatAge(birth),
      phone: info.phone ?? '',
    );
    notifyListeners();
  }

  /// 当前时间（全局时间服务口径，见 time_service.dart）。
  static DateTime _now() => app.getIt<TimeService>().now();

  /// 按出生日期格式化实际年龄（x岁/x岁y个月/y个月，未满月为 0个月）。
  String _formatAge(DateTime birth) {
    // 「现在」取全局时间服务（服务端口径），避免终端本地时钟不一致
    // 影响实际年龄展示
    final now = _now();
    var months = (now.year - birth.year) * 12 + now.month - birth.month;
    if (now.day < birth.day) months--;
    if (months < 0) months = 0;
    final years = months ~/ 12;
    final rest = months % 12;
    if (years > 0) {
      return rest > 0 ? '$years岁$rest个月' : '$years岁';
    }
    return '$rest个月';
  }

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
    child = CurrentChild(
      visitCardNo: '',
      patientId: '',
      name: '',
      gender: '',
      birthDate: DateTime.fromMillisecondsSinceEpoch(0),
      phone: '',
    );
    notifyListeners();
  }

  /// 打开帮助中心（伪菜单 id，不出现在侧边栏，仅驱动内容区）
  void openHelpCenter() {
    _selectedMenuId = 'help-center';
    _breadcrumbs = ['帮助中心'];
    notifyListeners();
  }
}
