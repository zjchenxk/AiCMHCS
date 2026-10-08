import 'package:client/models/child_info.dart';
import 'package:client/models/login_user.dart';
import 'package:client/models/menu_item.dart';
import 'package:material_ui/material_ui.dart';

class MainViewModel extends ChangeNotifier {
  // 科室（示例数据，实际从接口获取）
  final List<(String, String)> availableDepts = const [
    ('D001', '儿童保健科'),
    ('D002', '儿童心理科'),
    ('D003', '康复科'),
    ('D004', '新生儿科'),
    ('D005', '产科'),
  ];

  // 登录用户信息（示例数据，实际可从接口获取）
  LoginUser loginUser = LoginUser(
    userId: 'U001',
    userCode: '0001',
    userName: '张医生',
    password: '123456',
    organId: 'O001',
    organName: '首都医科大学附属北京儿童医院',
    branchId: 'B001',
    branchName: '顺义院区',
    deptId: 'D001',
    deptName: '儿童保健科',
  );

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

  // 功能菜单
  final List<MenuItem> menus = const [
    MenuItem(id: 'home', title: '首页', icon: Icons.home_outlined, route: '/home'),
    MenuItem(
      id: 'children',
      title: '儿童管理',
      icon: Icons.child_care,
      children: [
        MenuItem(id: 'children-build', title: '儿童建档', icon: Icons.folder_open),
        MenuItem(id: 'children-photo', title: '儿童拍照', icon: Icons.camera_alt_outlined),
      ],
    ),
    MenuItem(
      id: 'intelligence',
      title: '智力测验',
      icon: Icons.psychology_outlined,
      children: [
        MenuItem(id: 'raven', title: '瑞文测验', icon: Icons.grid_on_outlined),
        MenuItem(id: 'wisc', title: '韦氏测验', icon: Icons.calculate_outlined),
      ],
    ),
    MenuItem(
      id: 'neuro',
      title: '神经运动测查',
      icon: Icons.accessibility_new,
      children: [
        MenuItem(id: 'nbna', title: 'NBNA', icon: Icons.monitor_heart_outlined),
        MenuItem(id: 'pdms', title: 'PDMS', icon: Icons.directions_run),
      ],
    ),
    MenuItem(
      id: 'development',
      title: '发育测查',
      icon: Icons.trending_up,
      children: [
        MenuItem(id: 'asq3', title: 'ASQ-3', icon: Icons.quiz_outlined),
        MenuItem(id: 'ddst', title: '丹佛DDST', icon: Icons.checklist),
      ],
    ),
    MenuItem(
      id: 'behavior',
      title: '行为测评',
      icon: Icons.emoji_emotions_outlined,
      children: [
        MenuItem(id: 'abc', title: 'ABC', icon: Icons.assignment_outlined),
        MenuItem(id: 'mchat', title: 'M-CHAT', icon: Icons.chat_bubble_outline),
      ],
    ),
    MenuItem(
      id: 'system',
      title: '系统管理',
      icon: Icons.settings_outlined,
      children: [
        MenuItem(id: 'hospital', title: '医院设置', icon: Icons.local_hospital_outlined, route: '/system/organ'),
        MenuItem(id: 'campus', title: '院区设置', icon: Icons.domain_outlined),
        MenuItem(id: 'department', title: '科室设置', icon: Icons.meeting_room_outlined),
        MenuItem(id: 'staff', title: '人员设置', icon: Icons.people_outline),
        MenuItem(id: 'permission', title: '权限设置', icon: Icons.lock_outline),
      ],
    ),
  ];

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

  String get userName => '张医生';

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

  /// 切换科室替换整个 loginUser 实例（而非改字段），
  /// 否则 Selector&lt;MainViewModel, LoginUser&gt; 因引用未变不会刷新顶部科室显示
  void switchDepartment(String deptId, String deptName) {
    loginUser = loginUser.copyWith(deptId: deptId, deptName: deptName);
    notifyListeners();
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
    notifyListeners();
  }

  /// 打开帮助中心（伪菜单 id，不出现在侧边栏，仅驱动内容区）
  void openHelpCenter() {
    _selectedMenuId = 'help-center';
    _breadcrumbs = ['帮助中心'];
    notifyListeners();
  }
}
