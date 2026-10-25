// 行政区划设置页面切换回归测试：VM 为全局单例，页面切走再切回
// （State 重建）不得重新 loadRoots 重建整棵树——否则展开与选中状态丢失，
// 而右侧详情还指着旧树对象，出现「左侧状态清除、右侧信息残留」的不一致。
import 'package:client/models/child_info.dart';
import 'package:client/services/admin_divisions_service.dart';
import 'package:client/view_models/system/admin_division_management_view_model.dart';
import 'package:client/views/system/admin_division_management_page.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 内存版行政区划服务：create 落内存、getChildren 按 parentCode 过滤，
/// 模拟后端懒加载行为。
class _FakeAdminDivisionsService extends AdminDivisionsService {
  int getChildrenCalls = 0;
  final Map<String, String> names = {'110000': '北京市', '120000': '天津市'};
  final Map<String, String?> parents = {'110000': null, '120000': null};

  @override
  Future<List<AdminDivision>> getChildren({String? parentCode}) async {
    getChildrenCalls++;
    final codes = parents.keys.where((c) => parents[c] == parentCode).toList()..sort();
    return codes.map((c) => AdminDivision(code: c, name: names[c]!, parentCode: parents[c], hasChildren: parents.values.contains(c))).toList();
  }

  @override
  Future<AdminDivision> create({required String code, required String name, String? parentCode}) async {
    names[code] = name;
    parents[code] = parentCode;
    return AdminDivision(code: code, name: name, parentCode: parentCode, hasChildren: false);
  }

  @override
  Future<AdminDivision> update({required String code, String? newCode, String? name}) async {
    throw UnimplementedError();
  }

  @override
  Future<int> getSubtreeCount(String code) async => 1;

  @override
  Future<int> delete(String code) async => 1;
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

Widget _wrapWidget(AdminDivisionManagementViewModel viewModel) {
  return ChangeNotifierProvider<AdminDivisionManagementViewModel>.value(
    value: viewModel,
    child: MaterialApp(
      localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
      supportedLocales: const [Locale('en')],
      // 主框架内页面挂在实际 Scaffold 下（SnackBar 依赖），此处等价模拟
      home: Scaffold(
        body: AdminDivisionManagementPage(
          loginUser: const LoginUser(
            id: 1,
            userCode: 'admin',
            userName: '管理员',
            roleCode: 'ADMIN',
            phone: '',
            lastLoginAt: null,
          ),
          child: _testChild,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('页面切走再切回不重新加载树，展开与选中状态保留', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = _FakeAdminDivisionsService();
    final viewModel = AdminDivisionManagementViewModel(service: service);

    // 首次进入：加载省级并选中北京市
    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();
    expect(service.getChildrenCalls, 1);
    await tester.tap(find.text('北京市'));
    await tester.pump();
    expect(viewModel.selectedNode?.code, '110000');

    // 模拟切页：页面从树上卸载（dispose 监听）后重新挂载（State 重建）
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 树未重载（roots 非空跳过 loadRoots），选中状态保留
    expect(service.getChildrenCalls, 1);
    expect(viewModel.selectedNode?.code, '110000');
    // 树节点与右侧表单中的名称均可见（表单不再整体隐藏）
    expect(find.text('北京市'), findsWidgets);
    expect(find.text('请先在左侧选择行政区划'), findsNothing);
  });

  testWidgets('未选中行政区划时右侧信息卡片常显且内容区给提示', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = _FakeAdminDivisionsService();
    final viewModel = AdminDivisionManagementViewModel(service: service);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 卡片抬头与空态提示同时可见（卡片不再整体隐藏）
    expect(find.text('行政区划信息'), findsOneWidget);
    expect(find.text('请先在左侧选择行政区划'), findsOneWidget);
  });

  testWidgets('选中节点后添加下级行政区划：右侧表单清空录入，保存后树立即显示新节点', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = _FakeAdminDivisionsService();
    final viewModel = AdminDivisionManagementViewModel(service: service);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 选中北京市（其子级从未加载过）
    await tester.tap(find.text('北京市'));
    await tester.pump();
    expect(viewModel.selectedNode?.code, '110000');

    // 打开节点菜单，点击「添加下级区划」：不弹窗，右侧切换为新增表单
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加下级区划'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(viewModel.formMode, AdminDivisionFormMode.create);

    // 右侧表单：代码/名称为空，上级代码显示选中节点的代码（只读）
    final fields = find.byType(TextFormField);
    final codeField = tester.widget<TextFormField>(fields.at(0));
    expect((codeField.controller as TextEditingController).text, '');
    final parentField = tester.widget<TextFormField>(fields.at(2));
    expect(parentField.initialValue, '110000');

    // 录入代码与名称后添加
    await tester.enterText(fields.at(0), '110101');
    await tester.enterText(fields.at(1), '东城区');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pump(const Duration(milliseconds: 100));
    // 新增成功提示（SnackBar 有 2 秒展示定时器，展示初期断言）
    expect(find.text('新增成功'), findsOneWidget);
    await tester.pumpAndSettle();

    // 树立即显示新节点（父节点已展开），右侧表单切到新节点的编辑态
    expect(find.text('东城区'), findsWidgets);
    expect(viewModel.formMode, AdminDivisionFormMode.edit);
    expect(viewModel.selectedNode?.code, '110101');
    expect(viewModel.selectedNode!.parentCode, '110000');
  });
}
