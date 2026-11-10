// 菜单管理 ViewModel 单元测试：Fake 服务构造注入，覆盖多根建树（下级
// 递归、孤儿不展示）、空库提示、树状态保留、表单三态流转、顶级/下级
// 新增参数、增删改后整表重拉与选中保持、失败提示。
import 'package:client/models/menu_tree_node.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/view_models/system/menu_management_view_model.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存版菜单服务：模拟后端全量查询、按 ITEM_CODE 查重、类型与路由
/// 联动校验、删除下级前置校验。
class FakeMenuService extends MenuService {
  final Map<String, Menu> store = {};
  int nextId = 1;
  int queryAllCalls = 0;
  Object? Function()? onCreate;
  Object? Function(String id)? onUpdate;
  Object? Function(String id)? onDelete;

  /// 最近一次新增的入参（断言挂载参数用）。
  ({String? parentId})? lastCreateArgs;

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
    queryAllCalls++;
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
    final error = onCreate?.call();
    if (error != null) throw error;
    if (store.values.any((m) => m.itemCode == itemCode)) {
      throw Exception('项目编码已存在：$itemCode');
    }
    lastCreateArgs = (parentId: parentId);
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
    final error = onUpdate?.call(id);
    if (error != null) throw error;
    final m = store[id];
    if (m == null) throw Exception('菜单项目不存在：$id');
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
    final error = onDelete?.call(id);
    if (error != null) throw error;
    if (store.values.any((m) => m.parentId == id)) {
      throw Exception('请先删除下级项目后，再删除该项目');
    }
    store.remove(id);
    return 1;
  }
}

void main() {
  late FakeMenuService menuService;
  late MenuManagementViewModel viewModel;

  setUp(() {
    menuService = FakeMenuService()
      // 顶级模块：系统管理（下级菜单：医院管理 → 下级操作：新增医院）
      ..seed('1', null, 'M001', '系统管理', '1')
      ..seed('2', '1', 'M002', '医院管理', '2', menuRoute: '/system/hospital', menuIcon: 'local_hospital_outlined')
      ..seed('3', '2', 'M003', '新增医院', '3')
      // 另一个顶级模块（多根）
      ..seed('4', null, 'M004', '儿童管理', '1')
      // 孤儿数据（parentId 指向缺失项目，不应出现在树上）
      ..seed('5', '999', 'M005', '孤儿项目', '1');
    viewModel = MenuManagementViewModel(menuService: menuService);
  });

  test('loadData：按 parentId 建树（顶级多根、下级递归、孤儿不展示）', () async {
    expect(await viewModel.loadData(), isTrue);
    expect(viewModel.isEmpty, isFalse);

    // 两个顶级模块；孤儿项目（parentId 指向缺失项目）不展示
    expect(viewModel.roots.map((r) => r.name).toList(), ['系统管理', '儿童管理']);
    final system = viewModel.roots.first;
    expect(system.children.single.name, '医院管理');
    expect(system.children.single.children.single.name, '新增医院');
    expect(findNoMenu(viewModel.roots, '孤儿项目'), isTrue);
    expect(viewModel.formMode, MenuFormMode.empty);
  });

  test('loadData：空库时 isEmpty 置位（页面显示空态引导）', () async {
    final emptyService = FakeMenuService();
    final vm = MenuManagementViewModel(menuService: emptyService);
    expect(await vm.loadData(), isTrue);
    expect(vm.isEmpty, isTrue);
    expect(vm.roots, isEmpty);
  });

  test('loadData：重复加载强制重拉且保留展开与选中（切回页面刷新）', () async {
    await viewModel.loadData();
    final system = viewModel.roots.first;
    viewModel.toggleExpand(system);
    viewModel.selectNode(system.children.single);
    final calls = menuService.queryAllCalls;

    expect(await viewModel.loadData(), isTrue);
    expect(menuService.queryAllCalls, greaterThan(calls), reason: '切回页面应重拉，保证数据一致');
    // 折叠与选中状态保留
    expect(viewModel.roots.first.expanded, isFalse);
    expect(viewModel.selectedMenu?.itemName, '医院管理');
  });

  test('selectNode：进入编辑态，归属说明按上级/顶级显示', () async {
    await viewModel.loadData();
    final system = viewModel.roots.first;

    viewModel.selectNode(system);
    expect(viewModel.formMode, MenuFormMode.edit);
    expect(viewModel.selectedLocationLabel, '顶级项目（无上级项目）');

    // 下级菜单的归属说明显示上级项目（带类型标签）
    viewModel.selectNode(system.children.single);
    expect(viewModel.selectedLocationLabel, contains('上级项目'));
    expect(viewModel.selectedLocationLabel, contains('系统管理'));
    expect(viewModel.selectedMenu?.menuRoute, '/system/hospital');
  });

  test('表单三态流转：顶级新增/取消/提交后回编辑态并选中新项目', () async {
    await viewModel.loadData();
    viewModel.selectNode(viewModel.roots.first);
    expect(viewModel.formMode, MenuFormMode.edit);

    // 面板头发起顶级新增：选中保留，顶部挂载说明指向顶级
    viewModel.startCreate(null);
    expect(viewModel.formMode, MenuFormMode.create);
    expect(viewModel.createTargetLabel, '挂载到：顶级（无上级项目）');
    viewModel.cancelCreate();
    expect(viewModel.formMode, MenuFormMode.edit);

    // 提交后选中新项目并回编辑态，挂载参数 parentId 为空
    viewModel.startCreate(null);
    final ok = await viewModel.createMenu(
      itemCode: 'M010',
      itemName: '智力测验',
      itemType: '1',
      visible: '1',
    );
    expect(ok, isTrue);
    expect(viewModel.formMode, MenuFormMode.edit);
    expect(viewModel.selectedMenu?.itemName, '智力测验');
    expect(menuService.lastCreateArgs?.parentId, isNull);
    // 新顶级模块入树
    expect(viewModel.roots.map((r) => r.name), contains('智力测验'));
  });

  test('createMenu：挂下级时 parentId 正确、树同步更新', () async {
    await viewModel.loadData();
    final menuNode = viewModel.roots.first.children.single;

    viewModel.startCreate(menuNode);
    expect(viewModel.createTargetLabel, contains('「医院管理」'));
    expect(
      await viewModel.createMenu(
        itemCode: 'M011',
        itemName: '删除医院',
        itemType: '3',
        visible: '1',
      ),
      isTrue,
    );
    expect(menuService.lastCreateArgs?.parentId, '2');

    // 新操作出现在树上该菜单之下
    final refreshed = viewModel.roots.first.children.single;
    expect(refreshed.children.map((c) => c.name), contains('删除医院'));
  });

  test('createMenu：服务端报错时返回失败、停留新增模式并带提示', () async {
    await viewModel.loadData();
    viewModel.startCreate(null);
    menuService.onCreate = () => Exception('项目编码已存在：M001');

    expect(
      await viewModel.createMenu(
        itemCode: 'M001',
        itemName: '重码项目',
        itemType: '1',
        visible: '1',
      ),
      isFalse,
    );
    expect(viewModel.formMode, MenuFormMode.create);
    expect(viewModel.errorMsg, contains('已存在'));
    expect(viewModel.roots.length, 2);
  });

  test('updateMenu：修改后树同步、选中保持', () async {
    await viewModel.loadData();
    viewModel.selectNode(viewModel.roots.first);

    expect(await viewModel.updateMenu('1', {'itemName': '系统设置'}), isTrue);
    expect(viewModel.roots.first.name, '系统设置');
    expect(viewModel.selectedMenu?.itemName, '系统设置');
  });

  test('updateMenu：服务端报错时返回失败并带提示', () async {
    await viewModel.loadData();
    menuService.onUpdate = (id) => Exception('菜单项目不存在：$id');
    expect(await viewModel.updateMenu('1', {'itemName': '改名'}), isFalse);
    expect(viewModel.errorMsg, contains('不存在'));
  });

  test('deleteMenu：删除选中项目回空态；删除其他项目不影响选中', () async {
    await viewModel.loadData();
    viewModel.selectNode(viewModel.roots.first);

    // 删除无下级的其他顶级项目（儿童管理）不影响选中
    expect(await viewModel.deleteMenu(viewModel.roots.last), isTrue);
    expect(viewModel.selectedMenu?.itemName, '系统管理');
    expect(viewModel.roots.single.name, '系统管理');

    // 删除选中项目：先删其下级链（操作→菜单），再删模块本身，回空态
    final system = viewModel.roots.single;
    expect(await viewModel.deleteMenu(system.children.single.children.single), isTrue);
    expect(await viewModel.deleteMenu(system.children.single), isTrue);
    expect(await viewModel.deleteMenu(viewModel.roots.single), isTrue);
    expect(viewModel.selectedMenu, isNull);
    expect(viewModel.roots, isEmpty);

    // 清掉种子中的孤儿数据（不展示但计入 isEmpty）后，库空态置位
    menuService.store.remove('5');
    await viewModel.loadData();
    expect(viewModel.isEmpty, isTrue);
  });

  test('deleteMenu：存在下级时服务端报错、返回失败并带提示', () async {
    await viewModel.loadData();
    final system = viewModel.roots.first;
    menuService.onDelete = (id) => Exception('请先删除下级项目后，再删除该项目');
    expect(await viewModel.deleteMenu(system), isFalse);
    expect(viewModel.errorMsg, contains('下级项目'));
    expect(viewModel.roots.first.name, '系统管理');
  });
}

/// 断言树中不含指定名称的菜单节点（递归全树检查）。
bool findNoMenu(List<MenuTreeNode> roots, String name) {
  var found = false;
  for (final root in roots) {
    root.visit((n) {
      if (n.name == name) found = true;
    });
  }
  return !found;
}
