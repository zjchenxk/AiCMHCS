// 主界面切换角色接线测试：MainViewModel.switchRole 调后端切换会话角色 →
// 全局 loginUser 更新为新角色身份并同步工作副本 → 侧边栏菜单按新角色
// 下发的权限菜单重建（选中/展开/搜索态清空，随后与登录同口径默认打开
// 首页；新角色未授权首页菜单时维持占位），当前儿童上下文与右侧信息
// 侧边栏一并清空；失败时会话与菜单保持原状。
import 'package:client/main.dart';
import 'package:client/services/account_service.dart';
import 'package:client/services/time_service.dart';
import 'package:client/view_models/main/main_view_model.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 返回固定切换结果（系统管理员 × 护理部）的伪账户服务。
class FakeAccountService extends AccountService {
  /// 是否随切换结果下发首页菜单（默认不下发，验证维持占位）。
  final bool includeHomeMenu;

  FakeAccountService({this.includeHomeMenu = false});

  /// 切换时捕获的科室 ID（断言「角色-科室」组合一并提交）。
  String? capturedDeptId;

  @override
  Future<SwitchRoleResult> switchRole(String roleId, {String? deptId}) async {
    capturedDeptId = deptId;
    return (
      user: const LoginUser(
        id: '2',
        userCode: 'doctor01',
        userName: '李医生',
        roleId: '6',
        roleName: '系统管理员',
        userType: 'DOCTOR',
        hospId: '1',
        hospName: '测试三级医院',
        campusId: '8',
        campusName: '城南院区',
        deptId: '9',
        deptName: '护理部',
      ),
      menus: [
        if (includeHomeMenu)
          const Menu(
            id: '11',
            parentId: null,
            itemCode: 'GEN01',
            itemName: '通用',
            itemType: '1',
            menuRoute: null,
            menuIcon: 'apps',
            visible: '1',
          ),
        if (includeHomeMenu)
          const Menu(
            id: '12',
            parentId: '11',
            itemCode: 'GEN0101',
            itemName: '首页',
            itemType: '2',
            menuRoute: '/home',
            menuIcon: 'home',
            visible: '1',
          ),
        const Menu(
          id: '9',
          parentId: null,
          itemCode: 'BUS01',
          itemName: '业务管理',
          itemType: '1',
          menuRoute: null,
          menuIcon: 'business',
          visible: '1',
        ),
        const Menu(
          id: '10',
          parentId: '9',
          itemCode: 'BUS0101',
          itemName: '儿童档案',
          itemType: '2',
          menuRoute: '/business/child',
          menuIcon: 'folder',
          visible: '1',
        ),
      ],
    );
  }
}

/// 始终抛异常（模拟后端拒绝，如角色未授权）的伪账户服务。
class FailingAccountService extends AccountService {
  @override
  Future<SwitchRoleResult> switchRole(String roleId, {String? deptId}) async {
    throw Exception('所选角色无效或未授权，请重新选择');
  }
}

/// 角色 2（登录时所选）的旧菜单：模块 1 下挂菜单 2。
List<Menu> _oldRoleMenus() => const [
  Menu(
    id: '1',
    parentId: null,
    itemCode: 'SYS01',
    itemName: '系统管理',
    itemType: '1',
    menuRoute: null,
    menuIcon: 'settings',
    visible: '1',
  ),
  Menu(
    id: '2',
    parentId: '1',
    itemCode: 'SYS0101',
    itemName: '医院管理',
    itemType: '2',
    menuRoute: '/system/hospital',
    menuIcon: 'domain',
    visible: '1',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    token = null;
    sessionKey = null;
    loginUser = null;
  });

  LoginUser loginAsRole2() => const LoginUser(
    id: '2',
    userCode: 'doctor01',
    userName: '李医生',
    roleId: '2',
    userType: 'DOCTOR',
    hospId: '1',
    hospName: '测试三级医院',
  );

  /// 该用户拥有的「角色-科室」授权组合列表（登录页角色下拉同源；登录用户
  /// 未下发 roleName 时 roleName 按当前 roleId 从此列表回退解析）。
  List<Map<String, String>> userRoles() => const [
    {'id': '2', 'roleName': '儿童心理医生', 'deptId': '7', 'deptName': '儿童心理科'},
    {'id': '6', 'roleName': '系统管理员', 'deptId': '9', 'deptName': '护理部'},
  ];

  test('切换成功：全局与工作副本刷新为新组合身份，菜单按新角色重建', () async {
    loginUser = loginAsRole2();
    final accountService = FakeAccountService();
    final vm = MainViewModel(accountService: accountService);
    vm.setRoles(userRoles());
    vm.syncLoginUser();
    vm.setRoleMenus(_oldRoleMenus());
    // 登录用户未下发 roleName 时按当前角色 ID 从组合列表回退解析
    expect(vm.roleName, '儿童心理医生');
    // 造一个选中态，验证切换后被清空
    vm.selectMenu(vm.menus.first.children.first, ['系统管理', '医院管理']);
    expect(vm.selectedMenuId, '2');

    final ok = await vm.switchRole('6', deptId: '9');

    expect(ok, isTrue);
    expect(accountService.capturedDeptId, '9'); //「角色-科室」组合一并提交
    expect(vm.errorMsg, isNull);
    expect(vm.switchingRole, isFalse);
    // 切换后顶栏「当前角色」取响应下发的 roleName
    expect(vm.roleName, '系统管理员');
    // 全局 loginUser 已替换为响应下发的新组合身份（科室/院区/医院随之刷新）
    expect(loginUser!.roleId, '6');
    expect(loginUser!.roleName, '系统管理员');
    expect(loginUser!.deptName, '护理部');
    expect(loginUser!.campusName, '城南院区');
    // 工作副本同步（引用替换，Selector 可感知）
    expect(vm.loginUser.roleId, '6');
    expect(identical(vm.loginUser, loginUser), isTrue);
    // 菜单整体更换为新角色下发的权限菜单
    expect(vm.menus, hasLength(1));
    expect(vm.menus.first.title, '业务管理');
    expect(vm.menus.first.children.single.title, '儿童档案');
    expect(vm.menus.first.children.single.route, '/business/child');
    // 选中/展开/搜索态已随菜单集更换清空；新角色未授权首页菜单
    // （Fake 默认不下发）时维持「请从左侧选择功能菜单」占位
    expect(vm.selectedMenuId, isNull);
    expect(vm.breadcrumbs, isEmpty);
  });

  test('切换成功且新角色授权首页菜单：与登录同口径默认打开首页', () async {
    loginUser = loginAsRole2();
    final vm = MainViewModel(accountService: FakeAccountService(includeHomeMenu: true));
    vm.syncLoginUser();
    vm.setRoleMenus(_oldRoleMenus());

    final ok = await vm.switchRole('6', deptId: '9');

    expect(ok, isTrue);
    // 选中态指向新角色菜单树中的首页菜单（递归查找命中叶子）
    final selected = vm.findMenuById(vm.selectedMenuId);
    expect(selected, isNotNull);
    expect(selected!.route, '/home');
    expect(selected.title, '首页');
    // 面包屑为「模块名 + 菜单名」，与侧边栏点击同口径
    expect(vm.breadcrumbs, ['通用', '首页']);
  });

  test('切换失败：返回 false、errorMsg 带提示，会话身份与菜单保持原状', () async {
    loginUser = loginAsRole2();
    final vm = MainViewModel(accountService: FailingAccountService());
    vm.syncLoginUser();
    vm.setRoleMenus(_oldRoleMenus());

    final ok = await vm.switchRole('6');

    expect(ok, isFalse);
    expect(vm.errorMsg, '所选角色无效或未授权，请重新选择');
    expect(vm.switchingRole, isFalse);
    // 原角色身份与菜单未受影响
    expect(loginUser!.roleId, '2');
    expect(vm.loginUser.roleId, '2');
    expect(vm.menus.single.title, '系统管理');
  });

  test('切换完成后进行中状态复位，可再次切换', () async {
    loginUser = loginAsRole2();
    final vm = MainViewModel(accountService: FakeAccountService());
    vm.syncLoginUser();
    vm.setRoleMenus(_oldRoleMenus());

    await vm.switchRole('6');
    expect(vm.switchingRole, isFalse);
    final again = await vm.switchRole('6');
    expect(again, isTrue);
  });

  test('切换成功：当前儿童上下文与右侧信息侧边栏一并清空（隐藏）', () async {
    // 侧边栏基础数据构建依赖全局时间服务（未校准即本地时钟）
    if (!getIt.isRegistered<TimeService>()) {
      getIt.registerLazySingleton<TimeService>(() => TimeService());
    }
    loginUser = loginAsRole2();
    final vm = MainViewModel(accountService: FakeAccountService());
    vm.syncLoginUser();
    vm.setRoleMenus(_oldRoleMenus());
    // 造一个已选定儿童态（setCurrentChild 即时出基础侧边栏，扩展档案
    // 加载缺 ChildService 依赖失败被内部吞掉、不影响本用例断言）
    vm.setCurrentChild(_testChildInfo());
    expect(vm.hasCurrentChild, isTrue);
    expect(vm.childSidebarData, isNotNull);

    final ok = await vm.switchRole('6', deptId: '9');

    // 角色/科室上下文已更换：当前儿童与侧边栏清空（侧边栏整体隐藏）
    expect(ok, isTrue);
    expect(vm.hasCurrentChild, isFalse);
    expect(vm.child.id, isEmpty);
    expect(vm.childSidebarData, isNull);
    expect(vm.childSidebarLoading, isFalse);
  });
}

/// 测试用儿童基础档案（最小必填集）。
ChildInfo _testChildInfo() => ChildInfo(
  id: 'child-1',
  checkTime: '2026-11-21',
  name: '测试儿童',
  sex: '1',
  birthDate: '2023-09-01',
  addressProvince: '330000',
  addressCity: '330100',
  addressCounty: '330106',
  addressDetails: '测试路 1 号',
  creatorId: 'user-1',
  creatorName: '测试医生',
  hospId: 'hosp-1',
  hospName: '测试医院',
);
