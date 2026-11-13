// 数据字典管理页面交互回归测试：加载后左侧显示字典树、右侧数据项
// 空态提示；选中字典懒加载数据项（默认徽章）；顶级/下级新增与修改
// 走 Form 对话框；删除走确认对话框（有下级时后端阻止）；数据项设为
// 默认与删除。
import 'package:client/models/child_info.dart';
import 'package:client/services/dict_service.dart';
import 'package:client/view_models/system/dict_management_view_model.dart';
import 'package:client/views/system/dictionary_management_page.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 内存版字典服务（页面交互所需子集）。
class _FakeDictService extends DictService {
  final Map<String, Dict> dictStore = {};
  final Map<String, DictItem> itemStore = {};
  int nextDictId = 1;
  int nextItemId = 1;

  void seedDict(String id, String? parentId, String code, String name, {String? displayOrder}) {
    dictStore[id] = Dict(
      id: id,
      parentId: parentId,
      dictCode: code,
      dictName: name,
      displayOrder: displayOrder,
      creatorId: '1',
      creatorName: '系统管理员',
      hospId: '1',
      hospName: '示例人民医院',
    );
    final n = int.parse(id);
    if (n >= nextDictId) nextDictId = n + 1;
  }

  void seedItem(String id, String dictId, String code, String value, {String? displayOrder, String isDefault = '0'}) {
    itemStore[id] = DictItem(
      id: id,
      dictId: dictId,
      itemCode: code,
      itemValue: value,
      isDefault: isDefault,
      displayOrder: displayOrder,
      creatorId: '1',
      creatorName: '系统管理员',
      hospId: '1',
      hospName: '示例人民医院',
    );
    final n = int.parse(id);
    if (n >= nextItemId) nextItemId = n + 1;
  }

  @override
  Future<List<Dict>> queryAll() async {
    final list = dictStore.values.toList()..sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
    return list;
  }

  @override
  Future<Dict> create({
    required String dictCode,
    required String dictName,
    String? parentId,
    String? displayOrder,
  }) async {
    if (dictStore.values.any((d) => d.dictCode == dictCode)) {
      throw Exception('该医院下字典编码已存在：$dictCode');
    }
    final id = '${nextDictId++}';
    final d = Dict(
      id: id,
      parentId: parentId,
      dictCode: dictCode,
      dictName: dictName,
      displayOrder: displayOrder,
      creatorId: '1',
      creatorName: '系统管理员',
      hospId: '1',
      hospName: '示例人民医院',
    );
    dictStore[id] = d;
    return d;
  }

  @override
  Future<Dict> update(String id, Map<String, Object?> changes) async {
    final d = dictStore[id]!;
    final updated = Dict(
      id: d.id,
      parentId: d.parentId,
      dictCode: changes['dictCode'] as String? ?? d.dictCode,
      dictName: changes['dictName'] as String? ?? d.dictName,
      displayOrder: changes.containsKey('displayOrder') ? changes['displayOrder'] as String? : d.displayOrder,
      creatorId: d.creatorId,
      creatorName: d.creatorName,
      hospId: d.hospId,
      hospName: d.hospName,
    );
    dictStore[id] = updated;
    return updated;
  }

  @override
  Future<int> delete(String id) async {
    if (dictStore.values.any((d) => d.parentId == id)) {
      throw Exception('请先删除下级字典后，再删除该字典');
    }
    if (itemStore.values.any((i) => i.dictId == id)) {
      throw Exception('该字典下存在数据项，请先删除全部数据项');
    }
    dictStore.remove(id);
    return 1;
  }

  @override
  Future<List<DictItem>> queryItems(String dictId) async {
    final list = itemStore.values.where((i) => i.dictId == dictId).toList()..sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
    return list;
  }

  @override
  Future<DictItem> createItem({
    required String dictId,
    required String itemCode,
    required String itemValue,
    String? displayOrder,
    String isDefault = '0',
  }) async {
    if (itemStore.values.any((i) => i.dictId == dictId && i.itemCode == itemCode)) {
      throw Exception('该字典下项目编码已存在：$itemCode');
    }
    final id = '${nextItemId++}';
    final item = DictItem(
      id: id,
      dictId: dictId,
      itemCode: itemCode,
      itemValue: itemValue,
      isDefault: isDefault,
      displayOrder: displayOrder,
      creatorId: '1',
      creatorName: '系统管理员',
      hospId: '1',
      hospName: '示例人民医院',
    );
    if (isDefault == '1') {
      for (final other in itemStore.values.where((i) => i.dictId == dictId).toList()) {
        itemStore[other.id] = _withDefault(other, '0');
      }
    }
    itemStore[id] = item;
    return item;
  }

  @override
  Future<DictItem> updateItem(String id, Map<String, Object?> changes) async {
    final i = itemStore[id]!;
    final updated = DictItem(
      id: i.id,
      dictId: i.dictId,
      itemCode: changes['itemCode'] as String? ?? i.itemCode,
      itemValue: changes['itemValue'] as String? ?? i.itemValue,
      isDefault: i.isDefault,
      displayOrder: changes.containsKey('displayOrder') ? changes['displayOrder'] as String? : i.displayOrder,
      creatorId: i.creatorId,
      creatorName: i.creatorName,
      hospId: i.hospId,
      hospName: i.hospName,
    );
    itemStore[id] = updated;
    return updated;
  }

  @override
  Future<int> deleteItem(String id) async {
    itemStore.remove(id);
    return 1;
  }

  @override
  Future<DictItem> setItemDefault(String id) async {
    final target = itemStore[id]!;
    for (final other in itemStore.values.where((i) => i.dictId == target.dictId).toList()) {
      itemStore[other.id] = _withDefault(other, other.id == id ? '1' : '0');
    }
    return itemStore[id]!;
  }

  DictItem _withDefault(DictItem i, String isDefault) => DictItem(
    id: i.id,
    dictId: i.dictId,
    itemCode: i.itemCode,
    itemValue: i.itemValue,
    isDefault: isDefault,
    displayOrder: i.displayOrder,
    creatorId: i.creatorId,
    creatorName: i.creatorName,
    hospId: i.hospId,
    hospName: i.hospName,
  );
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
  id: '1',
  userCode: 'admin',
  userName: '系统管理员',
  userType: 'ADMIN',
  roleId: '',
  hospId: '1',
  hospName: '示例人民医院',
);

Widget _wrapWidget(DictManagementViewModel viewModel) {
  return ChangeNotifierProvider<DictManagementViewModel>.value(
    value: viewModel,
    child: MaterialApp(
      localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
      supportedLocales: const [Locale('en')],
      // 主框架内页面挂在实际 Scaffold 下（SnackBar 依赖），此处等价模拟
      home: Scaffold(
        body: DictionaryManagementPage(loginUser: _testLoginUser, child: _testChild),
      ),
    ),
  );
}

void main() {
  testWidgets('加载后左侧显示字典树，选中字典右侧懒加载数据项（默认徽章与顺序）', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final dictService = _FakeDictService()
      ..seedDict('1', null, 'D001', '性别', displayOrder: '1')
      ..seedDict('2', '1', 'D002', '学历层次')
      ..seedItem('1', '1', 'M', '男', displayOrder: '1')
      ..seedItem('2', '1', 'F', '女', displayOrder: '2', isDefault: '1');
    final viewModel = DictManagementViewModel(dictService: dictService);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 左树显示顶级与下级，subtitle 带编码；右侧未选中给提示
    expect(find.text('性别'), findsOneWidget);
    expect(find.text('学历层次'), findsOneWidget);
    expect(find.textContaining('D001'), findsOneWidget);
    expect(find.text('请先在左侧选择数据字典'), findsOneWidget);

    // 选中字典：右侧标题带字典名，数据项按顺序排列，默认项带徽章
    await tester.tap(find.text('性别'));
    await tester.pumpAndSettle();
    expect(find.text('数据项 · 性别'), findsOneWidget);
    expect(find.text('男'), findsOneWidget);
    expect(find.text('女'), findsOneWidget);
    expect(find.text('默认'), findsOneWidget);
    expect(find.text('M · 顺序 1'), findsOneWidget);
    expect(find.text('D001 · 顺序 1'), findsOneWidget);
  });

  testWidgets('面板头发起顶级新增：对话框录入提交后入树并提示成功', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final dictService = _FakeDictService()..seedDict('1', null, 'D001', '性别');
    final viewModel = DictManagementViewModel(dictService: dictService);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 面板头「新增顶级字典」：对话框挂载说明指向顶级，三个输入框
    await tester.tap(find.byTooltip('新增顶级字典'));
    await tester.pumpAndSettle();
    expect(find.text('新增数据字典'), findsOneWidget);
    expect(find.text('挂载到：顶级（无上级字典）'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));

    await tester.enterText(find.byType(TextFormField).at(0), 'D002');
    await tester.enterText(find.byType(TextFormField).at(1), '学历');
    await tester.enterText(find.byType(TextFormField).at(2), '2');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('新增成功'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('学历'), findsOneWidget);
    expect(dictService.dictStore['2']?.parentId, isNull);
    expect(dictService.dictStore['2']?.displayOrder, '2');
  });

  testWidgets('节点菜单发起下级新增：挂载说明指向发起节点，添加后挂其下', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final dictService = _FakeDictService()..seedDict('1', null, 'D001', '性别');
    final viewModel = DictManagementViewModel(dictService: dictService);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    final menus = find.byTooltip('更多操作...');
    expect(menus, findsNWidgets(1));
    await tester.tap(menus.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增下级字典'));
    await tester.pumpAndSettle();
    expect(find.text('挂载到：字典「性别」'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'D003');
    await tester.enterText(find.byType(TextFormField).at(1), '学历层次');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('新增成功'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(dictService.dictStore['2']?.parentId, '1');
    expect(find.text('学历层次'), findsOneWidget);
  });

  testWidgets('修改选中字典名称：保存后左侧树同步更新', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final dictService = _FakeDictService()..seedDict('1', null, 'D001', '性别');
    final viewModel = DictManagementViewModel(dictService: dictService);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 选中后从节点菜单「修改」打开编辑对话框（回填编码/名称/顺序）
    await tester.tap(find.text('性别'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作...').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改'));
    await tester.pumpAndSettle();
    expect(find.text('编辑数据字典'), findsOneWidget);

    final fields = find.byType(TextFormField);
    expect(
      (tester.widget<TextFormField>(fields.at(0)).controller as TextEditingController).text,
      'D001',
    );
    await tester.enterText(fields.at(1), '性别类别');
    await tester.tap(find.widgetWithText(FilledButton, '保 存'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('保存成功'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('性别类别'), findsWidgets);
    expect(viewModel.selectedDict?.dictName, '性别类别');
  });

  testWidgets('删除字典：确认对话框，有下级被后端阻止，清空后删除成功', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final dictService = _FakeDictService()
      ..seedDict('1', null, 'D001', '性别')
      ..seedDict('2', '1', 'D002', '学历层次')
      ..seedDict('3', null, 'D003', '民族');
    final viewModel = DictManagementViewModel(dictService: dictService);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();

    // 删除带下级的「性别」：确认后失败，SnackBar 提示且树不变
    await tester.tap(find.text('性别'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作...').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除确认'), findsOneWidget);
    expect(find.textContaining('确定删除数据字典'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('请先删除下级字典后，再删除该字典'), findsOneWidget);
    await tester.pumpAndSettle();
    // 排空错误 SnackBar 展示期，避免后续「删除成功」提示被队列延后
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    // 排空错误 SnackBar（同一测试内连续提示会被队列延后）
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first).clearSnackBars();
    await tester.pumpAndSettle();
    expect(find.text('性别'), findsWidgets);

    // 删除无下级无数据项的「民族」：成功移出树
    await tester.tap(find.text('民族'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作...').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('删除成功'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('民族'), findsNothing);
    expect(dictService.dictStore.containsKey('3'), isFalse);
  });

  testWidgets('数据项：新增对话框归属说明、行操作设为默认与删除确认', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final dictService = _FakeDictService()
      ..seedDict('1', null, 'D001', '性别')
      ..seedItem('1', '1', 'M', '男', isDefault: '1');
    final viewModel = DictManagementViewModel(dictService: dictService);

    await tester.pumpWidget(_wrapWidget(viewModel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('性别'));
    await tester.pumpAndSettle();

    // 新增数据项：对话框显示归属字典说明，提交后入列表
    await tester.tap(find.byTooltip('新增数据项'));
    await tester.pumpAndSettle();
    expect(find.text('新增数据项'), findsOneWidget);
    expect(find.text('归属字典：性别'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'F');
    await tester.enterText(find.byType(TextFormField).at(1), '女');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('新增成功'), findsOneWidget);
    await tester.pumpAndSettle();
    // 排空 SnackBar，避免后续提示被队列延后
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first).clearSnackBars();
    await tester.pumpAndSettle();
    expect(dictService.itemStore['2']?.itemValue, '女');

    // 行操作「设为默认项」：默认徽章从「男」切到「女」
    await tester.tap(find.byTooltip('设为默认项'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('已设为默认项'), findsOneWidget);
    await tester.pumpAndSettle();
    // 排空上一条 SnackBar，避免后续提示被队列延后
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first).clearSnackBars();
    await tester.pumpAndSettle();
    expect(dictService.itemStore['1']?.isDefault, '0');
    expect(dictService.itemStore['2']?.isDefault, '1');
    expect(find.text('默认'), findsOneWidget);

    // 删除「女」：确认后移出列表（定位「女」所在行内的删除按钮）
    final femaleRow = find.ancestor(of: find.text('女'), matching: find.byType(ListTile));
    await tester.tap(find.descendant(of: femaleRow, matching: find.byTooltip('删除')));
    await tester.pumpAndSettle();
    expect(find.textContaining('确定删除数据项'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('删除成功'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('女'), findsNothing);
    expect(dictService.itemStore.containsKey('2'), isFalse);
  });
}
