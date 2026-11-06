// 医院管理 ViewModel 单元测试：FakeHospitalService 构造注入，覆盖扁平
// 列表建树、表单模式流转、新增（顶级/下级）后整表重拉与选中、修改本地
// 同步、级联删除后的状态清理，以及重拉时展开状态保持。
import 'package:client/models/hospital_info.dart';
import 'package:client/services/admin_divisions_service.dart';
import 'package:client/services/hospital_service.dart';
import 'package:client/view_models/system/hospital_management_view_model.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存版医院服务：模拟后端全量查询、按 CODE 查重、级联删除。
class FakeHospitalService extends HospitalService {
  final Map<String, Hospital> store = {};
  int nextId = 1;
  int getAllCalls = 0;
  Object? Function()? onCreate;
  Object? Function(String id)? onDelete;

  Hospital seed(String id, String? parentId, String code, String name) {
    final h = Hospital(
      id: id,
      parentId: parentId,
      code: code,
      name: name,
      province: '北京市',
      city: '北京市',
      county: '东城区',
      address: '测试路$id号',
      tel: '010-12345678',
    );
    store[id] = h;
    final n = int.parse(id);
    if (n >= nextId) nextId = n + 1;
    return h;
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
    final error = onCreate?.call();
    if (error != null) throw error;
    if (store.values.any((h) => h.code == code)) {
      throw Exception('组织机构代码已存在：$code');
    }
    final id = '${nextId++}';
    final h = Hospital(
      id: id,
      parentId: parentId,
      code: code,
      name: name,
      nameEn: nameEn,
      province: province,
      city: city,
      county: county,
      town: town,
      address: address,
      tel: tel,
      logoBase64: logoBase64,
      sealBase64: sealBase64,
      watermarkBase64: watermarkBase64,
    );
    store[id] = h;
    return _withFlags(h);
  }

  @override
  Future<Hospital> update(String id, Map<String, Object?> changes) async {
    final h = store[id];
    if (h == null) throw Exception('医院不存在：$id');
    String? pick(String key, String? current) => changes.containsKey(key) ? changes[key] as String? : current;

    final updated = Hospital(
      id: h.id,
      parentId: h.parentId,
      code: pick('code', h.code),
      // 必填列 null 视为不变（服务端会拒绝，Fake 简化处理）
      name: changes['name'] as String? ?? h.name,
      nameEn: pick('nameEn', h.nameEn),
      province: changes['province'] as String? ?? h.province,
      city: changes['city'] as String? ?? h.city,
      county: pick('county', h.county),
      town: pick('town', h.town),
      address: changes['address'] as String? ?? h.address,
      tel: pick('tel', h.tel),
      logoBase64: pick('logoBase64', h.logoBase64),
      sealBase64: pick('sealBase64', h.sealBase64),
      watermarkBase64: pick('watermarkBase64', h.watermarkBase64),
    );
    store[id] = updated;
    return _withFlags(updated);
  }

  @override
  Future<(Hospital, int)> getDetail(String id) async {
    final h = store[id];
    if (h == null) throw Exception('医院不存在：$id');
    var count = 0;
    void walk(String i) {
      count++;
      for (final c in store.values.where((x) => x.parentId == i).toList()) {
        walk(c.id);
      }
    }

    walk(id);
    return (_withFlags(h), count);
  }

  @override
  Future<int> delete(String id) async {
    final error = onDelete?.call(id);
    if (error != null) throw error;
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

void main() {
  late FakeHospitalService service;
  late HospitalManagementViewModel viewModel;

  setUp(() {
    service = FakeHospitalService()
      ..seed('1', null, 'H001', '示例人民医院')
      ..seed('2', '1', 'H002', '示例人民医院-第一分院')
      ..seed('3', '2', 'H003', '第一分院-社区门诊')
      ..seed('4', null, 'H004', '示例中医院');
    viewModel = HospitalManagementViewModel(
      hospitalService: service,
      divisionsService: AdminDivisionsService(),
    );
  });

  test('loadHospitals：扁平列表建树，信息表可回填', () async {
    final ok = await viewModel.loadHospitals();
    expect(ok, isTrue);
    expect(viewModel.hospitalTree.map((n) => n.name), ['示例人民医院', '示例中医院']);
    final branch = viewModel.hospitalTree.first.children.single;
    expect(branch.name, '示例人民医院-第一分院');
    expect(branch.children.single.name, '第一分院-社区门诊');
    expect(viewModel.loading, isFalse);

    viewModel.selectNode(branch);
    expect(viewModel.selectedHospitalInfo?.code, 'H002');
    expect(viewModel.selectedHospitalInfo?.county, '东城区');
  });

  test('loadHospitals：上级缺失的孤儿节点按顶级处理', () async {
    service.seed('5', '999', 'H005', '孤儿医院');
    await viewModel.loadHospitals();
    expect(viewModel.hospitalTree.map((n) => n.name), contains('孤儿医院'));
  });

  test('表单模式流转：新增/取消/选中切换/提交后回编辑态', () async {
    await viewModel.loadHospitals();
    expect(viewModel.formMode, HospitalFormMode.empty);

    final root = viewModel.hospitalTree.first;
    viewModel.selectNode(root);
    expect(viewModel.formMode, HospitalFormMode.edit);

    // 添加下级：切新增模式，目标父级为选中节点，选中节点保留（树上高亮）
    viewModel.startCreate(parent: root);
    expect(viewModel.formMode, HospitalFormMode.create);
    expect(viewModel.creatingParentNode, same(root));
    expect(viewModel.selectedNode, same(root));

    // 取消：回到选中医院的编辑态
    viewModel.cancelCreate();
    expect(viewModel.formMode, HospitalFormMode.edit);

    // 添加顶级：目标父级为空
    viewModel.startCreate();
    expect(viewModel.formMode, HospitalFormMode.create);
    expect(viewModel.creatingParentNode, isNull);

    final info = HospitalInfo(id: '', parentId: null, code: 'H100', name: '新顶级医院', province: '北京市', city: '北京市', address: '新路1号');
    final ok = await viewModel.createHospital(info);
    expect(ok, isTrue);
    expect(viewModel.formMode, HospitalFormMode.edit);
    expect(viewModel.selectedNode?.name, '新顶级医院');
  });

  test('createHospital：新增下级后整表重拉、选中新节点并展开可见', () async {
    await viewModel.loadHospitals();
    final callsBefore = service.getAllCalls;
    final root = viewModel.hospitalTree.first;
    viewModel.startCreate(parent: root);

    final info = HospitalInfo(id: '', parentId: root.id, code: 'H100', name: '第二分院', province: '北京市', city: '北京市', address: '新路2号');
    final ok = await viewModel.createHospital(info);

    expect(ok, isTrue);
    expect(service.getAllCalls, greaterThan(callsBefore));
    expect(viewModel.selectedNode?.name, '第二分院');
    expect(viewModel.selectedNode?.parentId, root.id);
    expect(viewModel.busy, isFalse);
    // 树上父节点下可见新节点（重拉后节点对象重建，从当前树断言）
    final rootAfter = viewModel.hospitalTree.first;
    expect(rootAfter.id, root.id);
    expect(rootAfter.children.map((n) => n.name), contains('第二分院'));
    expect(rootAfter.expanded, isTrue, reason: '父节点应保持展开使新节点可见');
  });

  test('createHospital：服务端报错时返回失败、停留在新增模式并带提示', () async {
    await viewModel.loadHospitals();
    viewModel.startCreate();
    service.onCreate = () => Exception('组织机构代码已存在：H001');

    final info = HospitalInfo(id: '', code: 'H001', name: '重复医院', province: '北京市', city: '北京市', address: '新路3号');
    final ok = await viewModel.createHospital(info);
    expect(ok, isFalse);
    expect(viewModel.formMode, HospitalFormMode.create);
    expect(viewModel.errorMsg, contains('已存在'));
    expect(viewModel.hospitalTree.length, 2);
  });

  test('updateHospital：本地同步树节点名称与信息', () async {
    await viewModel.loadHospitals();
    final root = viewModel.hospitalTree.first;
    viewModel.selectNode(root);

    final info = HospitalInfo.fromHospital(service.store['1']!)..name = '示例人民医院（新）';
    final ok = await viewModel.updateHospital(info);
    expect(ok, isTrue);
    expect(root.name, '示例人民医院（新）');
    expect(viewModel.selectedHospitalInfo?.name, '示例人民医院（新）');
  });

  test('updateHospital：服务端报错时返回失败并带提示', () async {
    await viewModel.loadHospitals();
    final info = HospitalInfo(id: '999', name: '不存在');
    final ok = await viewModel.updateHospital(info);
    expect(ok, isFalse);
    expect(viewModel.errorMsg, contains('不存在'));
  });

  test('deleteHospital：级联删除后重建树，选中被删子树时清空、兄弟不受影响', () async {
    await viewModel.loadHospitals();
    final root = viewModel.hospitalTree.first;
    final branch = root.children.single;
    // 选中被删子树中的孙节点
    viewModel.selectNode(branch.children.single);
    expect(viewModel.selectedNode?.name, '第一分院-社区门诊');

    final ok = await viewModel.deleteHospital(branch);
    expect(ok, isTrue);
    expect(viewModel.selectedNode, isNull);
    expect(viewModel.hospitalTree.first.children, isEmpty);
    expect(viewModel.hospitalTree.map((n) => n.name), ['示例人民医院', '示例中医院']);
  });

  test('deleteHospital：服务端报错时返回失败并带提示', () async {
    await viewModel.loadHospitals();
    final root = viewModel.hospitalTree.first;
    service.onDelete = (id) => Exception('删除失败');
    expect(await viewModel.deleteHospital(root), isFalse);
    expect(viewModel.errorMsg, contains('删除失败'));
    expect(viewModel.hospitalTree.length, 2);
  });

  test('整表重拉保持展开状态：折叠的节点保持折叠，新节点默认展开', () async {
    await viewModel.loadHospitals();
    final root = viewModel.hospitalTree.first;
    viewModel.toggleExpand(root);
    expect(root.expanded, isFalse);

    // 新增兄弟顶级（触发整表重拉）
    final info = HospitalInfo(id: '', code: 'H100', name: '新医院', province: '北京市', city: '北京市', address: '新路4号');
    await viewModel.createHospital(info);

    final rootAfter = viewModel.hospitalTree.first;
    expect(rootAfter.id, root.id);
    expect(rootAfter.expanded, isFalse, reason: '折叠状态应跨重拉保持');
    expect(rootAfter.children, isNotEmpty);
    expect(viewModel.hospitalTree.last.expanded, isTrue, reason: '新节点默认展开');
  });

  test('subtreeCount：透传服务端子树规模（含自身）', () async {
    await viewModel.loadHospitals();
    expect(await viewModel.subtreeCount(viewModel.hospitalTree.first), 3);
    expect(await viewModel.subtreeCount(viewModel.hospitalTree.last), 1);
  });
}
