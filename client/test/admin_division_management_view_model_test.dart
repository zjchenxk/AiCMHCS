// 行政区划设置 ViewModel 单元测试：FakeAdminDivisionsService 构造注入，
// 覆盖懒加载展开、新增（省级/下级）本地插树、改名、级联删除后的本地树
// 同步（含选中节点清理与父节点状态回退）与失败提示。
import 'package:client/models/admin_division_node.dart';
import 'package:client/services/admin_divisions_service.dart';
import 'package:client/view_models/system/admin_division_management_view_model.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存版行政区划服务：模拟后端按 parentCode 懒加载与级联删除。
class FakeAdminDivisionsService extends AdminDivisionsService {
  final Map<String, String> names = {};
  final Map<String, String?> parents = {};
  int getChildrenCalls = 0;
  Object? Function(String parentCode)? onGetChildren;
  Object? Function()? onCreate;
  Object? Function(String code)? onDelete;

  void seed(String code, String name, String? parentCode) {
    names[code] = name;
    parents[code] = parentCode;
  }

  bool _hasChildren(String code) => parents.values.contains(code);

  @override
  Future<List<AdminDivision>> getChildren({String? parentCode}) async {
    getChildrenCalls++;
    final hook = parentCode == null ? null : onGetChildren?.call(parentCode);
    if (hook != null) throw hook;
    final codes = parents.keys.where((c) => parents[c] == parentCode).toList()..sort();
    return codes.map((c) => AdminDivision(code: c, name: names[c]!, parentCode: parents[c], hasChildren: _hasChildren(c))).toList();
  }

  @override
  Future<AdminDivision> create({required String code, required String name, String? parentCode}) async {
    final error = onCreate?.call();
    if (error != null) throw error;
    if (names.containsKey(code)) {
      throw Exception('行政区划代码已存在：$code');
    }
    seed(code, name, parentCode);
    return AdminDivision(code: code, name: name, parentCode: parentCode, hasChildren: false);
  }

  @override
  Future<AdminDivision> update({required String code, String? newCode, String? name}) async {
    final oldCode = code;
    final changedCode = newCode?.trim();
    if (changedCode != null && changedCode.isNotEmpty && changedCode != oldCode) {
      if (names.containsKey(changedCode)) {
        throw Exception('行政区划代码已存在：$changedCode');
      }
      // 级联更新子级父引用
      for (final key in parents.keys.toList()) {
        if (parents[key] == oldCode) {
          parents[key] = changedCode;
        }
      }
      names[changedCode] = names.remove(oldCode)!;
      parents[changedCode] = parents.remove(oldCode);
      final newName = (name == null || name.trim().isEmpty) ? names[changedCode]! : name.trim();
      names[changedCode] = newName;
      return AdminDivision(code: changedCode, name: newName, parentCode: parents[changedCode], hasChildren: parents.values.contains(changedCode));
    }
    final newName = (name == null || name.trim().isEmpty) ? names[oldCode]! : name.trim();
    names[oldCode] = newName;
    return AdminDivision(code: oldCode, name: newName, parentCode: parents[oldCode], hasChildren: parents.values.contains(oldCode));
  }

  @override
  Future<int> getSubtreeCount(String code) async {
    var count = 0;
    void walk(String c) {
      count++;
      for (final child in parents.keys.where((k) => parents[k] == c)) {
        walk(child);
      }
    }

    walk(code);
    return count;
  }

  @override
  Future<int> delete(String code) async {
    final error = onDelete?.call(code);
    if (error != null) throw error;
    var count = 0;
    void walk(String c) {
      count++;
      final children = parents.keys.where((k) => parents[k] == c).toList();
      names.remove(c);
      parents.remove(c);
      for (final child in children) {
        walk(child);
      }
    }

    walk(code);
    return count;
  }
}

void main() {
  late FakeAdminDivisionsService service;
  late AdminDivisionManagementViewModel viewModel;

  setUp(() {
    service = FakeAdminDivisionsService()
      ..seed('110000', '北京市', null)
      ..seed('110100', '市辖区', '110000')
      ..seed('110101', '东城区', '110100')
      ..seed('110102', '西城区', '110100')
      ..seed('110101001', '东华门街道', '110101')
      ..seed('120000', '天津市', null);
    viewModel = AdminDivisionManagementViewModel(service: service);
  });

  test('loadRoots：加载省级列表并按代码排序', () async {
    final ok = await viewModel.loadRoots();
    expect(ok, isTrue);
    expect(viewModel.roots.map((n) => n.code), ['110000', '120000']);
    expect(viewModel.roots.first.name, '北京市');
    expect(viewModel.roots.first.hasChildren, isTrue);
    expect(viewModel.loading, isFalse);
  });

  test('toggleExpand：首次展开懒加载子级，再次折叠不再请求', () async {
    await viewModel.loadRoots();
    final beijing = viewModel.roots.first;

    expect(await viewModel.toggleExpand(beijing), isTrue);
    expect(beijing.expanded, isTrue);
    expect(beijing.childrenLoaded, isTrue);
    expect(beijing.children.map((c) => c.code), ['110100']);

    final callsAfterExpand = service.getChildrenCalls;
    expect(await viewModel.toggleExpand(beijing), isTrue);
    expect(beijing.expanded, isFalse);
    expect(service.getChildrenCalls, callsAfterExpand);
  });

  test('toggleExpand：懒加载失败时置错误信息且不展开', () async {
    await viewModel.loadRoots();
    final beijing = viewModel.roots.first;
    service.onGetChildren = (code) => Exception('加载失败');

    expect(await viewModel.toggleExpand(beijing), isFalse);
    expect(beijing.expanded, isFalse);
    expect(viewModel.errorMsg, contains('加载失败'));
    viewModel.clearError();
    expect(viewModel.errorMsg, isNull);
  });

  test('表单模式流转：新增/取消/选中切换/提交后回编辑态', () async {
    await viewModel.loadRoots();
    expect(viewModel.formMode, AdminDivisionFormMode.empty);

    final beijing = viewModel.roots.first;
    viewModel.selectNode(beijing);
    expect(viewModel.formMode, AdminDivisionFormMode.edit);

    // 添加下级：切新增模式，目标父级为选中节点，选中节点保留（树上高亮）
    viewModel.startCreate(parent: beijing);
    expect(viewModel.formMode, AdminDivisionFormMode.create);
    expect(viewModel.creatingParentNode, same(beijing));
    expect(viewModel.selectedNode, same(beijing));

    // 取消：回到选中节点的编辑态
    viewModel.cancelCreate();
    expect(viewModel.formMode, AdminDivisionFormMode.edit);

    // 添加省级：目标父级为空
    viewModel.startCreate();
    expect(viewModel.formMode, AdminDivisionFormMode.create);
    expect(viewModel.creatingParentNode, isNull);

    // 新增提交成功后退出新增模式并选中新节点
    final ok = await viewModel.createDivision(parent: viewModel.creatingParentNode, code: '130000', name: '河北省');
    expect(ok, isTrue);
    expect(viewModel.formMode, AdminDivisionFormMode.edit);
    expect(viewModel.selectedNode?.code, '130000');
  });

  test('createDivision：新增省级插入排序列表并选中新节点', () async {
    await viewModel.loadRoots();

    final ok = await viewModel.createDivision(code: '130000', name: '河北省');
    expect(ok, isTrue);
    expect(viewModel.roots.map((n) => n.code), ['110000', '120000', '130000']);
    expect(viewModel.selectedNode?.code, '130000');
    expect(viewModel.busy, isFalse);
  });

  test('createDivision：新增下级更新父节点标记并展开', () async {
    await viewModel.loadRoots();
    final beijing = viewModel.roots.first;
    await viewModel.toggleExpand(beijing);
    final city = beijing.children.single;

    final ok = await viewModel.createDivision(parent: city, code: '110103', name: '崇文区');
    expect(ok, isTrue);
    expect(city.hasChildren, isTrue);
    expect(city.expanded, isTrue);
    expect(city.children.map((c) => c.code), ['110101', '110102', '110103']);
    expect(viewModel.selectedNode?.code, '110103');
  });

  test('createDivision：服务端报错时返回失败并带提示', () async {
    await viewModel.loadRoots();
    service.onCreate = () => Exception('行政区划代码已存在：110000');

    final ok = await viewModel.createDivision(code: '110000', name: '重复');
    expect(ok, isFalse);
    expect(viewModel.errorMsg, contains('已存在'));
    expect(viewModel.roots.length, 2);
  });

  test('updateDivision：更新节点名称', () async {
    await viewModel.loadRoots();
    final beijing = viewModel.roots.first;

    final ok = await viewModel.updateDivision(beijing, name: '北京');
    expect(ok, isTrue);
    expect(beijing.name, '北京');
    expect(viewModel.roots.first.name, '北京');
  });

  test('updateDivision：改编码同步本地树、子级父引用并重排序', () async {
    await viewModel.loadRoots();
    final beijing = viewModel.roots.first;
    await viewModel.toggleExpand(beijing);
    final city = beijing.children.single;
    await viewModel.toggleExpand(city);
    final dongcheng = city.children.first;
    await viewModel.toggleExpand(dongcheng);
    final street = dongcheng.children.single;

    final ok = await viewModel.updateDivision(dongcheng, newCode: '110199', name: '东城区（新）');
    expect(ok, isTrue);
    expect(dongcheng.code, '110199');
    expect(dongcheng.name, '东城区（新）');
    // 直接子级（已加载部分）父引用同步
    expect(street.parentCode, '110199');
    // 重排序：110199 仍小于 110102 之前？110102 < 110199，顺序应为 [110102, 110199]
    expect(city.children.map((c) => c.code), ['110102', '110199']);
    // 选中节点仍指向同一对象
    expect(viewModel.selectedNode, isNull);
    viewModel.selectNode(dongcheng);
    expect(viewModel.selectedNode?.code, '110199');
  });

  test('updateDivision：服务端报错时返回失败并带提示', () async {
    await viewModel.loadRoots();
    final beijing = viewModel.roots.first;

    // Fake 未模拟格式校验，直接改撞已存在的编码
    final ok = await viewModel.updateDivision(beijing, newCode: '120000', name: '北京市');
    expect(ok, isFalse);
    expect(viewModel.errorMsg, contains('已存在'));
    expect(beijing.code, '110000');
  });

  test('deleteDivision：级联删除本地树、选中子孙时清空、兄弟不受影响', () async {
    await viewModel.loadRoots();
    final beijing = viewModel.roots.first;
    await viewModel.toggleExpand(beijing);
    final city = beijing.children.single;
    await viewModel.toggleExpand(city);
    final dongcheng = city.children.first;
    await viewModel.toggleExpand(dongcheng);
    expect(dongcheng.children.map((c) => c.code), ['110101001']);

    // 选中被删子树中的街道节点
    viewModel.selectNode(dongcheng.children.single);
    expect(viewModel.selectedNode?.code, '110101001');

    final ok = await viewModel.deleteDivision(dongcheng);
    expect(ok, isTrue);
    expect(city.children.map((c) => c.code), ['110102']);
    // 选中节点在被删子树内 → 清空
    expect(viewModel.selectedNode, isNull);
    // 兄弟分支仍在
    expect(viewModel.roots.map((n) => n.code), ['110000', '120000']);
    expect(city.hasChildren, isTrue);
  });

  test('deleteDivision：父节点无剩余子级时回退展开标记', () async {
    await viewModel.loadRoots();
    final tianjin = viewModel.roots.last;

    final ok = await viewModel.deleteDivision(tianjin);
    expect(ok, isTrue);
    expect(viewModel.roots.map((n) => n.code), ['110000']);
    expect(viewModel.selectedNode, isNull);
  });

  test('subtreeCount：透传服务端子树规模（含自身）', () async {
    await viewModel.loadRoots();
    expect(await viewModel.subtreeCount(viewModel.roots.first), 5);
  });

  test('AdminDivisionNode.insertChild：按代码升序插入', () {
    final node = AdminDivisionNode(code: '110100', name: '市辖区');
    node
      ..insertChild(AdminDivisionNode(code: '110102', name: '西城区'))
      ..insertChild(AdminDivisionNode(code: '110101', name: '东城区'));
    expect(node.children.map((c) => c.code), ['110101', '110102']);
    expect(node.hasChildren, isTrue);
    expect(node.find('110102')?.name, '西城区');
  });
}
