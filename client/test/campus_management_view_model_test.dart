// 院区管理 ViewModel 单元测试：Fake 服务构造注入，覆盖按登录用户所属
// 医院加载（同医院跳过/换医院重拉/未绑定提示）、表单三态流转、增删改
// 后整表重拉与选中保持、失败提示。
import 'package:client/services/campus_service.dart';
import 'package:client/view_models/system/campus_management_view_model.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存版院区服务：模拟后端按医院查询、按 CODE 查重、同医院名称查重。
class FakeCampusService extends CampusService {
  final Map<String, Campus> store = {};
  int nextId = 1;
  int getByHospitalCalls = 0;
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
  Future<List<Campus>> getByHospital(String hospId) async {
    getByHospitalCalls++;
    final list = store.values.where((c) => c.hospId == hospId).toList()..sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
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
      hospId: c.hospId,
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
  late FakeCampusService campusService;
  late CampusManagementViewModel viewModel;

  setUp(() {
    campusService = FakeCampusService()
      ..seed('1', '1', 'C001', '主院区')
      ..seed('2', '1', 'C002', '顺义院区')
      ..seed('3', '2', 'C003', '别家医院的院区');
    viewModel = CampusManagementViewModel(campusService: campusService);
  });

  test('loadData：按登录用户医院过滤，仅显示本院院区', () async {
    final ok = await viewModel.loadData('1');
    expect(ok, isTrue);
    expect(viewModel.campuses.map((c) => c.name), ['主院区', '顺义院区']);
    expect(viewModel.unbound, isFalse);
    expect(viewModel.loading, isFalse);
    expect(viewModel.formMode, CampusFormMode.empty);
  });

  test('loadData：同一医院重复加载跳过（切页保留状态）', () async {
    await viewModel.loadData('1');
    viewModel.selectCampus(viewModel.campuses.first);
    final calls = campusService.getByHospitalCalls;

    final ok = await viewModel.loadData('1');
    expect(ok, isTrue);
    expect(campusService.getByHospitalCalls, calls, reason: '同一医院不应重拉');
    expect(viewModel.selectedCampus?.name, '主院区', reason: '选中状态保留');
  });

  test('loadData：医院变化（切换账号）时强制重拉并清空选中', () async {
    await viewModel.loadData('1');
    viewModel.selectCampus(viewModel.campuses.first);

    final ok = await viewModel.loadData('2');
    expect(ok, isTrue);
    expect(viewModel.campuses.map((c) => c.name), ['别家医院的院区']);
    expect(viewModel.selectedCampus, isNull);
  });

  test('loadData：未设置所属医院时置提示、列表清空', () async {
    expect(await viewModel.loadData(null), isFalse);
    expect(viewModel.unbound, isTrue);
    expect(viewModel.campuses, isEmpty);
    expect(viewModel.errorMsg, contains('未设置所属医院'));

    // 再以正常医院加载可恢复
    expect(await viewModel.loadData('1'), isTrue);
    expect(viewModel.unbound, isFalse);
    expect(viewModel.errorMsg, isNull);
  });

  test('表单三态流转：选中/新增/取消/提交后回编辑态', () async {
    await viewModel.loadData('1');
    expect(viewModel.formMode, CampusFormMode.empty);

    viewModel.selectCampus(viewModel.campuses.first);
    expect(viewModel.formMode, CampusFormMode.edit);

    // 新增模式：选中保留（列表高亮），取消回到编辑态
    viewModel.startCreate();
    expect(viewModel.formMode, CampusFormMode.create);
    expect(viewModel.selectedCampus?.name, '主院区');
    viewModel.cancelCreate();
    expect(viewModel.formMode, CampusFormMode.edit);

    // 新增提交后选中新院区并回编辑态
    viewModel.startCreate();
    final ok = await viewModel.createCampus(code: 'C009', name: '西城院区');
    expect(ok, isTrue);
    expect(viewModel.formMode, CampusFormMode.edit);
    expect(viewModel.selectedCampus?.name, '西城院区');
    expect(campusService.store['4']?.hospId, '1');
  });

  test('createCampus：未绑定医院直接返回失败', () async {
    final vm = CampusManagementViewModel(campusService: campusService);
    expect(await vm.createCampus(code: 'C009', name: '无归属'), isFalse);
    expect(campusService.store.length, 3);
  });

  test('createCampus：服务端报错时返回失败、停留新增模式并带提示', () async {
    await viewModel.loadData('1');
    viewModel.startCreate();
    campusService.onCreate = () => Exception('院区代码已存在：C001');

    final ok = await viewModel.createCampus(code: 'C001', name: '重复院区');
    expect(ok, isFalse);
    expect(viewModel.formMode, CampusFormMode.create);
    expect(viewModel.errorMsg, contains('已存在'));
    expect(viewModel.campuses.length, 2);
  });

  test('updateCampus：修改后整表重拉、选中同步', () async {
    await viewModel.loadData('1');
    viewModel.selectCampus(viewModel.campuses.first);
    final ok = await viewModel.updateCampus('1', {'name': '本部院区'});
    expect(ok, isTrue);
    expect(viewModel.campuses.first.name, '本部院区');
    expect(viewModel.selectedCampus?.name, '本部院区');
  });

  test('updateCampus：服务端报错时返回失败并带提示', () async {
    await viewModel.loadData('1');
    campusService.onUpdate = (id) => Exception('院区不存在：$id');
    expect(await viewModel.updateCampus('1', {'name': '改名'}), isFalse);
    expect(viewModel.errorMsg, contains('不存在'));
  });

  test('deleteCampus：删除选中院区后回退空态；删除他院院区不影响选中', () async {
    await viewModel.loadData('1');
    viewModel.selectCampus(viewModel.campuses.first);
    expect(await viewModel.deleteCampus(campusService.store['1']!), isTrue);
    expect(viewModel.selectedCampus, isNull);
    expect(viewModel.campuses.map((c) => c.name), ['顺义院区']);

    viewModel.selectCampus(viewModel.campuses.first);
    expect(await viewModel.deleteCampus(campusService.store['3']!), isTrue);
    expect(viewModel.selectedCampus?.name, '顺义院区');
  });

  test('deleteCampus：服务端报错时返回失败并带提示', () async {
    await viewModel.loadData('1');
    campusService.onDelete = (id) => Exception('删除失败');
    expect(await viewModel.deleteCampus(campusService.store['1']!), isFalse);
    expect(viewModel.errorMsg, contains('删除失败'));
    expect(viewModel.campuses.length, 2);
  });
}
