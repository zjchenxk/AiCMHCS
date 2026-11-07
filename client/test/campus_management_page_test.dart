// 院区管理页面交互回归测试：加载后左树选中医院、右侧院区列表展示；
// 新增/编辑走毛玻璃对话框；删除走确认对话框；切换医院右侧列表联动。
import 'package:client/models/child_info.dart';
import 'package:client/services/campus_service.dart';
import 'package:client/services/hospital_service.dart';
import 'package:client/view_models/system/campus_management_view_model.dart';
import 'package:client/views/system/campus_management_page.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 内存版医院服务（仅建树所需子集）。
class _FakeHospitalService extends HospitalService {
  final Map<String, Hospital> store = {};

  void seed(String id, String? parentId, String code, String name) {
    store[id] = Hospital(
      id: id,
      parentId: parentId,
      code: code,
      name: name,
      province: '北京市',
      city: '市辖区',
      county: '东城区',
      address: '测试路$id号',
      tel: '010-12345678',
    );
  }

  @override
  Future<List<Hospital>> getAll() async {
    final list = store.values.toList()..sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
    return list;
  }
}

/// 内存版院区服务（页面交互所需子集）。
class _FakeCampusService extends CampusService {
  final Map<String, Campus> store = {};
  int nextId = 1;
  int getAllCalls = 0;

  void seed(String id, String hospId, String code, String name) {
    store[id] = Campus(id: id, hospId: hospId, code: code, name: name);
    final n = int.parse(id);
    if (n >= nextId) nextId = n + 1;
  }

  @override
  Future<List<Campus>> getAll() async {
    getAllCalls++;
    final list = store.values.toList()
      ..sort((a, b) {
        final byHosp = a.hospId.compareTo(b.hospId);
        return byHosp != 0 ? byHosp : int.parse(a.id).compareTo(int.parse(b.id));
      });
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
      hospId: changes['hospId'] as String? ?? c.hospId,
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

Widget _wrapWidget(CampusManagementViewModel viewModel) {
  return ChangeNotifierProvider<CampusManagementViewModel>.value(
    value: viewModel,
    child: MaterialApp(
      localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
      supportedLocales: const [Locale('en')],
      // 主框架内页面挂在实际 Scaffold 下（SnackBar 依赖），此处等价模拟
      home: Scaffold(
        body: CampusManagementPage(
          loginUser: const LoginUser(
            id: 1,
            userCode: 'admin',
            userName: '管理员',
            userType: 'ADMIN',
            phone: '',
          ),
          child: _testChild,
        ),
      ),
    ),
  );
}

CampusManagementViewModel _viewModel(
  _FakeHospitalService hospitals,
  _FakeCampusService campuses,
) {
  return CampusManagementViewModel(
    hospitalService: hospitals,
    campusService: campuses,
  );
}

void main() {
  testWidgets('加载后默认选中首个医院，右侧展示该院院区；切换医院联动', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final hospitals = _FakeHospitalService()
      ..seed('1', null, 'H001', '示例人民医院')
      ..seed('2', null, 'H002', '示例中医院');
    final campuses = _FakeCampusService()
      ..seed('1', '1', 'C001', '主院区')
      ..seed('2', '1', 'C002', '顺义院区')
      ..seed('3', '2', 'C003', '东城院区');
    final viewModel = _viewModel(hospitals, campuses);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 默认选中首个顶级医院，右侧显示其院区
    expect(viewModel.selectedNode?.name, '示例人民医院');
    expect(find.text('主院区'), findsOneWidget);
    expect(find.text('顺义院区'), findsOneWidget);
    expect(find.text('东城院区'), findsNothing);

    // 切换医院后右侧列表联动
    await tester.tap(find.text('示例中医院'));
    await tester.pumpAndSettle();
    expect(find.text('东城院区'), findsOneWidget);
    expect(find.text('主院区'), findsNothing);
  });

  testWidgets('新增院区：对话框录入代码与名称，保存后列表立即显示', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final hospitals = _FakeHospitalService()..seed('1', null, 'H001', '示例人民医院');
    final campuses = _FakeCampusService()..seed('1', '1', 'C001', '主院区');
    final viewModel = _viewModel(hospitals, campuses);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 打开新增对话框
    await tester.tap(find.byTooltip('新增院区'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('新增院区'), findsOneWidget);
    expect(find.textContaining('所属医院：示例人民医院'), findsOneWidget);

    // 代码/名称必填校验
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    expect(find.text('请输入院区代码'), findsOneWidget);

    // 录入后保存
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'C002');
    await tester.enterText(fields.at(1), '西城院区');
    await tester.enterText(fields.at(2), '西城区测试路2号');
    await tester.enterText(fields.at(3), '010-87654321');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('新增成功'), findsOneWidget);
    await tester.pumpAndSettle();

    // 列表立即显示新院区（副标题含代码与地址）
    expect(find.text('西城院区'), findsOneWidget);
    expect(find.textContaining('代码：C002'), findsOneWidget);
    expect(campuses.store['2']?.hospId, '1');
  });

  testWidgets('编辑院区：对话框回填，改名保存后列表更新', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final hospitals = _FakeHospitalService()..seed('1', null, 'H001', '示例人民医院');
    final campuses = _FakeCampusService()..seed('1', '1', 'C001', '主院区');
    final viewModel = _viewModel(hospitals, campuses);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑院区'), findsOneWidget);

    // 回填校验：名称回填原值，改名保存
    final fields = find.byType(TextFormField);
    expect((tester.widget<TextFormField>(fields.at(1)).controller as TextEditingController).text, '主院区');
    await tester.enterText(fields.at(1), '本部院区');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('修改成功'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('本部院区'), findsOneWidget);
    expect(find.text('主院区'), findsNothing);
  });

  testWidgets('删除院区：确认对话框，确认后列表移除', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final hospitals = _FakeHospitalService()..seed('1', null, 'H001', '示例人民医院');
    final campuses = _FakeCampusService()
      ..seed('1', '1', 'C001', '主院区')
      ..seed('2', '1', 'C002', '顺义院区');
    final viewModel = _viewModel(hospitals, campuses);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('删除').first);
    await tester.pumpAndSettle();
    expect(find.text('删除确认'), findsOneWidget);
    expect(find.textContaining('确定删除院区'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('删除成功'), findsOneWidget);
    await tester.pumpAndSettle();

    // 第一行（主院区）被删除，仅剩顺义院区
    expect(find.text('主院区'), findsNothing);
    expect(find.text('顺义院区'), findsOneWidget);
    expect(campuses.store, isNotEmpty);
    expect(campuses.store.containsKey('1'), isFalse);
  });
}
