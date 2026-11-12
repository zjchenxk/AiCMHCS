// 主界面切换角色接线测试：MainViewModel.switchRole 调后端切换会话角色 →
// 全局 loginUser 更新为新角色身份并同步工作副本 → 侧边栏菜单按新角色
// 下发的权限菜单重建（选中/展开/搜索态清空）；失败时会话与菜单保持原状。
import 'package:client/main.dart';
import 'package:client/services/account_service.dart';
import 'package:client/view_models/main/main_view_model.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 返回固定切换结果（角色 6-系统管理员）的伪账户服务。
class FakeAccountService extends AccountService {
  @override
  Future<SwitchRoleResult> switchRole(String roleId) async {
    return (
      user: const LoginUser(
        id: '2',
        userCode: 'doctor01',
        userName: '李医生',
        roleId: '6',
        userType: 'DOCTOR',
        hospId: '1',
        hospName: '测试三级医院',
      ),
      menus: [
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
  Future<SwitchRoleResult> switchRole(String roleId) async {
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

  /// 该用户拥有的角色列表（登录页角色下拉同源，roleName 按当前 roleId 从此解析）。
  List<Map<String, String>> userRoles() => const [
    {'id': '2', 'roleName': '儿童心理医生'},
    {'id': '6', 'roleName': '系统管理员'},
  ];

  test('切换成功：全局与工作副本刷新为新角色身份，菜单按新角色重建', () async {
    loginUser = loginAsRole2();
    final vm = MainViewModel(accountService: FakeAccountService());
    vm.setRoles(userRoles());
    vm.syncLoginUser();
    vm.setRoleMenus(_oldRoleMenus());
    // 顶栏信息栏按当前角色 ID 解析角色名称
    expect(vm.roleName, '儿童心理医生');
    // 造一个选中态，验证切换后被清空
    vm.selectMenu(vm.menus.first.children.first, ['系统管理', '医院管理']);
    expect(vm.selectedMenuId, '2');

    final ok = await vm.switchRole('6');

    expect(ok, isTrue);
    expect(vm.errorMsg, isNull);
    expect(vm.switchingRole, isFalse);
    // 切换后随新角色 ID 解析新角色名称
    expect(vm.roleName, '系统管理员');
    // 全局 loginUser 已替换为响应下发的新角色身份
    expect(loginUser!.roleId, '6');
    // 工作副本同步（引用替换，Selector 可感知）
    expect(vm.loginUser.roleId, '6');
    expect(identical(vm.loginUser, loginUser), isTrue);
    // 菜单整体更换为新角色下发的权限菜单
    expect(vm.menus, hasLength(1));
    expect(vm.menus.first.title, '业务管理');
    expect(vm.menus.first.children.single.title, '儿童档案');
    expect(vm.menus.first.children.single.route, '/business/child');
    // 选中/展开/搜索态已随菜单集更换清空
    expect(vm.selectedMenuId, isNull);
    expect(vm.breadcrumbs, isEmpty);
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
}
