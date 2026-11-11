// 科室管理页面交互回归测试：加载后左侧显示「医院→院区→科室→下级」树、
// 右侧信息表单三态（未选中提示 / 编辑回填 / 新增清空带挂载说明）；
// 从院区节点经菜单新增；删除走确认对话框；未设置所属医院时给引导提示。
import 'package:client/models/child_info.dart';
import 'package:client/services/campus_service.dart';
import 'package:client/services/department_service.dart';
import 'package:client/view_models/system/department_management_view_model.dart';
import 'package:client/views/system/department_management_page.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 内存版院区服务（页面交互所需子集）。
class _FakeCampusService extends CampusService {
  final Map<String, Campus> store = {};

  void seed(String id, String hospId, String code, String name) {
    store[id] = Campus(id: id, hospId: hospId, code: code, name: name);
  }

  @override
  Future<List<Campus>> getByHospital(String hospId) async {
    final list = store.values.where((c) => c.hospId == hospId).toList()..sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
    return list;
  }
}

/// 内存版科室服务（页面交互所需子集）。
class _FakeDepartmentService extends DepartmentService {
  final Map<String, Department> store = {};
  int nextId = 1;

  void seed(
    String id,
    String hospId,
    String? campusId,
    String? parentId,
    String code,
    String name,
  ) {
    store[id] = Department(
      id: id,
      hospId: hospId,
      campusId: campusId,
      parentId: parentId,
      code: code,
      name: name,
    );
    final n = int.parse(id);
    if (n >= nextId) nextId = n + 1;
  }

  @override
  Future<List<Department>> getByHospital(String hospId) async {
    final list = store.values.where((d) => d.hospId == hospId).toList()..sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
    return list;
  }

  @override
  Future<Department> create({
    required String hospId,
    required String code,
    required String name,
    String? campusId,
    String? parentId,
    String? address,
    String? tel,
  }) async {
    if (store.values.any((d) => d.code == code)) {
      throw Exception('科室代码已存在：$code');
    }
    if (store.values.any(
      (d) => d.campusId == campusId && d.parentId == parentId && d.name == name,
    )) {
      throw Exception('同级下科室名称已存在：$name');
    }
    final id = '${nextId++}';
    final d = Department(
      id: id,
      hospId: hospId,
      campusId: campusId,
      parentId: parentId,
      code: code,
      name: name,
      address: address,
      tel: tel,
    );
    store[id] = d;
    return d;
  }

  @override
  Future<Department> update(String id, Map<String, Object?> changes) async {
    final d = store[id]!;
    final updated = Department(
      id: d.id,
      hospId: d.hospId,
      campusId: d.campusId,
      parentId: d.parentId,
      code: changes['code'] as String? ?? d.code,
      name: changes['name'] as String? ?? d.name,
      address: changes.containsKey('address') ? changes['address'] as String? : d.address,
      tel: changes.containsKey('tel') ? changes['tel'] as String? : d.tel,
    );
    store[id] = updated;
    return updated;
  }

  @override
  Future<int> delete(String id) async {
    if (store.values.any((d) => d.parentId == id)) {
      throw Exception('请先删除下级科室后，再删除科室');
    }
    store.remove(id);
    return 1;
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
  userCode: 'doctor01',
  userName: '王心怡',
  roleId: '',
  userType: 'DOCTOR',
  hospId: '1',
  hospName: '示例人民医院',
);

Widget _wrapWidget(
  DepartmentManagementViewModel viewModel, {
  LoginUser loginUser = _testLoginUser,
}) {
  return ChangeNotifierProvider<DepartmentManagementViewModel>.value(
    value: viewModel,
    child: MaterialApp(
      localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
      supportedLocales: const [Locale('en')],
      // 主框架内页面挂在实际 Scaffold 下（SnackBar 依赖），此处等价模拟
      home: Scaffold(
        body: DepartmentManagementPage(loginUser: loginUser, child: _testChild),
      ),
    ),
  );
}

void main() {
  testWidgets('加载后左侧显示医院→院区→科室→下级树，选中科室右侧回填', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final campusService = _FakeCampusService()..seed('1', '1', 'C001', '主院区');
    final departmentService = _FakeDepartmentService()
      ..seed('1', '1', '1', null, 'D001', '儿童保健科')
      ..seed('2', '1', '1', null, 'D002', '儿童心理科')
      ..seed('3', '1', '1', '2', 'D003', '儿童心理门诊');
    final viewModel = DepartmentManagementViewModel(
      campusService: campusService,
      departmentService: departmentService,
    );

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 医院根（登录用户所属医院）、院区、科室、下级科室逐层显示
    expect(find.text('示例人民医院'), findsOneWidget);
    expect(find.text('主院区'), findsOneWidget);
    expect(find.text('儿童保健科'), findsOneWidget);
    expect(find.text('儿童心理科'), findsOneWidget);
    expect(find.text('儿童心理门诊'), findsOneWidget);
    expect(find.text('请先在左侧选择科室'), findsOneWidget);

    // 点击选中科室：右侧表单回填（第 2 个文本框为名称）
    await tester.tap(find.text('儿童心理科'));
    await tester.pumpAndSettle();
    expect(viewModel.selectedDepartment?.code, 'D002');
    final fields = find.byType(TextFormField);
    expect(
      (tester.widget<TextFormField>(fields.at(0)).controller as TextEditingController).text,
      'D002',
    );
    // 归属说明显示所属院区
    expect(find.text('所属院区：主院区'), findsOneWidget);
  });

  testWidgets('从院区节点新增科室：菜单发起、表单带挂载说明、添加后入树', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final campusService = _FakeCampusService()..seed('1', '1', 'C001', '主院区');
    final departmentService = _FakeDepartmentService()..seed('1', '1', '1', null, 'D001', '儿童保健科');
    final viewModel = DepartmentManagementViewModel(
      campusService: campusService,
      departmentService: departmentService,
    );

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 三个菜单依次属于医院根、院区节点与科室节点（2026-11-10 起医院根
    // 也允许新增科室），树按层序渲染，第二个属于院区节点
    final menus = find.byTooltip('更多操作...');
    expect(menus, findsNWidgets(3));
    await tester.tap(menus.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增科室'));
    await tester.pumpAndSettle();

    expect(viewModel.formMode, DepartmentFormMode.create);
    expect(find.text('挂载到：院区「主院区」'), findsOneWidget);

    // 必填校验
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pump();
    expect(find.text('请输入科室代码'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'D010');
    await tester.enterText(fields.at(1), '发育行为科');
    await tester.enterText(fields.at(2), '门诊楼3层');
    await tester.enterText(fields.at(3), '010-88886010');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('新增成功'), findsOneWidget);
    await tester.pumpAndSettle();

    // 树上院区下出现新科室，右侧切到其编辑态
    expect(find.text('发育行为科'), findsWidgets);
    expect(viewModel.formMode, DepartmentFormMode.edit);
    expect(viewModel.selectedDepartment?.campusId, '1');
    expect(departmentService.store['2']?.campusId, '1');
  });

  testWidgets('修改选中科室名称：保存后左侧树同步更新', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final campusService = _FakeCampusService()..seed('1', '1', 'C001', '主院区');
    final departmentService = _FakeDepartmentService()..seed('1', '1', '1', null, 'D001', '儿童保健科');
    final viewModel = DepartmentManagementViewModel(
      campusService: campusService,
      departmentService: departmentService,
    );

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('儿童保健科'));
    await tester.pumpAndSettle();

    // 编辑态表单回填：名称在第 2 个文本框，改名保存
    final fields = find.byType(TextFormField);
    expect(
      (tester.widget<TextFormField>(fields.at(1)).controller as TextEditingController).text,
      '儿童保健科',
    );
    await tester.enterText(fields.at(1), '儿童保健中心');
    await tester.tap(find.widgetWithText(FilledButton, '保 存'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('保存成功'), findsOneWidget);
    await tester.pumpAndSettle();

    // 树节点与表单回填各显示一次
    expect(find.text('儿童保健中心'), findsWidgets);
    expect(viewModel.selectedDepartment?.name, '儿童保健中心');
  });

  testWidgets('删除科室：确认对话框，确认后树移除并回空态', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final campusService = _FakeCampusService()..seed('1', '1', 'C001', '主院区');
    final departmentService = _FakeDepartmentService()
      ..seed('1', '1', '1', null, 'D001', '儿童保健科')
      ..seed('2', '1', '1', null, 'D002', '儿童心理科');
    final viewModel = DepartmentManagementViewModel(
      campusService: campusService,
      departmentService: departmentService,
    );

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 先选中第一个科室，再从其菜单删除（菜单依次属于医院根、院区、
    // 科室 1、科室 2：2026-11-10 起医院根也有「新增科室」菜单，第 3 个
    // 属于科室 1）
    await tester.tap(find.text('儿童保健科'));
    await tester.pumpAndSettle();
    final menus = find.byTooltip('更多操作...');
    expect(menus, findsNWidgets(4));
    await tester.tap(menus.at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除确认'), findsOneWidget);
    expect(find.textContaining('确定删除科室'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('删除成功'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('儿童保健科'), findsNothing);
    expect(find.text('儿童心理科'), findsOneWidget);
    expect(find.text('请先在左侧选择科室'), findsOneWidget);
    expect(departmentService.store.containsKey('1'), isFalse);
  });

  testWidgets('未设置所属医院：树给引导提示，不发起查询', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final campusService = _FakeCampusService()..seed('1', '1', 'C001', '主院区');
    var queried = false;
    final departmentService = _FakeDepartmentService();
    final viewModel = DepartmentManagementViewModel(
      campusService: _NoQueryCampusService(campusService, () => queried = true),
      departmentService: departmentService,
    );

    await tester.pumpWidget(
      _wrapWidget(
        viewModel,
        loginUser: const LoginUser(
          id: 2,
          userCode: 'x',
          userName: 'x',
          roleId: '',
          userType: 'DOCTOR',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 树空态与 errorMsg 的 SnackBar 各出现一次
    expect(find.text('当前登录用户未设置所属医院，无法管理科室'), findsWidgets);
    expect(find.text('当前登录用户未设置所属医院'), findsOneWidget);
    expect(queried, isFalse, reason: '未绑定不应发起查询');
  });
}

/// 未绑定时不允许发起院区查询的包装（断言未发起查询用）。
class _NoQueryCampusService extends CampusService {
  _NoQueryCampusService(this._inner, this._onQuery);

  final _FakeCampusService _inner;
  final void Function() _onQuery;

  @override
  Future<List<Campus>> getByHospital(String hospId) async {
    _onQuery();
    return _inner.getByHospital(hospId);
  }
}
