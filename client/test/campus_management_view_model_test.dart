// 院区管理 ViewModel 单元测试：Fake 服务构造注入，覆盖医院建树与默认
// 选中、院区按医院分组、切换选中医院、增删改后整表重拉与失败提示。
import 'package:client/services/campus_service.dart';
import 'package:client/services/hospital_service.dart';
import 'package:client/view_models/system/campus_management_view_model.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// 内存版院区服务：模拟后端全量查询、按 CODE 查重、同医院名称查重。
class FakeCampusService extends CampusService {
  final Map<String, Campus> store = {};
  int nextId = 1;
  int getAllCalls = 0;
  Object? Function()? onCreate;
  Object? Function(String id)? onUpdate;
  Object? Function(String id)? onDelete;

  Campus seed(String id, String hospId, String code, String name) {
    final c = Campus(id: id, hospId: hospId, code: code, name: name, address: '测试路$id号');
    store[id] = c;
    final n = int.parse(id);
    if (n >= nextId) nextId = n + 1;
    return c;
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
    final error = onCreate?.call();
    if (error != null) throw error;
    if (store.values.any((c) => c.code == code)) {
      throw Exception('院区代码已存在：$code');
    }
    if (store.values.any((c) => c.hospId == hospId && c.name == name)) {
      throw Exception('该医院下院区名称已存在：$name');
    }
    final id = '${nextId++}';
    final c = Campus(id: id, hospId: hospId, code: code, name: name, address: address, tel: tel);
    store[id] = c;
    return c;
  }

  @override
  Future<Campus> update(String id, Map<String, Object?> changes) async {
    final error = onUpdate?.call(id);
    if (error != null) throw error;
    final c = store[id];
    if (c == null) throw Exception('院区不存在：$id');
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
    final error = onDelete?.call(id);
    if (error != null) throw error;
    store.remove(id);
    return 1;
  }
}

void main() {
  late _FakeHospitalService hospitalService;
  late FakeCampusService campusService;
  late CampusManagementViewModel viewModel;

  setUp(() {
    hospitalService = _FakeHospitalService()
      ..seed('1', null, 'H001', '示例人民医院')
      ..seed('2', '1', 'H002', '示例人民医院-第一分院')
      ..seed('3', null, 'H003', '示例中医院');
    campusService = FakeCampusService()
      ..seed('1', '1', 'C001', '主院区')
      ..seed('2', '1', 'C002', '顺义院区')
      ..seed('3', '2', 'C003', '东城院区');
    viewModel = CampusManagementViewModel(
      hospitalService: hospitalService,
      campusService: campusService,
    );
  });

  test('loadData：建树、默认选中首个顶级医院、院区按医院分组', () async {
    final ok = await viewModel.loadData();
    expect(ok, isTrue);
    expect(viewModel.hospitalTree.map((n) => n.name), ['示例人民医院', '示例中医院']);
    expect(viewModel.selectedNode?.name, '示例人民医院');
    expect(viewModel.campuses.map((c) => c.name), ['主院区', '顺义院区']);
    expect(viewModel.loading, isFalse);
  });

  test('loadData：上级缺失的孤儿医院按顶级处理', () async {
    hospitalService.seed('9', '999', 'H009', '孤儿医院');
    await viewModel.loadData();
    expect(viewModel.hospitalTree.map((n) => n.name), contains('孤儿医院'));
  });

  test('selectNode：切换医院后右侧院区列表随之切换', () async {
    await viewModel.loadData();
    final branch = viewModel.hospitalTree.first.children.single;
    viewModel.selectNode(branch);
    expect(viewModel.campuses.map((c) => c.name), ['东城院区']);

    viewModel.selectNode(viewModel.hospitalTree.last);
    expect(viewModel.campuses, isEmpty);
  });

  test('createCampus：新增到选中医院后整表重拉', () async {
    await viewModel.loadData();
    final callsBefore = campusService.getAllCalls;
    final ok = await viewModel.createCampus(code: 'C009', name: '西城院区');
    expect(ok, isTrue);
    expect(campusService.getAllCalls, greaterThan(callsBefore));
    expect(viewModel.campuses.map((c) => c.name), ['主院区', '顺义院区', '西城院区']);
    expect(campusService.store['4']?.hospId, '1');
    expect(viewModel.busy, isFalse);
  });

  test('createCampus：未选中医院直接返回失败', () async {
    final ok = await viewModel.createCampus(code: 'C009', name: '无归属院区');
    expect(ok, isFalse);
    expect(campusService.store, isNotEmpty);
  });

  test('createCampus：服务端报错时返回失败并带提示', () async {
    await viewModel.loadData();
    campusService.onCreate = () => Exception('院区代码已存在：C001');
    final ok = await viewModel.createCampus(code: 'C001', name: '重复院区');
    expect(ok, isFalse);
    expect(viewModel.errorMsg, contains('已存在'));
    expect(viewModel.campuses.length, 2);
  });

  test('updateCampus：修改后整表重拉生效', () async {
    await viewModel.loadData();
    final ok = await viewModel.updateCampus('1', {'name': '本部院区'});
    expect(ok, isTrue);
    expect(viewModel.campuses.first.name, '本部院区');
  });

  test('updateCampus：服务端报错时返回失败并带提示', () async {
    await viewModel.loadData();
    campusService.onUpdate = (id) => Exception('院区不存在：$id');
    expect(await viewModel.updateCampus('1', {'name': '改名'}), isFalse);
    expect(viewModel.errorMsg, contains('不存在'));
  });

  test('deleteCampus：删除后整表重拉、列表移除', () async {
    await viewModel.loadData();
    final ok = await viewModel.deleteCampus(campusService.store['1']!);
    expect(ok, isTrue);
    expect(viewModel.campuses.map((c) => c.name), ['顺义院区']);
  });

  test('deleteCampus：服务端报错时返回失败并带提示', () async {
    await viewModel.loadData();
    campusService.onDelete = (id) => Exception('删除失败');
    expect(await viewModel.deleteCampus(campusService.store['1']!), isFalse);
    expect(viewModel.errorMsg, contains('删除失败'));
    expect(viewModel.campuses.length, 2);
  });
}
