// 院区管理页面交互回归测试：加载后左侧显示本院区列表、右侧信息表单
// 三态（未选中提示 / 编辑回填 / 新增清空）；新增走右侧表单不弹窗；
// 删除走确认对话框；未设置所属医院时给引导提示。
import 'package:client/models/child_info.dart';
import 'package:client/services/campus_service.dart';
import 'package:client/view_models/system/campus_management_view_model.dart';
import 'package:client/views/system/campus_management_page.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 内存版院区服务（页面交互所需子集）。
class _FakeCampusService extends CampusService {
  final Map<String, Campus> store = {};
  int nextId = 1;
  int getByHospitalCalls = 0;

  void seed(String id, String hospId, String code, String name) {
    store[id] = Campus(id: id, hospId: hospId, code: code, name: name);
    final n = int.parse(id);
    if (n >= nextId) nextId = n + 1;
  }

  @override
  Future<List<Campus>> getByHospital(String hospId) async {
    getByHospitalCalls++;
    final list = store.values.where((c) => c.hospId == hospId).toList()..sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
    return list;
  }

  @override
  Future<Campus> create({
    required String hospId,
    required String code,
    required String name,
    String? address,
    String? tel,
  }) async {
    if (store.values.any((c) => c.code == code)) {
      throw Exception('院区代码已存在：$code');
    }
    final id = '${nextId++}';
    final c = Campus(id: id, hospId: hospId, code: code, name: name, address: address, tel: tel);
    store[id] = c;
    return c;
  }

  @override
  Future<Campus> update(String id, Map<String, Object?> changes) async {
    final c = store[id]!;
    final updated = Campus(
      id: c.id,
      hospId: c.hospId,
      code: changes['code'] as String? ?? c.code,
      name: changes['name'] as String? ?? c.name,
      address: changes.containsKey('address') ? changes['address'] as String? : c.address,
      tel: changes.containsKey('tel') ? changes['tel'] as String? : c.tel,
    );
    store[id] = updated;
    return updated;
  }

  @override
  Future<int> delete(String id) async {
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
);

Widget _wrapWidget(CampusManagementViewModel viewModel, {LoginUser loginUser = _testLoginUser}) {
  return ChangeNotifierProvider<CampusManagementViewModel>.value(
    value: viewModel,
    child: MaterialApp(
      localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
      supportedLocales: const [Locale('en')],
      // 主框架内页面挂在实际 Scaffold 下（SnackBar 依赖），此处等价模拟
      home: Scaffold(
        body: CampusManagementPage(loginUser: loginUser, child: _testChild),
      ),
    ),
  );
}

void main() {
  testWidgets('加载后左侧仅显示本院区列表，选中院区右侧表单回填', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = _FakeCampusService()
      ..seed('1', '1', 'C001', '主院区')
      ..seed('2', '1', 'C002', '顺义院区')
      ..seed('3', '2', 'C003', '别家医院的院区');
    final viewModel = CampusManagementViewModel(campusService: service);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 未选中：右侧提示，左侧仅本院两条
    expect(find.text('主院区'), findsOneWidget);
    expect(find.text('顺义院区'), findsOneWidget);
    expect(find.text('别家医院的院区'), findsNothing);
    expect(find.text('请先在左侧选择院区'), findsOneWidget);

    // 点击选中：右侧表单回填
    await tester.tap(find.text('顺义院区'));
    await tester.pumpAndSettle();
    expect(viewModel.selectedCampus?.name, '顺义院区');
    final fields = find.byType(TextFormField);
    expect((tester.widget<TextFormField>(fields.at(1)).controller as TextEditingController).text, '顺义院区');
  });

  testWidgets('新增院区：右侧表单录入（不弹窗），添加后列表立即显示并选中', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = _FakeCampusService()..seed('1', '1', 'C001', '主院区');
    final viewModel = CampusManagementViewModel(campusService: service);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 点击新增：不弹窗，右侧切换为新增表单（清空）
    await tester.tap(find.byTooltip('新增院区'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(viewModel.formMode, CampusFormMode.create);

    // 必填校验
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pump();
    expect(find.text('请输入院区代码'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'C002');
    await tester.enterText(fields.at(1), '西城院区');
    await tester.enterText(fields.at(2), '西城区测试路2号');
    await tester.enterText(fields.at(3), '010-87654321');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('新增成功'), findsOneWidget);
    await tester.pumpAndSettle();

    // 列表立即显示新院区，右侧切到新院区编辑态
    expect(find.text('西城院区'), findsWidgets);
    expect(viewModel.formMode, CampusFormMode.edit);
    expect(viewModel.selectedCampus?.name, '西城院区');
    expect(service.store['2']?.hospId, '1');
  });

  testWidgets('修改选中院区名称：保存后左侧列表同步更新', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = _FakeCampusService()..seed('1', '1', 'C001', '主院区');
    final viewModel = CampusManagementViewModel(campusService: service);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主院区'));
    await tester.pumpAndSettle();

    // 编辑态表单回填：名称在第 2 个文本框，改名保存
    final fields = find.byType(TextFormField);
    expect((tester.widget<TextFormField>(fields.at(1)).controller as TextEditingController).text, '主院区');
    await tester.enterText(fields.at(1), '本部院区');
    await tester.tap(find.widgetWithText(FilledButton, '保 存'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('保存成功'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('本部院区'), findsWidgets);
    expect(viewModel.selectedCampus?.name, '本部院区');
  });

  testWidgets('删除院区：确认对话框，确认后列表移除并回空态', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = _FakeCampusService()
      ..seed('1', '1', 'C001', '主院区')
      ..seed('2', '1', 'C002', '顺义院区');
    final viewModel = CampusManagementViewModel(campusService: service);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 先选中再删除选中项
    await tester.tap(find.text('主院区'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除').first);
    await tester.pumpAndSettle();
    expect(find.text('删除确认'), findsOneWidget);
    expect(find.textContaining('确定删除院区'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('删除成功'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('主院区'), findsNothing);
    expect(find.text('顺义院区'), findsOneWidget);
    expect(find.text('请先在左侧选择院区'), findsOneWidget);
    expect(service.store.containsKey('1'), isFalse);
  });

  testWidgets('未设置所属医院：列表给引导提示、新增禁用', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = _FakeCampusService()..seed('1', '1', 'C001', '主院区');
    final viewModel = CampusManagementViewModel(campusService: service);

    await tester.pumpWidget(
      _wrapWidget(
        viewModel,
        loginUser: const LoginUser(
          id: 2,
          userCode: 'x',
          userName: 'x',
          userType: 'DOCTOR',
          roleId: '',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 列表空态与 errorMsg 的 SnackBar 各出现一次
    expect(find.text('当前登录用户未设置所属医院，无法管理院区'), findsWidgets);
    expect(find.text('当前登录用户未设置所属医院'), findsOneWidget);
    expect(find.byTooltip('新增院区'), findsOneWidget);
    // 新增按钮禁用：点击不切换模式
    await tester.tap(find.byTooltip('新增院区'));
    await tester.pumpAndSettle();
    expect(viewModel.formMode, CampusFormMode.empty);
    expect(service.getByHospitalCalls, 0, reason: '未绑定不应发起查询');
  });
}
