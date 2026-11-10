// 用户管理页面交互回归测试：加载后左侧显示「科室→下级科室→用户」树
// （孤儿用户入「未分配科室」）、右侧表单三态（未选中提示 / 编辑回填 /
// 新增清空）；从科室节点新增用户带角色勾选；修改保存后树同步；医院未
// 设科室时给「未添加科室，不能新增用户」引导。
import 'package:client/models/child_info.dart';
import 'package:client/services/department_service.dart';
import 'package:client/services/role_service.dart';
import 'package:client/services/user_service.dart';
import 'package:client/view_models/system/user_management_view_model.dart';
import 'package:client/views/system/user_management_page.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 内存版科室服务（页面交互所需子集）。
class _FakeDepartmentService extends DepartmentService {
  final Map<String, Department> store = {};

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
    return store.values.where((d) => d.hospId == hospId).toList()..sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
  }
}

/// 内存版角色服务（页面交互所需子集）。
class _FakeRoleService extends RoleService {
  final Map<String, Role> store = {};

  void seed(String id, String hospId, String code, String name) {
    store[id] = Role(id: id, roleCode: code, roleName: name, hospId: hospId);
  }

  @override
  Future<List<Role>> getByHospital(String hospId) async {
    return store.values.where((r) => r.hospId == hospId).toList()..sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
  }
}

/// 内存版用户服务（页面交互所需子集）。
class _FakeUserService extends UserService {
  final Map<String, User> store = {};
  int nextId = 1;

  /// 最近一次新增的角色入参（断言多选提交用）。
  List<String>? lastCreateRoleIds;

  void seed(
    String id,
    String hospId,
    String? deptId,
    String userCode,
    String userName, {
    List<String> roleIds = const [],
  }) {
    store[id] = User(
      id: id,
      userCode: userCode,
      userName: userName,
      hospId: hospId,
      deptId: deptId,
      status: '1',
      roleIds: roleIds,
    );
    final n = int.parse(id);
    if (n >= nextId) nextId = n + 1;
  }

  @override
  Future<List<User>> getByHospital(String hospId) async {
    return store.values.where((u) => u.hospId == hospId).toList()..sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
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
    String? signatureImage,
    String? status,
    List<String> roleIds = const [],
  }) async {
    lastCreateRoleIds = roleIds;
    final id = '${nextId++}';
    final u = User(
      id: id,
      userCode: userCode,
      userName: userName,
      hospId: hospId,
      userType: userType,
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
    final u = store[id]!;
    final updated = User(
      id: u.id,
      userCode: u.userCode,
      userName: changes['userName'] as String? ?? u.userName,
      hospId: u.hospId,
      userType: u.userType,
      deptId: u.deptId,
      status: changes['status'] as String? ?? u.status,
      roleIds: roleIds ?? u.roleIds,
    );
    store[id] = updated;
    return updated;
  }
}

final _testChild = ChildInfo(
  cardNo: '',
  patientId: '',
  name: '',
  gender: '',
  birthDate: DateTime(2020, 1, 1),
  gestationalWeek: '',
  actualAge: '',
  correctedAge: '',
  phone: '',
);

const _testLoginUser = LoginUser(
  id: 1,
  userCode: 'admin',
  userName: '系统管理员',
  userType: 'ADMIN',
  hospId: '1',
  hospName: '示例人民医院',
);

Widget _wrapWidget(UserManagementViewModel viewModel, {LoginUser loginUser = _testLoginUser}) {
  return ChangeNotifierProvider<UserManagementViewModel>.value(
    value: viewModel,
    child: MaterialApp(
      localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
      supportedLocales: const [Locale('en')],
      // 主框架内页面挂在实际 Scaffold 下（SnackBar 依赖），此处等价模拟
      home: Scaffold(
        body: UserManagementPage(loginUser: loginUser, child: _testChild),
      ),
    ),
  );
}

void main() {
  testWidgets('加载后左侧显示科室→下级科室→用户树，点击用户右侧回填', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final departmentService = _FakeDepartmentService()
      ..seed('1', '1', null, '儿童保健科')
      ..seed('2', '1', null, '儿童心理科')
      ..seed('3', '1', '2', '儿童心理门诊');
    final roleService = _FakeRoleService()
      ..seed('101', '1', 'R001', '医生')
      ..seed('102', '1', 'R002', '护士');
    final userService = _FakeUserService()
      ..seed('1', '1', '1', 'admin', '系统管理员')
      ..seed('2', '1', '2', 'doctor01', '王心怡', roleIds: ['101'])
      ..seed('4', '1', null, 'teacher01', '李晓芳');
    final viewModel = UserManagementViewModel(
      userService: userService,
      departmentService: departmentService,
      roleService: roleService,
    );

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 科室、下级科室、用户、未分配科室逐项显示；右侧空态提示
    expect(find.text('儿童保健科'), findsOneWidget);
    expect(find.text('儿童心理科'), findsOneWidget);
    expect(find.text('儿童心理门诊'), findsOneWidget);
    expect(find.text('系统管理员'), findsOneWidget);
    expect(find.text('王心怡'), findsOneWidget);
    expect(find.text('未分配科室'), findsOneWidget);
    expect(find.text('李晓芳'), findsOneWidget);
    expect(find.text('请先在左侧选择用户，或点击科室节点的 + 新增用户'), findsOneWidget);

    // 点击用户：右侧表单回填（登录账号只读、姓名可改），角色回显勾选
    await tester.tap(find.text('王心怡'));
    await tester.pumpAndSettle();
    expect(viewModel.formMode, UserFormMode.edit);
    final fields = find.byType(TextFormField);
    expect(
      (tester.widget<TextFormField>(fields.at(0)).controller as TextEditingController).text,
      'doctor01',
    );
    expect(
      (tester.widget<TextFormField>(fields.at(1)).controller as TextEditingController).text,
      '王心怡',
    );
    final doctorChip = tester.widget<FilterChip>(find.widgetWithText(FilterChip, '医生'));
    expect(doctorChip.selected, isTrue);
    final nurseChip = tester.widget<FilterChip>(find.widgetWithText(FilterChip, '护士'));
    expect(nurseChip.selected, isFalse);
  });

  testWidgets('从科室节点新增用户：表单校验、录入与角色勾选提交后入树', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final departmentService = _FakeDepartmentService()..seed('2', '1', null, '儿童心理科');
    final roleService = _FakeRoleService()
      ..seed('101', '1', 'R001', '医生')
      ..seed('102', '1', 'R002', '护士');
    final userService = _FakeUserService();
    final viewModel = UserManagementViewModel(
      userService: userService,
      departmentService: departmentService,
      roleService: roleService,
    );

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 科室节点行尾 + 按钮发起在儿童心理科下新增
    await tester.tap(find.byTooltip('新增用户'));
    await tester.pumpAndSettle();
    expect(viewModel.formMode, UserFormMode.create);
    expect(viewModel.createParent?.name, '儿童心理科');
    expect(find.text('新增用户 - 儿童心理科'), findsOneWidget);

    // 必填校验
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pump();
    expect(find.text('请输入登录账号'), findsOneWidget);

    // 录入必填项并勾选一个角色
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'doctor02');
    await tester.enterText(fields.at(1), '林静');
    await tester.enterText(fields.at(2), 'Doctor@123');
    await tester.tap(find.text('护士'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('新增成功'), findsOneWidget);
    await tester.pumpAndSettle();

    // 新用户出现在树上并选中，角色按勾选提交
    expect(find.text('林静'), findsWidgets);
    expect(viewModel.formMode, UserFormMode.edit);
    expect(viewModel.selectedUser?.userCode, 'doctor02');
    expect(userService.lastCreateRoleIds, ['102']);
  });

  testWidgets('修改选中用户姓名：保存后左侧树同步更新', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final departmentService = _FakeDepartmentService()..seed('1', '1', null, '儿童保健科');
    final roleService = _FakeRoleService()..seed('101', '1', 'R001', '医生');
    final userService = _FakeUserService()..seed('2', '1', '1', 'doctor01', '王心怡', roleIds: ['101']);
    final viewModel = UserManagementViewModel(
      userService: userService,
      departmentService: departmentService,
      roleService: roleService,
    );

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('王心怡'));
    await tester.pumpAndSettle();

    // 编辑态回填姓名（第 2 个文本框），改名保存
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), '王心怡医生');
    await tester.tap(find.widgetWithText(FilledButton, '保 存'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('保存成功'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('王心怡医生'), findsWidgets);
    expect(viewModel.selectedUser?.userName, '王心怡医生');
  });

  testWidgets('医院未设科室：左侧给「未添加科室，不能新增用户」引导', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final viewModel = UserManagementViewModel(
      userService: _FakeUserService(),
      departmentService: _FakeDepartmentService(),
      roleService: _FakeRoleService(),
    );

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    expect(viewModel.departmentEmpty, isTrue);
    expect(find.text('未添加科室，不能新增用户'), findsWidgets);
    expect(find.text('请先在「系统管理 → 科室管理」中添加科室'), findsOneWidget);
    // 无科室节点即无新增入口
    expect(find.byTooltip('新增用户'), findsNothing);
  });
}
