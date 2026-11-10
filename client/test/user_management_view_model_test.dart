// 用户管理 ViewModel 单元测试：Fake 服务构造注入，覆盖按登录用户所属
// 医院加载建树（科室→下级科室→用户、孤儿用户兜底、别家医院隔离）、
// 未设科室空态、表单三态流转、角色勾选、新增/修改提交参数与整表重拉、
// 选中保持、失败提示。
import 'package:client/models/user_tree_node.dart';
import 'package:client/services/department_service.dart';
import 'package:client/services/role_service.dart';
import 'package:client/services/user_service.dart';
import 'package:client/view_models/system/user_management_view_model.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存版科室服务（建树所需的子集）。
class FakeDepartmentService extends DepartmentService {
  final Map<String, Department> store = {};
  int getByHospitalCalls = 0;

  void seed(String id, String hospId, String? parentId, String name) {
    store[id] = Department(
      id: id,
      hospId: hospId,
      parentId: parentId,
      code: 'D$id',
      name: name,
    );
  }

  @override
  Future<List<Department>> getByHospital(String hospId) async {
    getByHospitalCalls++;
    final list = store.values.where((d) => d.hospId == hospId).toList()..sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
    return list;
  }
}

/// 内存版角色服务（多选数据源所需的子集）。
class FakeRoleService extends RoleService {
  final Map<String, Role> store = {};

  void seed(String id, String hospId, String code, String name) {
    store[id] = Role(id: id, roleCode: code, roleName: name, hospId: hospId);
  }

  @override
  Future<List<Role>> getByHospital(String hospId) async {
    final list = store.values.where((r) => r.hospId == hospId).toList()..sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
    return list;
  }
}

/// 内存版用户服务：模拟后端按医院查询、按 USER_CODE 查重。
class FakeUserService extends UserService {
  final Map<String, User> store = {};
  int nextId = 1;
  int getByHospitalCalls = 0;
  Object? Function()? onCreate;
  Object? Function(String id)? onUpdate;

  /// 最近一次新增的入参（断言挂载与角色提交用）。
  ({String? deptId, List<String> roleIds})? lastCreateArgs;

  /// 最近一次修改的入参（断言角色全量覆盖与口令重置用）。
  ({List<String>? roleIds, String? password})? lastUpdateArgs;

  void seed(
    String id,
    String hospId,
    String? deptId,
    String userCode,
    String userName, {
    List<String> roleIds = const [],
    String status = '1',
  }) {
    store[id] = User(
      id: id,
      userCode: userCode,
      userName: userName,
      hospId: hospId,
      deptId: deptId,
      status: status,
      roleIds: roleIds,
    );
    final n = int.parse(id);
    if (n >= nextId) nextId = n + 1;
  }

  @override
  Future<List<User>> getByHospital(String hospId) async {
    getByHospitalCalls++;
    final list = store.values.where((u) => u.hospId == hospId).toList()..sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
    return list;
  }

  @override
  Future<User> create({
    required String hospId,
    required String deptId,
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
    String? avatarImage,
    String? signatureImage,
    String? status,
    List<String> roleIds = const [],
  }) async {
    final error = onCreate?.call();
    if (error != null) throw error;
    if (store.values.any((u) => u.userCode == userCode)) {
      throw Exception('登录账号已存在：$userCode');
    }
    lastCreateArgs = (deptId: deptId, roleIds: roleIds);
    final id = '${nextId++}';
    final u = User(
      id: id,
      userCode: userCode,
      userName: userName,
      hospId: hospId,
      userType: userType,
      permissionLevel: permissionLevel,
      phone: phone,
      idCardNo: idCardNo,
      hisUserCode: hisUserCode,
      mchisUserCode: mchisUserCode,
      certId: certId,
      avatarImage: avatarImage,
      signatureImage: signatureImage,
      deptId: deptId,
      status: status ?? '1',
      roleIds: roleIds,
    );
    store[id] = u;
    return u;
  }

  @override
  Future<User> update(
    String id,
    Map<String, Object?> changes, {
    String? password,
    List<String>? roleIds,
  }) async {
    final error = onUpdate?.call(id);
    if (error != null) throw error;
    final u = store[id];
    if (u == null) throw Exception('用户不存在：$id');
    lastUpdateArgs = (roleIds: roleIds, password: password);
    final updated = User(
      id: u.id,
      userCode: u.userCode,
      userName: changes['userName'] as String? ?? u.userName,
      hospId: u.hospId,
      userType: changes.containsKey('userType') ? changes['userType'] as String? : u.userType,
      permissionLevel: changes.containsKey('permissionLevel') ? changes['permissionLevel'] as String? : u.permissionLevel,
      phone: changes.containsKey('phone') ? changes['phone'] as String? : u.phone,
      idCardNo: changes.containsKey('idCardNo') ? changes['idCardNo'] as String? : u.idCardNo,
      hisUserCode: changes.containsKey('hisUserCode') ? changes['hisUserCode'] as String? : u.hisUserCode,
      mchisUserCode: changes.containsKey('mchisUserCode') ? changes['mchisUserCode'] as String? : u.mchisUserCode,
      certId: changes.containsKey('certId') ? changes['certId'] as String? : u.certId,
      avatarImage: changes.containsKey('avatarImage') ? changes['avatarImage'] as String? : u.avatarImage,
      signatureImage: changes.containsKey('signatureImage') ? changes['signatureImage'] as String? : u.signatureImage,
      deptId: u.deptId,
      status: changes['status'] as String? ?? u.status,
      roleIds: roleIds ?? u.roleIds,
    );
    store[id] = updated;
    return updated;
  }
}

void main() {
  late FakeDepartmentService departmentService;
  late FakeRoleService roleService;
  late FakeUserService userService;
  late UserManagementViewModel viewModel;

  setUp(() {
    departmentService = FakeDepartmentService()
      // 医院 1：儿童保健科、儿童心理科（下级：儿童心理门诊）
      ..seed('1', '1', null, '儿童保健科')
      ..seed('2', '1', null, '儿童心理科')
      ..seed('3', '1', '2', '儿童心理门诊')
      // 别家医院的科室（不应出现在本院树）
      ..seed('9', '2', null, '别家医院的科室');
    roleService = FakeRoleService()
      ..seed('101', '1', 'R001', '医生')
      ..seed('102', '1', 'R002', '护士')
      ..seed('201', '2', 'R101', '别家医院角色');
    userService = FakeUserService()
      ..seed('1', '1', '1', 'admin', '系统管理员')
      ..seed('2', '1', '2', 'doctor01', '王心怡', roleIds: ['101'])
      ..seed('3', '1', '3', 'nurse01', '陈晓', roleIds: ['101', '102'])
      // 孤儿用户：DEPT_ID 为空
      ..seed('4', '1', null, 'teacher01', '李晓芳')
      // DEPT_ID 指向已删除科室
      ..seed('5', '1', '999', 'parent01', '张浩然', status: '0')
      // 别家医院的用户（不应出现在本院树）
      ..seed('6', '2', '9', 'doctor99', '分院医生');
    viewModel = UserManagementViewModel(
      userService: userService,
      departmentService: departmentService,
      roleService: roleService,
    );
  });

  test('loadData：按登录用户医院建树（科室→下级科室→用户）', () async {
    final ok = await viewModel.loadData('1');
    expect(ok, isTrue);
    expect(viewModel.unbound, isFalse);
    expect(viewModel.departmentEmpty, isFalse);

    // 两个顶级科室根（别家医院科室不出现）
    expect(viewModel.roots.map((r) => r.name).toList(), ['儿童保健科', '儿童心理科', '未分配科室']);
    final healthDept = viewModel.roots[0];
    final psychDept = viewModel.roots[1];
    final unassigned = viewModel.roots[2];

    // 用户挂在各自科室下：儿童保健科→admin
    expect(healthDept.children.single.name, '系统管理员');
    expect(healthDept.children.single.type, UserTreeNodeType.user);
    // 儿童心理科→doctor01 + 下级科室（儿童心理门诊→nurse01）
    expect(psychDept.children[0].name, '王心怡');
    expect(psychDept.children[0].user!.userCode, 'doctor01');
    expect(psychDept.children[1].name, '儿童心理门诊');
    expect(psychDept.children[1].children.single.user!.userCode, 'nurse01');
    // 孤儿用户（无科室/科室已删）收入「未分配科室」
    expect(unassigned.department, isNull);
    expect(
      unassigned.children.map((c) => c.user!.userCode).toList(),
      ['teacher01', 'parent01'],
    );
    expect(findByName(viewModel.roots, '别家医院的科室'), isNull);
    expect(viewModel.formMode, UserFormMode.empty);
    // 角色多选数据源仅本院角色
    expect(viewModel.roles.map((r) => r.roleName).toList(), ['医生', '护士']);
  });

  test('loadData：医院未设任何科室时置空态（不能新增用户）', () async {
    final emptyDeptService = FakeDepartmentService();
    final vm = UserManagementViewModel(
      userService: userService,
      departmentService: emptyDeptService,
      roleService: roleService,
    );
    expect(await vm.loadData('9'), isTrue);
    expect(vm.departmentEmpty, isTrue);
    expect(vm.roots, isEmpty);

    // 有用户但无科室：孤儿收入「未分配科室」，科室为空依旧不能新增
    userService.seed('7', '9', null, 'orphan01', '孤儿用户');
    expect(await vm.loadData('9'), isTrue);
    expect(vm.departmentEmpty, isTrue);
    expect(vm.roots.single.name, '未分配科室');
    // 「未分配科室」不可作为挂载目标
    vm.startCreate(vm.roots.single);
    expect(vm.formMode, UserFormMode.empty);
  });

  test('loadData：未设置所属医院时置提示、树清空', () async {
    expect(await viewModel.loadData(null), isFalse);
    expect(viewModel.unbound, isTrue);
    expect(viewModel.roots, isEmpty);
    expect(viewModel.errorMsg, contains('未设置所属医院'));

    // 再以正常医院加载可恢复
    expect(await viewModel.loadData('1'), isTrue);
    expect(viewModel.unbound, isFalse);
    expect(viewModel.errorMsg, isNull);
  });

  test('loadData：同一医院重复加载强制重拉且保留展开与选中（切回页面刷新）', () async {
    await viewModel.loadData('1');
    final psychDept = viewModel.roots[1];
    viewModel.toggleExpand(psychDept);
    viewModel.selectUser(psychDept.children[0].user!);
    final userCalls = userService.getByHospitalCalls;

    expect(await viewModel.loadData('1'), isTrue);
    expect(userService.getByHospitalCalls, greaterThan(userCalls), reason: '切回页面应重拉，保证科室/角色管理等兄弟页面改动后数据一致');
    // 折叠与选中状态保留
    expect(viewModel.roots[1].expanded, isFalse);
    expect(viewModel.selectedUser?.userCode, 'doctor01');
  });

  test('selectUser：进编辑态并回显其角色勾选', () async {
    await viewModel.loadData('1');
    final doctor = viewModel.users.firstWhere((u) => u.userCode == 'doctor01');
    viewModel.selectUser(doctor);
    expect(viewModel.formMode, UserFormMode.edit);
    expect(viewModel.selectedUser?.id, doctor.id);
    expect(viewModel.checkedRoleIds, {'101'});

    // 切换用户勾选随之切换
    final nurse = viewModel.users.firstWhere((u) => u.userCode == 'nurse01');
    viewModel.selectUser(nurse);
    expect(viewModel.checkedRoleIds, {'101', '102'});
  });

  test('startCreate：科室节点下进入新增态、勾选清空；取消回空态', () async {
    await viewModel.loadData('1');
    final deptNode = viewModel.roots[0];
    // 先选一个用户带出勾选，再进入新增应清空
    viewModel.selectUser(viewModel.users.first);
    viewModel.startCreate(deptNode);
    expect(viewModel.formMode, UserFormMode.create);
    expect(viewModel.createParent?.name, '儿童保健科');
    expect(viewModel.checkedRoleIds, isEmpty);
    expect(viewModel.selectedUser, isNull);

    viewModel.cancelCreate();
    expect(viewModel.formMode, UserFormMode.empty);
  });

  test('toggleRole：勾选/取消勾选角色', () async {
    await viewModel.loadData('1');
    viewModel.toggleRole('101');
    expect(viewModel.checkedRoleIds, {'101'});
    viewModel.toggleRole('102');
    expect(viewModel.checkedRoleIds, {'101', '102'});
    viewModel.toggleRole('101');
    expect(viewModel.checkedRoleIds, {'102'});
  });

  test('createUser：提交挂载科室与勾选角色，成功后选中新用户退出新增态', () async {
    await viewModel.loadData('1');
    final deptNode = viewModel.roots[1]; // 儿童心理科
    viewModel.startCreate(deptNode);
    viewModel.toggleRole('102');

    final ok = await viewModel.createUser(
      userCode: 'doctor02',
      userName: '林静',
      password: 'Doctor@123',
      userType: 'DOCTOR',
    );
    expect(ok, isTrue);
    expect(userService.lastCreateArgs?.deptId, '2');
    expect(userService.lastCreateArgs?.roleIds, ['102']);
    expect(viewModel.formMode, UserFormMode.edit);
    expect(viewModel.selectedUser?.userCode, 'doctor02');
    expect(viewModel.checkedRoleIds, {'102'});
    // 新用户出现在树上该科室之下
    final refreshed = viewModel.roots[1];
    expect(refreshed.children.any((c) => c.user?.userCode == 'doctor02'), isTrue);
  });

  test('createUser：服务端报错时返回失败、停留新增模式并带提示', () async {
    await viewModel.loadData('1');
    viewModel.startCreate(viewModel.roots[0]);
    userService.onCreate = () => Exception('登录账号已存在：admin');

    final ok = await viewModel.createUser(
      userCode: 'admin',
      userName: '重复账号',
      password: 'Admin@123',
    );
    expect(ok, isFalse);
    expect(viewModel.formMode, UserFormMode.create);
    expect(viewModel.errorMsg, contains('已存在'));
  });

  test('updateUser：以表单勾选全量覆盖角色，成功后保持选中', () async {
    await viewModel.loadData('1');
    final doctor = viewModel.users.firstWhere((u) => u.userCode == 'doctor01');
    viewModel.selectUser(doctor);
    expect(viewModel.checkedRoleIds, {'101'});

    // 勾掉 101、勾上 102
    viewModel.toggleRole('101');
    viewModel.toggleRole('102');

    final ok = await viewModel.updateUser(doctor.id, {'userName': '王心怡医生'}, password: 'NewPass@123');
    expect(ok, isTrue);
    expect(userService.lastUpdateArgs?.roleIds, ['102']);
    expect(userService.lastUpdateArgs?.password, 'NewPass@123');
    expect(viewModel.selectedUser?.userName, '王心怡医生');
    expect(viewModel.checkedRoleIds, {'102'});
  });

  test('updateUser：密码留空不改（不提交口令）；服务端报错时返回失败并带提示', () async {
    await viewModel.loadData('1');
    final admin = viewModel.users.firstWhere((u) => u.userCode == 'admin');
    viewModel.selectUser(admin);

    expect(await viewModel.updateUser(admin.id, {'status': '0'}, password: '  '), isTrue);
    expect(userService.lastUpdateArgs?.password, isNull);
    expect(viewModel.selectedUser?.status, '0');

    userService.onUpdate = (id) => Exception('用户不存在：$id');
    expect(await viewModel.updateUser(admin.id, {'userName': '改名'}), isFalse);
    expect(viewModel.errorMsg, contains('不存在'));
  });
}

/// 在根列表中递归查找指定名称的节点。
UserTreeNode? findByName(List<UserTreeNode> roots, String name) {
  for (final root in roots) {
    if (root.name == name) return root;
    for (final child in root.children) {
      final hit = findByName([child], name);
      if (hit != null) return hit;
    }
  }
  return null;
}
