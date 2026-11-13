// 数据字典管理 ViewModel 单元测试：Fake 服务构造注入，覆盖多根建树
// （下级递归、显示顺序排序）、选中字典驱动右侧数据项懒加载、新增挂载
// 参数、增删改后整表重拉与选中保持、删除前置校验、数据项增删改与默认
// 项互斥、失败提示。
import 'package:client/services/dict_service.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/view_models/system/dict_management_view_model.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存版菜单服务：仅覆写操作权限查询（字典 VM 只用到该接口），
/// 默认全量授权、既有数据流用例不关心权限差异。
class FakeMenuService extends MenuService {
  FakeMenuService({Set<String>? operationCodes}) : _operationCodes = operationCodes ?? _allOperationCodes;

  static final Set<String> _allOperationCodes = {
    DictManagementViewModel.opCreateDict,
    DictManagementViewModel.opUpdateDict,
    DictManagementViewModel.opDeleteDict,
    DictManagementViewModel.opCreateItem,
    DictManagementViewModel.opUpdateItem,
    DictManagementViewModel.opDeleteItem,
  };

  final Set<String> _operationCodes;
  int queryCalls = 0;

  @override
  Future<Set<String>> queryOperationCodes() async {
    queryCalls++;
    return {..._operationCodes};
  }
}

/// 内存版字典服务：模拟后端查询、同医院字典编码/同字典项目编码查重、
/// 删除前置校验、默认项互斥。
class FakeDictService extends DictService {
  final Map<String, Dict> dictStore = {};
  final Map<String, DictItem> itemStore = {};
  int nextDictId = 1;
  int nextItemId = 1;
  int queryAllCalls = 0;
  Object? Function()? onCreateDict;
  Object? Function(String id)? onDeleteDict;
  Object? Function()? onCreateItem;

  /// 最近一次字典新增的入参（断言挂载参数用）。
  ({String? parentId})? lastCreateDictArgs;

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
    queryAllCalls++;
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
    final error = onCreateDict?.call();
    if (error != null) throw error;
    if (dictStore.values.any((d) => d.dictCode == dictCode)) {
      throw Exception('该医院下字典编码已存在：$dictCode');
    }
    lastCreateDictArgs = (parentId: parentId);
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
    final error = onDeleteDict?.call(id);
    if (error != null) throw error;
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
    final error = onCreateItem?.call();
    if (error != null) throw error;
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
    // 置默认时同字典互斥清位
    if (isDefault == '1') {
      for (final other in itemStore.values.where((i) => i.dictId == dictId)) {
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
    for (final other in itemStore.values.where((i) => i.dictId == target.dictId)) {
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

/// 清空微任务队列（Fake 服务全为内存操作，两轮零延时足够
/// selectNode 内部未 await 的数据项刷新完成）。
Future<void> flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('loadData 组树：多根、下级递归、按显示顺序排序（未设置靠后），选中字典驱动右侧数据项按顺序排序', () async {
    final service = FakeDictService()
      ..seedDict('1', null, 'D002', '学历', displayOrder: '2')
      ..seedDict('2', '1', 'D004', '全日制')
      ..seedDict('3', null, 'D001', '性别', displayOrder: '1')
      ..seedItem('1', '3', 'M', '男', displayOrder: '2')
      ..seedItem('2', '3', 'F', '女', displayOrder: '1')
      ..seedItem('3', '3', 'U', '未知');

    final viewModel = DictManagementViewModel(menuService: FakeMenuService(), dictService: service);
    expect(await viewModel.loadData(), isTrue);
    expect(viewModel.isEmpty, isFalse);

    // 顶级按显示顺序：性别(1) 在前、学历(2) 在后
    expect(viewModel.roots.map((r) => r.name), ['性别', '学历']);
    // 下级递归
    expect(viewModel.roots[1].children.map((c) => c.name), ['全日制']);

    // 选中字典后右侧数据项懒加载：女(1) → 男(2) → 未知(未设置靠后)
    viewModel.selectNode(viewModel.roots[0]);
    await flushMicrotasks();
    expect(viewModel.selectedDict?.dictCode, 'D001');
    expect(viewModel.itemsLoading, isFalse);
    expect(viewModel.items.map((i) => i.itemValue), ['女', '男', '未知']);
    expect(viewModel.items.where((i) => i.isDefault == '1'), isEmpty);
  });

  test('createDict：挂载目标随请求下发，新增后整表重拉并选中新字典', () async {
    final service = FakeDictService()..seedDict('1', null, 'D001', '性别');
    final viewModel = DictManagementViewModel(menuService: FakeMenuService(), dictService: service);
    await viewModel.loadData();

    viewModel.startCreate(service.dictStore['1'] != null ? viewModel.roots[0] : null);
    final created = await viewModel.createDict(dictCode: 'D002', dictName: '学历', displayOrder: '5');
    expect(created, isTrue);
    expect(service.lastCreateDictArgs?.parentId, '1');
    expect(viewModel.selectedNode?.name, '学历');
    expect(viewModel.roots[0].children.map((c) => c.name), ['学历']);

    // 顶级新增：parentId 为空
    viewModel.startCreate(null);
    await viewModel.createDict(dictCode: 'D003', dictName: '民族');
    expect(service.lastCreateDictArgs?.parentId, isNull);
  });

  test('updateDict：改名后树同步更新且选中保持；重码失败置错误提示', () async {
    final service = FakeDictService()..seedDict('1', null, 'D001', '性别');
    final viewModel = DictManagementViewModel(menuService: FakeMenuService(), dictService: service);
    await viewModel.loadData();
    viewModel.selectNode(viewModel.roots[0]);

    final ok = await viewModel.updateDict('1', {'dictName': '性别类别'});
    expect(ok, isTrue);
    expect(viewModel.roots.single.name, '性别类别');
    expect(viewModel.selectedNode?.name, '性别类别');
    expect(service.queryAllCalls, 2, reason: '增改后整表重拉');

    service.onCreateDict = () => Exception('该医院下字典编码已存在：D001');
    expect(await viewModel.createDict(dictCode: 'D001', dictName: '重码'), isFalse);
    expect(viewModel.errorMsg, contains('字典编码已存在'));
    viewModel.clearError();
    expect(viewModel.errorMsg, isNull);
  });

  test('deleteDict：有下级字典或数据项时被阻止（返回 false 并提示），逐层清空后成功回退', () async {
    final service = FakeDictService()
      ..seedDict('1', null, 'D001', '性别')
      ..seedDict('2', '1', 'D002', '学历层次')
      ..seedItem('1', '2', 'P', '小学');
    final viewModel = DictManagementViewModel(menuService: FakeMenuService(), dictService: service);
    await viewModel.loadData();
    viewModel.selectNode(viewModel.roots[0]);
    await flushMicrotasks();

    // 下级字典阻止
    expect(await viewModel.deleteDict(viewModel.roots[0]), isFalse);
    expect(viewModel.errorMsg, '请先删除下级字典后，再删除该字典');
    viewModel.clearError();

    // 删掉下级字典前先删其数据项，再逐层删除；选中节点被删后回退空态
    expect(await viewModel.deleteItem(service.itemStore['1']!), isTrue);
    expect(await viewModel.deleteDict(viewModel.roots[0].children.single), isTrue);
    expect(await viewModel.deleteDict(viewModel.roots[0]), isTrue);
    expect(viewModel.selectedNode, isNull);
    expect(viewModel.selectedDict, isNull);
    expect(viewModel.items, isEmpty);
    expect(viewModel.isEmpty, isTrue);
  });

  test('数据项增删改与设默认：同字典默认互斥、重码失败提示', () async {
    final service = FakeDictService()..seedDict('1', null, 'D001', '性别');
    final viewModel = DictManagementViewModel(menuService: FakeMenuService(), dictService: service);
    await viewModel.loadData();
    viewModel.selectNode(viewModel.roots[0]);
    await flushMicrotasks();

    // 新增默认项
    expect(
      await viewModel.createItem(itemCode: 'M', itemValue: '男', displayOrder: '1', isDefault: '1'),
      isTrue,
    );
    expect(viewModel.items.single.isDefault, '1');

    // 再新增普通项：默认项保持
    await viewModel.createItem(itemCode: 'F', itemValue: '女');
    expect(viewModel.items.map((i) => i.isDefault), ['1', '0']);

    // 未选中字典时新增数据项直接失败
    final viewModel2 = DictManagementViewModel(menuService: FakeMenuService(), dictService: service);
    expect(await viewModel2.createItem(itemCode: 'X', itemValue: '无归属'), isFalse);

    // 新增带默认标记的数据项：原默认项互斥清位
    await viewModel.createItem(itemCode: 'U', itemValue: '未知', isDefault: '1');
    expect(viewModel.items.map((i) => i.isDefault), ['0', '0', '1']);

    // 修改与重码失败
    expect(await viewModel.updateItem(viewModel.items.first.id, {'itemValue': '男性'}), isTrue);
    expect(viewModel.items.first.itemValue, '男性');
    service.onCreateItem = () => Exception('该字典下项目编码已存在：M');
    expect(await viewModel.createItem(itemCode: 'M', itemValue: '重码'), isFalse);
    expect(viewModel.errorMsg, contains('项目编码已存在'));
    service.onCreateItem = null;
    viewModel.clearError();

    // 设默认与删除：M 重获默认，删除后剩 F、U
    expect(await viewModel.setItemDefault(viewModel.items.first), isTrue);
    expect(viewModel.items.map((i) => i.isDefault), ['1', '0', '0']);
    expect(await viewModel.deleteItem(viewModel.items.first), isTrue);
    expect(viewModel.items.map((i) => i.itemCode), ['F', 'U']);
  });

  test('loadData 拉取角色操作权限：canXxx getter 按 6 个操作权限编码判定，全未授权时按钮全隐藏', () async {
    final dictService = FakeDictService()..seedDict('1', null, 'D001', '性别');
    final menuService = FakeMenuService(
      operationCodes: {
        DictManagementViewModel.opCreateDict,
        DictManagementViewModel.opCreateItem,
        DictManagementViewModel.opDeleteItem,
      },
    );
    final viewModel = DictManagementViewModel(dictService: dictService, menuService: menuService);
    expect(await viewModel.loadData(), isTrue);
    // 每次进页重拉权限（loadData 内恰好调用一次）
    expect(menuService.queryCalls, 1);
    expect(viewModel.canCreateDict, isTrue);
    expect(viewModel.canUpdateDict, isFalse);
    expect(viewModel.canDeleteDict, isFalse);
    expect(viewModel.canCreateItem, isTrue);
    expect(viewModel.canUpdateItem, isFalse);
    expect(viewModel.canDeleteItem, isTrue);

    // 全未授权：全部按钮隐藏（权限未知时不放行）
    final none = DictManagementViewModel(
      dictService: dictService,
      menuService: FakeMenuService(operationCodes: {}),
    );
    expect(await none.loadData(), isTrue);
    expect(none.canCreateDict, isFalse);
    expect(none.canUpdateDict, isFalse);
    expect(none.canDeleteDict, isFalse);
    expect(none.canCreateItem, isFalse);
    expect(none.canUpdateItem, isFalse);
    expect(none.canDeleteItem, isFalse);
  });
}
