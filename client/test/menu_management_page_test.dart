// 菜单管理页面交互回归测试：加载后左侧显示「模块→菜单→操作」树、
// 右侧信息表单三态（未选中提示 / 编辑回填 / 新增清空带挂载说明）；
// 顶级新增与下级新增、类型联动（菜单类型出路由、操作类型无图标）、
// 删除走确认对话框。
import 'package:client/models/child_info.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/view_models/system/menu_management_view_model.dart';
import 'package:client/views/system/menu_management_page.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 内存版菜单服务（页面交互所需子集）。
class _FakeMenuService extends MenuService {
  final Map<String, Menu> store = {};
  int nextId = 1;

  void seed(
    String id,
    String? parentId,
    String itemCode,
    String itemName,
    String itemType, {
    String? menuRoute,
    String? menuIcon,
  }) {
    store[id] = Menu(
      id: id,
      parentId: parentId,
      itemCode: itemCode,
      itemName: itemName,
      itemType: itemType,
      menuRoute: menuRoute,
      menuIcon: menuIcon,
      visible: '1',
    );
    final n = int.parse(id);
    if (n >= nextId) nextId = n + 1;
  }

  @override
  Future<List<Menu>> queryAll() async {
    final list = store.values.toList()..sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
    return list;
  }

  @override
  Future<Menu> create({
    required String itemCode,
    required String itemName,
    required String itemType,
    required String visible,
    String? parentId,
    String? menuRoute,
    String? menuIcon,
  }) async {
    if (store.values.any((m) => m.itemCode == itemCode)) {
      throw Exception('项目编码已存在：$itemCode');
    }
    final id = '${nextId++}';
    final m = Menu(
      id: id,
      parentId: parentId,
      itemCode: itemCode,
      itemName: itemName,
      itemType: itemType,
      menuRoute: menuRoute,
      menuIcon: menuIcon,
      visible: visible,
    );
    store[id] = m;
    return m;
  }

  @override
  Future<Menu> update(String id, Map<String, Object?> changes) async {
    final m = store[id]!;
    final updated = Menu(
      id: m.id,
      parentId: m.parentId,
      itemCode: changes['itemCode'] as String? ?? m.itemCode,
      itemName: changes['itemName'] as String? ?? m.itemName,
      itemType: changes['itemType'] as String? ?? m.itemType,
      menuRoute: changes.containsKey('menuRoute') ? changes['menuRoute'] as String? : m.menuRoute,
      menuIcon: changes.containsKey('menuIcon') ? changes['menuIcon'] as String? : m.menuIcon,
      visible: changes['visible'] as String? ?? m.visible,
    );
    store[id] = updated;
    return updated;
  }

  @override
  Future<int> delete(String id) async {
    if (store.values.any((m) => m.parentId == id)) {
      throw Exception('请先删除下级项目后，再删除该项目');
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
  userCode: 'admin',
  userName: '系统管理员',
  userType: 'ADMIN',
  roleId: '',
  hospId: '1',
  hospName: '示例人民医院',
);

Widget _wrapWidget(MenuManagementViewModel viewModel) {
  return ChangeNotifierProvider<MenuManagementViewModel>.value(
    value: viewModel,
    child: MaterialApp(
      localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
      supportedLocales: const [Locale('en')],
      // 主框架内页面挂在实际 Scaffold 下（SnackBar 依赖），此处等价模拟
      home: Scaffold(
        body: MenuManagementPage(loginUser: _testLoginUser, child: _testChild),
      ),
    ),
  );
}

void main() {
  testWidgets('加载后左侧显示模块→菜单→操作树，选中项目右侧回填', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final menuService = _FakeMenuService()
      ..seed('1', null, 'M001', '系统管理', '1')
      ..seed('2', '1', 'M002', '医院管理', '2', menuRoute: '/system/hospital', menuIcon: 'local_hospital_outlined')
      ..seed('3', '2', 'M003', '新增医院', '3');
    final viewModel = MenuManagementViewModel(menuService: menuService);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 树逐层显示，subtitle 带类型标签与编码
    expect(find.text('系统管理'), findsOneWidget);
    expect(find.text('医院管理'), findsOneWidget);
    expect(find.text('新增医院'), findsOneWidget);
    expect(find.text('菜单 · M002'), findsOneWidget);
    expect(find.text('操作 · M003'), findsOneWidget);
    expect(find.text('请先在左侧选择菜单项目'), findsOneWidget);

    // 点击选中菜单项目：右侧表单回填（编码/名称/路由三个文本框）
    await tester.tap(find.text('医院管理'));
    await tester.pumpAndSettle();
    expect(viewModel.selectedMenu?.itemCode, 'M002');
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(3));
    expect(
      (tester.widget<TextFormField>(fields.at(0)).controller as TextEditingController).text,
      'M002',
    );
    expect(
      (tester.widget<TextFormField>(fields.at(2)).controller as TextEditingController).text,
      '/system/hospital',
    );
    // 归属说明显示上级项目
    expect(find.text('上级项目：「模块」系统管理'), findsOneWidget);
  });

  testWidgets('面板头发起顶级新增：类型切菜单出路由（可选）、图标选择器选图标，添加后入树', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final menuService = _FakeMenuService()..seed('1', null, 'M001', '系统管理', '1');
    final viewModel = MenuManagementViewModel(menuService: menuService);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 面板头「新增顶级项目」按钮发起：挂载说明指向顶级
    await tester.tap(find.byTooltip('新增顶级项目'));
    await tester.pumpAndSettle();
    expect(viewModel.formMode, MenuFormMode.create);
    expect(find.text('挂载到：顶级（无上级项目）'), findsOneWidget);

    // 默认模块类型：仅编码/名称两个文本框，无路由字段
    expect(find.byType(TextFormField), findsNWidgets(2));

    // 类型切成菜单：出现路由字段（可选）
    await tester.tap(find.text('模块'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('菜单').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(3));

    await tester.enterText(find.byType(TextFormField).at(0), 'M010');
    await tester.enterText(find.byType(TextFormField).at(1), '院区管理');

    // 打开图标选择器：搜索后点选 domain 图标（数据源 iconMap 全量）
    // （label 在装饰层不接收点击，点字段内容文本触发）
    await tester.tap(find.text('不设置（点击选择）'));
    await tester.pumpAndSettle();
    expect(find.text('选择菜单图标'), findsOneWidget);
    // 对话框搜索框是纯 TextField，且 overlay 中最后构建（.last 区别于表单 TextFormField）
    await tester.enterText(find.byType(TextField).last, 'domain');
    await tester.pump();
    // 网格项在搜索框（EditableText）之后构建，取 .last 命中图标格
    await tester.tap(find.text('domain').last);
    await tester.pumpAndSettle();

    // 路由留空提交（占位菜单可暂不配置路由）
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('新增成功'), findsOneWidget);
    await tester.pumpAndSettle();

    // 新菜单入树并进入编辑态
    expect(find.text('院区管理'), findsWidgets);
    expect(viewModel.formMode, MenuFormMode.edit);
    expect(viewModel.selectedMenu?.menuIcon, 'domain');
    expect(viewModel.selectedMenu?.menuRoute, isNull);
    expect(menuService.store['2']?.parentId, isNull);
  });

  testWidgets('类型切操作：无路由字段与图标下拉，直接添加', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final menuService = _FakeMenuService()..seed('1', null, 'M001', '系统管理', '1');
    final viewModel = MenuManagementViewModel(menuService: menuService);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 从模块节点菜单发起下级新增
    final menus = find.byTooltip('更多操作...');
    expect(menus, findsNWidgets(1));
    await tester.tap(menus.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增下级项目'));
    await tester.pumpAndSettle();
    expect(find.text('挂载到：「模块」「系统管理」'), findsOneWidget);

    // 类型切成操作：无路由字段、无图标选择入口
    await tester.tap(find.text('模块'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('操作').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('菜单图标'), findsNothing);

    await tester.enterText(find.byType(TextFormField).at(0), 'M011');
    await tester.enterText(find.byType(TextFormField).at(1), '删除模块');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('新增成功'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(menuService.store['2']?.parentId, '1');
    expect(menuService.store['2']?.itemType, '3');
  });

  testWidgets('修改选中项目名称：保存后左侧树同步更新', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final menuService = _FakeMenuService()..seed('1', null, 'M001', '系统管理', '1');
    final viewModel = MenuManagementViewModel(menuService: menuService);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('系统管理'));
    await tester.pumpAndSettle();

    // 编辑态表单回填：名称在第 2 个文本框，改名保存
    final fields = find.byType(TextFormField);
    expect(
      (tester.widget<TextFormField>(fields.at(1)).controller as TextEditingController).text,
      '系统管理',
    );
    await tester.enterText(fields.at(1), '系统设置');
    await tester.tap(find.widgetWithText(FilledButton, '保 存'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('保存成功'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('系统设置'), findsWidgets);
    expect(viewModel.selectedMenu?.itemName, '系统设置');
  });

  testWidgets('删除项目：确认对话框，确认后树移除并回空态', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final menuService = _FakeMenuService()
      ..seed('1', null, 'M001', '系统管理', '1')
      ..seed('2', null, 'M004', '儿童管理', '1');
    final viewModel = MenuManagementViewModel(menuService: menuService);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 选中第一个项目，再从其菜单删除
    await tester.tap(find.text('系统管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作...').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除确认'), findsOneWidget);
    expect(find.textContaining('确定删除菜单项目'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('删除成功'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('系统管理'), findsNothing);
    expect(find.text('儿童管理'), findsOneWidget);
    expect(find.text('请先在左侧选择菜单项目'), findsOneWidget);
    expect(menuService.store.containsKey('1'), isFalse);
  });

  testWidgets('删除有下级的项目：后端阻止，错误经 SnackBar 提示', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final menuService = _FakeMenuService()
      ..seed('1', null, 'M001', '系统管理', '1')
      ..seed('2', '1', 'M002', '医院管理', '2', menuRoute: '/system/hospital');
    final viewModel = MenuManagementViewModel(menuService: menuService);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 删除带下级的顶级模块：确认后失败，SnackBar 提示且树不变
    await tester.tap(find.text('系统管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作...').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('请先删除下级项目后，再删除该项目'), findsOneWidget);
    await tester.pumpAndSettle();
    // 树节点与编辑表单回填各显示一次（删除被阻止，二者均在）
    expect(find.text('系统管理'), findsWidgets);
    expect(menuService.store.containsKey('1'), isTrue);
  });
}
