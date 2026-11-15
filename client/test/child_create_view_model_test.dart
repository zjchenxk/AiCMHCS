// 儿童建档 ViewModel 单元测试：Fake 服务构造注入，覆盖操作权限灰化
// （canCreate/canUpdate/canSave/canDelete）、整档载入
// 浏览态、新增/修改/删除流转、保存走新增或修改分支、监护人本地工作
// 列表增删改（不做权限控制）。
import 'package:client/services/admin_divisions_service.dart';
import 'package:client/services/child_service.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/view_models/child/child_create_view_model.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存版菜单服务：仅覆写操作权限查询。
class FakeMenuService extends MenuService {
  FakeMenuService(this.operationCodes);

  final Set<String> operationCodes;
  int queryCalls = 0;

  @override
  Future<Set<String>> queryOperationCodes() async {
    queryCalls++;
    return {...operationCodes};
  }
}

/// 内存版儿童服务：整档存取 + 调用计数。
class FakeChildService extends ChildService {
  final Map<String, ChildArchive> archives = {};
  int nextId = 1;
  int createCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;
  String? lastUpdatedId;

  @override
  Future<ChildArchive> load(String id) async => archives[id]!;

  @override
  Future<ChildArchive> create({
    required ChildInfo child,
    ChildExtInfo? ext,
    List<ChildGuardianInfo> guardians = const [],
  }) async {
    createCalls++;
    final id = '${nextId++}';
    final stored = ChildInfo.fromJson(child.toJson()..['id'] = id);
    archives[id] = (stored, ext, guardians);
    return archives[id]!;
  }

  @override
  Future<ChildArchive> update({
    required String id,
    required ChildInfo child,
    ChildExtInfo? ext,
    List<ChildGuardianInfo> guardians = const [],
  }) async {
    updateCalls++;
    lastUpdatedId = id;
    final stored = ChildInfo.fromJson(child.toJson()..['id'] = id);
    archives[id] = (stored, ext, guardians);
    return archives[id]!;
  }

  @override
  Future<int> delete(String id) async {
    deleteCalls++;
    archives.remove(id);
    return 1;
  }
}

/// 内存版行政区划服务：两级级联即可覆盖回显用例。
class FakeAdminDivisionsService extends AdminDivisionsService {
  @override
  Future<List<Province>?> getProvinces() async => [
    Province(code: '110000', name: '北京市', cities: const []),
  ];

  @override
  Future<List<City>?> getCitiesByProvince(String provinceCode) async => [
    City(code: '110100', name: '北京市', counties: const []),
  ];

  @override
  Future<List<County>?> getCountiesByCity(String cityCode) async => [
    County(code: '110101', name: '东城区', towns: const []),
  ];

  @override
  Future<List<Town>?> getTownsByCounty(String countyCode) async => const [];

  @override
  Future<List<Village>?> getVillagesByTown(String townCode) async => const [];
}

ChildInfo _child(String id) => ChildInfo(
  id: id,
  checkTime: '2026-11-14 09:30:00',
  visitCardNo: 'JZK202601001',
  patientId: null,
  ecardId: null,
  name: '王小明',
  sex: '1',
  birthDate: '2026-01-01',
  birthTime: null,
  country: null,
  nation: null,
  certificateType: null,
  certificateNo: null,
  healthNo: null,
  mchisHealthNo: null,
  addressProvince: '北京市',
  addressCity: '北京市',
  addressCounty: '东城区',
  addressTown: null,
  addressVillage: null,
  addressDetails: '景山前街4号',
  addressCode: '110101',
  phone: null,
  creatorId: '9',
  creatorName: '张医生',
  hospId: '1',
  hospName: '示例人民医院',
);

ChildCreateViewModel _buildViewModel({
  required Set<String> operationCodes,
  FakeChildService? childService,
}) {
  final menu = FakeMenuService(operationCodes);
  final child = childService ?? FakeChildService();
  return ChildCreateViewModel(
    childService: child,
    menuService: menu,
    adminDivisionsService: FakeAdminDivisionsService(),
  );
}

void main() {
  test('loadPermissions：按角色操作码给出按钮权限与查询区显隐', () async {
    final all = _buildViewModel(
      operationCodes: {
        ChildCreateViewModel.opCreate,
        ChildCreateViewModel.opUpdate,
        ChildCreateViewModel.opSave,
        ChildCreateViewModel.opDelete,
      },
    );
    await all.loadPermissions();
    expect(all.canCreate, isTrue);
    expect(all.canUpdate, isTrue);
    expect(all.canSave, isTrue);
    expect(all.canDelete, isTrue);

    final createOnly = _buildViewModel(operationCodes: {ChildCreateViewModel.opCreate});
    await createOnly.loadPermissions();
    expect(createOnly.canCreate, isTrue);
    expect(createOnly.canUpdate, isFalse);
    expect(createOnly.canSave, isFalse);
    expect(createOnly.canDelete, isFalse);

    final none = _buildViewModel(operationCodes: <String>{});
    await none.loadPermissions();
    expect(none.canCreate, isFalse);
    expect(none.canUpdate, isFalse);
    expect(none.canSave, isFalse);
    expect(none.canDelete, isFalse);
  });

  test('selectChild：载入整档进入浏览态并回显省级区划', () async {
    final service = FakeChildService();
    service.archives['1'] = (_child('1'), null, const []);
    final vm = _buildViewModel(operationCodes: {ChildCreateViewModel.opUpdate, ChildCreateViewModel.opDelete}, childService: service);
    await vm.loadPermissions();

    final ok = await vm.selectChild('1');
    expect(ok, isTrue);
    expect(vm.mode, ChildFormMode.browse);
    expect(vm.browsing, isTrue);
    expect(vm.child?.name, '王小明');
    expect(vm.selectedProvince?.name, '北京市');
    expect(vm.selectedCity?.name, '北京市');
    expect(vm.selectedCounty?.name, '东城区');
    expect(vm.addressCode, '110101');
  });

  test('startCreate/save：新增态清空数据，保存走新增并回到浏览态', () async {
    final service = FakeChildService();
    final vm = _buildViewModel(operationCodes: {ChildCreateViewModel.opCreate}, childService: service);
    await vm.loadPermissions();

    await vm.startCreate();
    expect(vm.creating, isTrue);
    expect(vm.child, isNull);
    expect(vm.guardians, isEmpty);

    final draft = _child('');
    final ok = await vm.save(child: draft, ext: null);
    expect(ok, isTrue);
    expect(service.createCalls, 1);
    expect(service.updateCalls, 0);
    expect(vm.mode, ChildFormMode.browse);
    expect(vm.child?.id, '1');
    expect(vm.guardians, isEmpty);
  });

  test('save：修改态走修改分支并携带档案 ID', () async {
    final service = FakeChildService();
    service.archives['1'] = (_child('1'), null, const []);
    final vm = _buildViewModel(operationCodes: {ChildCreateViewModel.opUpdate}, childService: service);
    await vm.loadPermissions();
    await vm.selectChild('1');
    vm.startEdit();
    expect(vm.editing, isTrue);

    final draft = _child('1');
    final ok = await vm.save(child: draft, ext: null);
    expect(ok, isTrue);
    expect(service.updateCalls, 1);
    expect(service.lastUpdatedId, '1');
    expect(vm.browsing, isTrue);
  });

  test('cancelEdit：未载入档案回空态，已载入档案重载回浏览态', () async {
    final service = FakeChildService();
    service.archives['1'] = (_child('1'), null, const []);
    final vm = _buildViewModel(operationCodes: {ChildCreateViewModel.opUpdate}, childService: service);
    await vm.loadPermissions();

    await vm.startCreate();
    await vm.cancelEdit();
    expect(vm.mode, ChildFormMode.empty);

    await vm.selectChild('1');
    vm.startEdit();
    await vm.cancelEdit();
    expect(vm.browsing, isTrue);
    expect(vm.child?.id, '1');
  });

  test('deleteCurrent：删除后回到空态并清空工作数据', () async {
    final service = FakeChildService();
    service.archives['1'] = (_child('1'), null, const []);
    final vm = _buildViewModel(operationCodes: {ChildCreateViewModel.opDelete}, childService: service);
    await vm.loadPermissions();
    await vm.selectChild('1');

    final ok = await vm.deleteCurrent();
    expect(ok, isTrue);
    expect(service.deleteCalls, 1);
    expect(vm.mode, ChildFormMode.empty);
    expect(vm.child, isNull);
    expect(vm.guardians, isEmpty);
  });

  test('guardians：本地工作列表增改删不受权限限制，随 save 整单携带', () async {
    final service = FakeChildService();
    final vm = _buildViewModel(operationCodes: {ChildCreateViewModel.opCreate}, childService: service);
    await vm.loadPermissions();
    await vm.startCreate();

    vm.addOrUpdateGuardian(
      ChildGuardianInfo(
        childId: '',
        name: '王大壮',
        guardianRelationship: '父亲',
        creatorId: '',
        creatorName: '',
        hospId: '',
        hospName: '',
      ),
    );
    expect(vm.guardians, hasLength(1));

    final updated = ChildGuardianInfo(
      childId: '',
      name: '王大壮',
      birthDate: '1990-05-01',
      guardianRelationship: '父亲',
      phone: '13900139000',
      creatorId: '',
      creatorName: '',
      hospId: '',
      hospName: '',
    );
    vm.addOrUpdateGuardian(updated, index: 0);
    expect(vm.guardians, hasLength(1), reason: '按下标替换本地未入库行');
    expect(vm.guardians.first.phone, '13900139000');

    vm.removeGuardianAt(0);
    expect(vm.guardians, isEmpty);

    // 整单保存携带监护人
    vm.addOrUpdateGuardian(updated);
    await vm.save(child: _child(''));
    expect(service.createCalls, 1);
    expect(service.archives['1']!.$3, hasLength(1));
    expect(service.archives['1']!.$3.first.name, '王大壮');
  });
}
