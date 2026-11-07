// 医院管理页面交互回归测试：添加下级医院不弹窗、在右侧信息表单录入
// （与行政区划一致的交互）；页面切走再切回不重新加载树；删除走确认
// 对话框并级联清理。
import 'package:client/models/child_info.dart';
import 'package:client/services/admin_divisions_service.dart';
import 'package:client/services/hospital_service.dart';
import 'package:client/view_models/system/hospital_management_view_model.dart';
import 'package:client/views/system/hospital_management_page.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 内存版医院服务（仅页面交互所需子集）。
class _FakeHospitalService extends HospitalService {
  final Map<String, Hospital> store = {};
  int nextId = 1;
  int getAllCalls = 0;

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
    final n = int.parse(id);
    if (n >= nextId) nextId = n + 1;
  }

  bool _hasChildren(String id) => store.values.any((h) => h.parentId == id);

  Hospital _withFlags(Hospital h) => Hospital(
    id: h.id,
    parentId: h.parentId,
    code: h.code,
    name: h.name,
    nameEn: h.nameEn,
    province: h.province,
    city: h.city,
    county: h.county,
    town: h.town,
    address: h.address,
    tel: h.tel,
    logoBase64: h.logoBase64,
    sealBase64: h.sealBase64,
    watermarkBase64: h.watermarkBase64,
    hasChildren: _hasChildren(h.id),
  );

  @override
  Future<List<Hospital>> getAll() async {
    getAllCalls++;
    final list = store.values.toList()..sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
    return list.map(_withFlags).toList();
  }

  @override
  Future<Hospital> create({
    String? parentId,
    required String code,
    required String name,
    String? nameEn,
    required String province,
    required String city,
    String? county,
    String? town,
    required String address,
    String? tel,
    String? logoBase64,
    String? sealBase64,
    String? watermarkBase64,
  }) async {
    final id = '${nextId++}';
    final h = Hospital(
      id: id,
      parentId: parentId,
      code: code,
      name: name,
      province: province,
      city: city,
      county: county,
      address: address,
      tel: tel,
    );
    store[id] = h;
    return _withFlags(h);
  }

  @override
  Future<Hospital> update(String id, Map<String, Object?> changes) async {
    final h = store[id]!;
    final updated = Hospital(
      id: h.id,
      parentId: h.parentId,
      code: changes['code'] as String? ?? h.code,
      name: changes['name'] as String? ?? h.name,
      nameEn: changes.containsKey('nameEn') ? changes['nameEn'] as String? : h.nameEn,
      province: changes['province'] as String? ?? h.province,
      city: changes['city'] as String? ?? h.city,
      county: changes.containsKey('county') ? changes['county'] as String? : h.county,
      town: changes.containsKey('town') ? changes['town'] as String? : h.town,
      address: changes['address'] as String? ?? h.address,
      tel: changes.containsKey('tel') ? changes['tel'] as String? : h.tel,
    );
    store[id] = updated;
    return _withFlags(updated);
  }

  @override
  Future<(Hospital, int, int)> getDetail(String id) async {
    var count = 0;
    void walk(String i) {
      count++;
      for (final c in store.values.where((x) => x.parentId == i).toList()) {
        walk(c.id);
      }
    }

    walk(id);
    return (_withFlags(store[id]!), count, 0);
  }

  @override
  Future<int> delete(String id) async {
    var count = 0;
    void walk(String i) {
      count++;
      final children = store.values.where((x) => x.parentId == i).map((x) => x.id).toList();
      store.remove(i);
      for (final c in children) {
        walk(c);
      }
    }

    walk(id);
    return count;
  }
}

/// 内存版行政区划服务（表单地址级联所需子集）。
class _FakeAdminDivisionsService extends AdminDivisionsService {
  @override
  Future<List<Province>?> getProvinces() async => [Province(code: '110000', name: '北京市', cities: const [])];

  @override
  Future<List<City>?> getCitiesByProvince(String provinceCode) async => [City(code: '110100', name: '市辖区', counties: const [])];

  @override
  Future<List<County>?> getCountiesByCity(String cityCode) async => [County(code: '110101', name: '东城区', towns: const [])];

  @override
  Future<List<Town>?> getTownsByCounty(String countyCode) async => [];
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

Widget _wrapWidget(HospitalManagementViewModel viewModel) {
  return ChangeNotifierProvider<HospitalManagementViewModel>.value(
    value: viewModel,
    child: MaterialApp(
      localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
      supportedLocales: const [Locale('en')],
      // 主框架内页面挂在实际 Scaffold 下（SnackBar 依赖），此处等价模拟
      home: Scaffold(
        body: HospitalManagementPage(
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

HospitalManagementViewModel _viewModel(
  _FakeHospitalService service, {
  AdminDivisionsService? divisionsService,
}) {
  return HospitalManagementViewModel(
    hospitalService: service,
    divisionsService: divisionsService ?? _FakeAdminDivisionsService(),
  );
}

void main() {
  testWidgets('页面切走再切回不重新加载树，选中状态保留', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = _FakeHospitalService()
      ..seed('1', null, 'H001', '示例人民医院')
      ..seed('2', null, 'H002', '示例中医院');
    final viewModel = _viewModel(service);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();
    expect(service.getAllCalls, 1);
    await tester.tap(find.text('示例人民医院'));
    await tester.pump();
    expect(viewModel.selectedNode?.name, '示例人民医院');

    // 模拟切页：页面从树上卸载（dispose 监听）后重新挂载（State 重建）
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 树未重载（hospitalTree 非空跳过 loadHospitals），选中状态保留
    expect(service.getAllCalls, 1);
    expect(viewModel.selectedNode?.name, '示例人民医院');
    expect(find.text('请先在左侧选择医院'), findsNothing);
  });

  testWidgets('未选中医院时右侧信息卡片常显且内容区给提示', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = _FakeHospitalService()..seed('1', null, 'H001', '示例人民医院');
    final viewModel = _viewModel(service);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    expect(find.text('医院信息'), findsOneWidget);
    expect(find.text('请先在左侧选择医院'), findsOneWidget);
  });

  testWidgets('添加下级医院：不弹窗，右侧表单清空录入，提交后树立即显示新节点', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = _FakeHospitalService()
      ..seed('1', null, 'H001', '示例人民医院')
      ..seed('2', '1', 'H002', '示例人民医院-第一分院');
    final viewModel = _viewModel(service);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 打开节点菜单，点击「添加下级医院」：不弹窗，右侧切换为新增表单
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加下级医院'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(viewModel.formMode, HospitalFormMode.create);

    // 右侧表单：代码/名称为空，上级医院显示选中节点名称（只读）
    final fields = find.byType(TextFormField);
    final codeField = tester.widget<TextFormField>(fields.at(0));
    expect((codeField.controller as TextEditingController).text, '');
    final parentField = tester.widget<TextFormField>(fields.at(3));
    expect(parentField.initialValue, '示例人民医院');

    // 依次选择省/市/县（表单校验必填；按各下拉提示文本定位，选中上一级
    // 后下一级选项加载、提示文本随之变化）
    await tester.pumpAndSettle();
    await tester.tap(find.text('请选择省/自治区/直辖市'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('北京市').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('请选择市/自治州/地区'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('市辖区').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('请选择县/区/旗'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('东城区').last);
    await tester.pumpAndSettle();

    // 录入其余必填项后添加
    await tester.enterText(fields.at(0), 'H999');
    await tester.enterText(fields.at(1), '儿童心理分院');
    await tester.enterText(fields.at(4), '心理路1号');
    await tester.enterText(fields.at(5), '010-99999999');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pump(const Duration(milliseconds: 100));
    // 新增成功提示（SnackBar 有 2 秒展示定时器，展示初期断言）
    expect(find.text('新增成功'), findsOneWidget);
    await tester.pumpAndSettle();

    // 树立即显示新节点，右侧表单切到新节点的编辑态
    expect(find.text('儿童心理分院'), findsWidgets);
    expect(viewModel.formMode, HospitalFormMode.edit);
    expect(viewModel.selectedNode?.name, '儿童心理分院');
    expect(viewModel.selectedNode?.parentId, '1');
  });

  testWidgets('修改选中医院名称：保存后左树同步更新', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = _FakeHospitalService()..seed('1', null, 'H001', '示例人民医院');
    final viewModel = _viewModel(service);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('示例人民医院'));
    await tester.pumpAndSettle();

    // 编辑态表单回填：名称在第 2 个文本框，改名保存
    final fields = find.byType(TextFormField);
    expect((tester.widget<TextFormField>(fields.at(1)).controller as TextEditingController).text, '示例人民医院');
    await tester.enterText(fields.at(1), '示例儿童医院');
    await tester.tap(find.widgetWithText(FilledButton, '保 存'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('保存成功'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('示例儿童医院'), findsWidgets);
    expect(viewModel.selectedNode?.name, '示例儿童医院');
  });

  testWidgets('删除医院：确认对话框提示子树规模，确认后级联删除', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = _FakeHospitalService()
      ..seed('1', null, 'H001', '示例人民医院')
      ..seed('2', '1', 'H002', '示例人民医院-第一分院');
    final viewModel = _viewModel(service);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('示例人民医院'));
    await tester.pumpAndSettle();

    // 打开选中节点菜单删除
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    // 确认对话框提示将级联删除 2 所（含自身）
    expect(find.text('删除确认'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('共 2 所医院'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('删除成功'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('示例人民医院'), findsNothing);
    expect(find.text('请先在左侧选择医院'), findsOneWidget);
    expect(viewModel.hospitalTree, isEmpty);
  });
}
