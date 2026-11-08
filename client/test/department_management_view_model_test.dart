// 科室管理 ViewModel 单元测试：Fake 服务构造注入，覆盖按登录用户所属
// 医院加载建树（院区层有无、下级递归、脏数据兜底）、树状态保留、表单
// 三态流转、三种挂载方式的新增参数、增删改后整表重拉与选中保持、
// 失败提示。
import 'package:client/models/department_tree_node.dart';
import 'package:client/services/campus_service.dart';
import 'package:client/services/department_service.dart';
import 'package:client/view_models/system/department_management_view_model.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存版院区服务（科室管理建树所需的子集）。
class FakeCampusService extends CampusService {
  final Map<String, Campus> store = {};
  int getByHospitalCalls = 0;

  void seed(String id, String hospId, String code, String name) {
    store[id] = Campus(id: id, hospId: hospId, code: code, name: name);
  }

  @override
  Future<List<Campus>> getByHospital(String hospId) async {
    getByHospitalCalls++;
    final list = store.values.where((c) => c.hospId == hospId).toList()..sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
    return list;
  }
}

/// 内存版科室服务：模拟后端按医院查询、按 CODE 查重。
class FakeDepartmentService extends DepartmentService {
  final Map<String, Department> store = {};
  int nextId = 1;
  int getByHospitalCalls = 0;
  Object? Function()? onCreate;
  Object? Function(String id)? onUpdate;
  Object? Function(String id)? onDelete;

  /// 最近一次新增的入参（断言挂载参数用）。
  ({String? campusId, String? parentId})? lastCreateArgs;

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
    getByHospitalCalls++;
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
    final error = onCreate?.call();
    if (error != null) throw error;
    if (store.values.any((d) => d.code == code)) {
      throw Exception('科室代码已存在：$code');
    }
    lastCreateArgs = (campusId: campusId, parentId: parentId);
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
    final error = onUpdate?.call(id);
    if (error != null) throw error;
    final d = store[id];
    if (d == null) throw Exception('科室不存在：$id');
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
    final error = onDelete?.call(id);
    if (error != null) throw error;
    store.remove(id);
    return 1;
  }
}

void main() {
  late FakeCampusService campusService;
  late FakeDepartmentService departmentService;
  late DepartmentManagementViewModel viewModel;

  setUp(() {
    campusService = FakeCampusService()
      ..seed('1', '1', 'C001', '主院区')
      ..seed('2', '1', 'C002', '顺义院区')
      ..seed('3', '2', 'C003', '别家医院的院区');
    departmentService = FakeDepartmentService()
      // 主院区：儿童保健科、儿童心理科（下级：儿童心理门诊）
      ..seed('1', '1', '1', null, 'D001', '儿童保健科')
      ..seed('2', '1', '1', null, 'D002', '儿童心理科')
      ..seed('3', '1', '1', '2', 'D003', '儿童心理门诊')
      // 顺义院区：与主院区同名科室（不同挂载点允许）
      ..seed('4', '1', '2', null, 'D004', '儿童保健科')
      // 别家医院的科室（不应出现在本院树）
      ..seed('5', '2', '3', null, 'D005', '别家医院的科室');
    viewModel = DepartmentManagementViewModel(
      campusService: campusService,
      departmentService: departmentService,
    );
  });

  test('loadData：按登录用户医院建树（医院→院区→科室→下级）', () async {
    final ok = await viewModel.loadData('1', '示例人民医院');
    expect(ok, isTrue);
    expect(viewModel.unbound, isFalse);
    expect(viewModel.hasCampuses, isTrue);

    final root = viewModel.root!;
    expect(root.type, DepartmentTreeNodeType.hospital);
    expect(root.name, '示例人民医院');
    // 医院根下仅本院两个院区节点（别家医院院区不出现）
    expect(
      root.children.map((c) => c.name).toList(),
      ['主院区', '顺义院区'],
    );
    // 主院区：两个顶级科室，儿童心理科下有一个下级
    final mainCampus = root.children.first;
    expect(
      mainCampus.children.map((c) => c.name).toList(),
      ['儿童保健科', '儿童心理科'],
    );
    expect(mainCampus.children[1].children.single.name, '儿童心理门诊');
    // 顺义院区：同名科室挂在另一挂载点
    expect(root.children[1].children.single.name, '儿童保健科');
    expect(findNoDept(root, '别家医院的科室'), isTrue);
    expect(viewModel.formMode, DepartmentFormMode.empty);
  });

  test('loadData：医院未设置院区时科室直挂医院根', () async {
    final emptyCampusService = FakeCampusService();
    final vm = DepartmentManagementViewModel(
      campusService: emptyCampusService,
      departmentService: departmentService,
    );
    await vm.loadData('9', '无院区医院');
    expect(vm.hasCampuses, isFalse);

    final root = vm.root!;
    expect(root.type, DepartmentTreeNodeType.hospital);
    // 该医院无科室数据时树仅医院根
    expect(root.children, isEmpty);

    // 直挂科室场景：医院 9 下造一条无院区科室
    departmentService.seed('9', '9', null, null, 'D009', '直挂科室');
    final vm2 = DepartmentManagementViewModel(
      campusService: emptyCampusService,
      departmentService: departmentService,
    );
    await vm2.loadData('9', '无院区医院');
    expect(vm2.root!.children.single.name, '直挂科室');
  });

  test('loadData：CAMPUS_ID 指向缺失院区的顶级科室兜底挂医院根', () async {
    departmentService.seed('6', '1', '999', null, 'D006', '孤儿挂载科室');
    await viewModel.loadData('1', '示例人民医院');
    // 两个院区节点之后，兜底科室直接挂医院根末尾
    final root = viewModel.root!;
    expect(root.children.length, 3);
    expect(root.children.last.name, '孤儿挂载科室');
  });

  test('loadData：同一医院重复加载强制重拉且保留展开与选中（切回页面刷新）', () async {
    await viewModel.loadData('1', '示例人民医院');
    final mainCampus = viewModel.root!.children.first;
    viewModel.toggleExpand(mainCampus);
    viewModel.selectNode(mainCampus.children.first);
    final campusCalls = campusService.getByHospitalCalls;
    final deptCalls = departmentService.getByHospitalCalls;

    expect(await viewModel.loadData('1', '示例人民医院'), isTrue);
    expect(campusService.getByHospitalCalls, greaterThan(campusCalls), reason: '切回页面应重拉，保证院区管理等兄弟页面改动后数据一致');
    expect(departmentService.getByHospitalCalls, greaterThan(deptCalls));
    // 折叠与选中状态保留
    expect(viewModel.root!.children.first.expanded, isFalse);
    expect(viewModel.selectedDepartment?.name, '儿童保健科');
  });

  test('loadData：重拉后兄弟页面删除的院区从树中消失', () async {
    await viewModel.loadData('1', '示例人民医院');
    expect(
      viewModel.root!.children.map((c) => c.name).toList(),
      ['主院区', '顺义院区'],
    );

    // 模拟在院区管理删除了顺义院区（其下科室一并消失）
    campusService.store.remove('2');
    departmentService.store.removeWhere((_, d) => d.campusId == '2');
    expect(await viewModel.loadData('1', '示例人民医院'), isTrue);
    expect(viewModel.root!.children.single.name, '主院区');
    // 顺义院区下唯一的科室（D004）随院区节点一起从树中消失
    expect(viewModel.root!.children.single.children.length, 2);
  });

  test('loadData：医院变化（切换账号）时强制重拉并清空选中', () async {
    await viewModel.loadData('1', '示例人民医院');
    viewModel.selectNode(viewModel.root!.children.first.children.first);

    expect(await viewModel.loadData('2', '别家医院'), isTrue);
    expect(viewModel.selectedDepartment, isNull);
    expect(viewModel.root!.children.single.name, '别家医院的院区');
  });

  test('loadData：未设置所属医院时置提示、树清空', () async {
    expect(await viewModel.loadData(null, null), isFalse);
    expect(viewModel.unbound, isTrue);
    expect(viewModel.root, isNull);
    expect(viewModel.errorMsg, contains('未设置所属医院'));

    // 再以正常医院加载可恢复
    expect(await viewModel.loadData('1', '示例人民医院'), isTrue);
    expect(viewModel.unbound, isFalse);
    expect(viewModel.errorMsg, isNull);
  });

  test('selectNode：科室节点进编辑态，医院/院区节点回空态', () async {
    await viewModel.loadData('1', '示例人民医院');
    final root = viewModel.root!;
    final mainCampus = root.children.first;

    viewModel.selectNode(mainCampus.children.first);
    expect(viewModel.formMode, DepartmentFormMode.edit);
    expect(viewModel.selectedDepartment?.code, 'D001');
    expect(viewModel.selectedLocationLabel, '所属院区：主院区');

    // 下级科室的归属说明显示上级科室
    final childDept = mainCampus.children[1].children.single;
    viewModel.selectNode(childDept);
    expect(viewModel.selectedLocationLabel, '上级科室：儿童心理科');

    // 院区/医院节点退出编辑
    viewModel.selectNode(mainCampus);
    expect(viewModel.formMode, DepartmentFormMode.empty);
    viewModel.selectNode(mainCampus.children.first);
    viewModel.selectNode(root);
    expect(viewModel.formMode, DepartmentFormMode.empty);
  });

  test('表单三态流转：挂院区新增/取消/提交后回编辑态并选中新科室', () async {
    await viewModel.loadData('1', '示例人民医院');
    final mainCampus = viewModel.root!.children.first;
    viewModel.selectNode(mainCampus.children.first);
    expect(viewModel.formMode, DepartmentFormMode.edit);

    // 从院区节点发起新增：选中保留，顶部挂载说明指向院区
    viewModel.startCreate(mainCampus);
    expect(viewModel.formMode, DepartmentFormMode.create);
    expect(viewModel.createTargetLabel, '挂载到：院区「主院区」');
    viewModel.cancelCreate();
    expect(viewModel.formMode, DepartmentFormMode.edit);

    // 提交后选中新科室并回编辑态，挂载参数 campusId 正确
    viewModel.startCreate(mainCampus);
    final ok = await viewModel.createDepartment(code: 'D010', name: '发育行为科');
    expect(ok, isTrue);
    expect(viewModel.formMode, DepartmentFormMode.edit);
    expect(viewModel.selectedDepartment?.name, '发育行为科');
    expect(departmentService.lastCreateArgs?.campusId, '1');
    expect(departmentService.lastCreateArgs?.parentId, isNull);
  });

  test('createDepartment：挂上级科室时 parentId 正确、继承说明更新', () async {
    await viewModel.loadData('1', '示例人民医院');
    final deptNode = viewModel.root!.children.first.children.first;

    viewModel.startCreate(deptNode);
    expect(viewModel.createTargetLabel, '挂载到：上级科室「儿童保健科」');
    expect(await viewModel.createDepartment(code: 'D011', name: '保健门诊'), isTrue);
    expect(departmentService.lastCreateArgs?.parentId, '1');
    expect(departmentService.lastCreateArgs?.campusId, isNull);

    // 新下级出现在树上该科室之下
    final refreshed = viewModel.root!.children.first.children.first;
    expect(refreshed.children.single.name, '保健门诊');
  });

  test('createDepartment：服务端报错时返回失败、停留新增模式并带提示', () async {
    await viewModel.loadData('1', '示例人民医院');
    viewModel.startCreate(viewModel.root!.children.first);
    departmentService.onCreate = () => Exception('科室代码已存在：D001');

    expect(await viewModel.createDepartment(code: 'D001', name: '重码科室'), isFalse);
    expect(viewModel.formMode, DepartmentFormMode.create);
    expect(viewModel.errorMsg, contains('已存在'));
    expect(viewModel.root!.children.first.children.length, 2);
  });

  test('updateDepartment：修改后树同步、选中保持', () async {
    await viewModel.loadData('1', '示例人民医院');
    final deptNode = viewModel.root!.children.first.children.first;
    viewModel.selectNode(deptNode);

    expect(await viewModel.updateDepartment('1', {'name': '儿童保健中心'}), isTrue);
    expect(viewModel.root!.children.first.children.first.name, '儿童保健中心');
    expect(viewModel.selectedDepartment?.name, '儿童保健中心');
  });

  test('updateDepartment：服务端报错时返回失败并带提示', () async {
    await viewModel.loadData('1', '示例人民医院');
    departmentService.onUpdate = (id) => Exception('科室不存在：$id');
    expect(await viewModel.updateDepartment('1', {'name': '改名'}), isFalse);
    expect(viewModel.errorMsg, contains('不存在'));
  });

  test('deleteDepartment：删除选中科室回空态；删除其他科室不影响选中', () async {
    await viewModel.loadData('1', '示例人民医院');
    final mainCampus = viewModel.root!.children.first;
    viewModel.selectNode(mainCampus.children.first);

    expect(await viewModel.deleteDepartment(mainCampus.children[1]), isTrue);
    expect(viewModel.selectedDepartment?.name, '儿童保健科');
    // 删除后树整体重建，需从新根取引用
    expect(viewModel.root!.children.first.children.length, 1);

    final remaining = viewModel.root!.children.first.children.first;
    expect(await viewModel.deleteDepartment(remaining), isTrue);
    expect(viewModel.selectedDepartment, isNull);
    expect(viewModel.root!.children.first.children, isEmpty);
  });

  test('deleteDepartment：服务端报错时返回失败并带提示', () async {
    await viewModel.loadData('1', '示例人民医院');
    final deptNode = viewModel.root!.children.first.children.first;
    departmentService.onDelete = (id) => Exception('请先删除下级科室后，再删除科室');
    expect(await viewModel.deleteDepartment(deptNode), isFalse);
    expect(viewModel.errorMsg, contains('下级科室'));
    expect(viewModel.root!.children.first.children.length, 2);
  });
}

/// 断言树中不含指定名称的科室节点（递归全树检查）。
bool findNoDept(DepartmentTreeNode node, String name) {
  var found = false;
  node.visit((n) {
    if (n.name == name) found = true;
  });
  return !found;
}
