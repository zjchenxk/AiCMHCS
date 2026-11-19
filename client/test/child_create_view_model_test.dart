// 儿童建档 ViewModel 单元测试：Fake 服务构造注入，覆盖操作权限灰化
// （canCreate/canUpdate/canSave/canDelete）、整档载入
// 浏览态、新增/修改/删除流转、保存走新增或修改分支、监护人本地工作
// 列表增删改（不做权限控制）。
import 'package:client/services/admin_divisions_service.dart';
import 'package:client/services/child_service.dart';
import 'package:client/services/high_risk_factor_service.dart';
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

  /// 查重入参记录（断言编辑态排除自身用）。
  String? lastDuplicateCheckExcludeId;
  List<ChildInfo> Function(String? excludeId)? onDuplicateCheck;

  /// 最近一次保存携带的高危因素 ID 列表（断言整单透传用）。
  List<({String factorId, String? remark})>? lastHighRiskFactors;

  @override
  Future<List<ChildInfo>> duplicateCheck({required String name, required String sex, required String birthDate, String? excludeId}) async {
    lastDuplicateCheckExcludeId = excludeId;
    return onDuplicateCheck?.call(excludeId) ?? const [];
  }

  @override
  Future<ChildArchive> load(String id) async => archives[id]!;

  @override
  Future<ChildArchive> create({
    required ChildInfo child,
    ChildExtInfo? ext,
    List<ChildGuardianInfo> guardians = const [],
    String? photoBase64,
    String? avatarBase64,
    List<({String factorId, String? remark})>? highRiskFactors,
  }) async {
    createCalls++;
    lastHighRiskFactors = highRiskFactors;
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
    String? photoBase64,
    String? avatarBase64,
    List<({String factorId, String? remark})>? highRiskFactors,
  }) async {
    updateCalls++;
    lastUpdatedId = id;
    lastHighRiskFactors = highRiskFactors;
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

  /// 儿童已保存的高危因素记录（loadHighRiskData 回显用，默认空）。
  List<ChildHighRiskFactor> savedHighRiskFactors = const [];

  @override
  Future<List<ChildHighRiskFactor>> highRiskFactors(String childId) async => savedHighRiskFactors;
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

/// 内存版高危因素服务：字典清单可预置，quickCreate 直接构造返回项。
class FakeHighRiskFactorService extends HighRiskFactorService {
  List<BaseHighRiskFactor> dict = const [];

  /// 最近一次 quickCreate 入参（断言默认大类/颜色映射用）。
  ({String? color, String? name})? lastQuickCreate;

  @override
  Future<List<BaseHighRiskFactor>> queryAll() async => dict;

  @override
  Future<BaseHighRiskFactor> quickCreate({required String riskColor, required String riskFactorName}) async {
    lastQuickCreate = (color: riskColor, name: riskFactorName);
    return BaseHighRiskFactor(
      id: 'new-factor',
      riskFactorCategory: '其它',
      riskFactorCode: const {'黄色': '02990000', '橙色': '03990000', '红色': '04990000', '紫色': '05990000'}[riskColor] ?? '',
      riskFactorName: riskFactorName,
      riskColor: riskColor,
      creatorId: '1',
      creatorName: '系统管理员',
      hospId: '1',
      hospName: '示例人民医院',
    );
  }
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
  FakeHighRiskFactorService? highRiskFactorService,
}) {
  final menu = FakeMenuService(operationCodes);
  final child = childService ?? FakeChildService();
  return ChildCreateViewModel(
    childService: child,
    menuService: menu,
    adminDivisionsService: FakeAdminDivisionsService(),
    highRiskFactorService: highRiskFactorService ?? FakeHighRiskFactorService(),
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

  test('checkDuplicate：新增态不带 excludeId，编辑态排除自身', () async {
    final service = FakeChildService();
    final vm = _buildViewModel(operationCodes: {ChildCreateViewModel.opCreate}, childService: service);
    await vm.loadPermissions();

    // 新增态（无已载入档案）→ excludeId 为 null
    await vm.startCreate();
    service.onDuplicateCheck = (excludeId) => [ChildInfo.fromJson(_child('9').toJson())];
    final inCreate = await vm.checkDuplicate(_child(''));
    expect(inCreate, hasLength(1));
    expect(service.lastDuplicateCheckExcludeId, isNull);

    // 编辑态（已载入档案 id=1）→ excludeId 携带自身 ID
    service.archives['1'] = (_child('1'), null, const []);
    await vm.selectChild('1');
    vm.startEdit();
    await vm.checkDuplicate(_child('1'));
    expect(service.lastDuplicateCheckExcludeId, '1');
  });

  test('高危因素：互斥勾选、快速新增自动勾选并保留已选、保存透传 ID 列表', () async {
    BaseHighRiskFactor factor(String id, String color, String name) => BaseHighRiskFactor(
      id: id,
      riskFactorCode: 'CODE-$id',
      riskFactorName: name,
      riskColor: color,
      creatorId: '1',
      creatorName: '系统管理员',
      hospId: '1',
      hospName: '示例人民医院',
    );
    final dict = [
      factor('G1', '绿色', ChildCreateViewModel.noneHighRiskFactorName),
      factor('G2', '绿色', '早产儿'),
      factor('R1', '红色', '妊娠期高血压'),
      factor('Y1', '黄色', '低出生体重'),
    ];
    final riskService = FakeHighRiskFactorService()..dict = dict;
    final childService = FakeChildService();

    final vm = _buildViewModel(
      operationCodes: {ChildCreateViewModel.opCreate},
      childService: childService,
      highRiskFactorService: riskService,
    );
    await vm.loadPermissions();
    await vm.startCreate();
    await vm.loadHighRiskData();
    expect(vm.highRiskDict, hasLength(4));
    // 新增态默认勾选绿色「无高危因素」（需求：新增默认选中该项）
    expect(vm.checkedHighRiskIds, {'G1'});
    expect(vm.greenNoneChecked, isTrue);
    // Tab 标签计数排除「无高危因素」标记项（仅勾它时显示 0）
    expect(vm.savedHighRiskCount, 0);

    // 勾选绿色「无高危因素」→ 四色不灰化（仅自动清除四色勾选）
    vm.toggleHighRiskFactor(dict[0], true);
    expect(vm.checkedHighRiskIds, {'G1'});
    expect(vm.greenNoneChecked, isTrue);
    expect(vm.anyNonGreenChecked, isFalse);
    expect(vm.canToggleHighRisk(dict[2], editable: true), isTrue, reason: '互斥项不再灰化禁用');
    expect(vm.canToggleHighRisk(dict[0], editable: false), isFalse, reason: '浏览态一律禁用');

    // 反向：勾选红色项 → 绿色「无高危因素」被自动清除（仍可再勾）
    vm.toggleHighRiskFactor(dict[2], true);
    expect(vm.checkedHighRiskIds, {'R1'});
    expect(vm.greenNoneChecked, isFalse);
    expect(vm.anyNonGreenChecked, isTrue);
    expect(vm.savedHighRiskCount, 1, reason: '真实高危因素计入 Tab 计数');
    // 按色计数（快捷导航按钮展示选中项数）：红色 1、黄色 0
    expect(vm.checkedHighRiskCountOfColor('红色'), 1);
    expect(vm.checkedHighRiskCountOfColor('黄色'), 0);
    expect(vm.canToggleHighRisk(dict[0], editable: true), isTrue, reason: '四色勾选时该项也不灰化');

    // 再勾绿色「无高危因素」→ 四色勾选被清空
    vm.toggleHighRiskFactor(dict[0], true);
    expect(vm.checkedHighRiskIds, {'G1'});

    // 绿色普通项与四色可并存（仅「无高危因素」与四色互斥）
    vm.toggleHighRiskFactor(dict[2], true);
    vm.toggleHighRiskFactor(dict[1], true);
    expect(vm.checkedHighRiskIds, {'R1', 'G2'});

    // 快速新增（黄色）→ 自动勾选且保留已选项
    vm.addCreatedFactor(await riskService.quickCreate(riskColor: '黄色', riskFactorName: '新发现高危'));
    expect(vm.checkedHighRiskIds, {'R1', 'G2', 'new-factor'});
    expect(vm.highRiskDict.any((f) => f.id == 'new-factor'), isTrue);

    // 设置备注 → 随保存透传（factorId + remark）
    vm.setHighRiskRemark('R1', '需随访');
    // 取消勾选 → 备注同步清除（备注依附于选中项）
    vm.toggleHighRiskFactor(dict[2], false);
    expect(vm.highRiskRemarkOf('R1'), isEmpty);
    vm.toggleHighRiskFactor(dict[2], true);
    vm.setHighRiskRemark('R1', '需随访');
    await vm.save(child: _child(''));
    final savedIds = childService.lastHighRiskFactors!.map((f) => f.factorId).toList();
    expect(savedIds, containsAll(['R1', 'G2', 'new-factor']));
    expect(childService.lastHighRiskFactors!.firstWhere((f) => f.factorId == 'R1').remark, '需随访');
    expect(childService.lastHighRiskFactors!.every((f) => f.factorId != 'G1'), isTrue, reason: '绿色无高危因素标记项不落库');

    // 勾选绿色「无高危因素」→ 互斥清空四色勾选，其备注一并清除
    vm.toggleHighRiskFactor(dict[0], true);
    expect(vm.highRiskRemarkOf('R1'), isEmpty, reason: '互斥清除四色勾选时备注同步清理');

    // 全部取消后保存 → 显式传空列表（清空库内记录，而非"不改动"）
    vm.startEdit();
    for (final id in [...vm.checkedHighRiskIds]) {
      vm.toggleHighRiskFactor(
        dict.firstWhere((f) => f.id == id, orElse: () => dict[0]),
        false,
      );
    }
    expect(vm.checkedHighRiskIds, isEmpty);
    await vm.save(child: _child('1'));
    expect(childService.lastHighRiskFactors, isEmpty);
  });

  test('浏览态：库内无高危因素记录默认勾选绿色无高危因素，有记录按库回显（含备注）', () async {
    BaseHighRiskFactor factor(String id, String color, String name) => BaseHighRiskFactor(
      id: id,
      riskFactorCode: 'CODE-$id',
      riskFactorName: name,
      riskColor: color,
      creatorId: '1',
      creatorName: '系统管理员',
      hospId: '1',
      hospName: '示例人民医院',
    );
    final riskService = FakeHighRiskFactorService()
      ..dict = [
        factor('G1', '绿色', ChildCreateViewModel.noneHighRiskFactorName),
        factor('R1', '红色', '妊娠期高血压'),
      ];
    final childService = FakeChildService()..archives['1'] = (_child('1'), null, const []);

    final vm = _buildViewModel(
      operationCodes: {ChildCreateViewModel.opUpdate},
      childService: childService,
      highRiskFactorService: riskService,
    );
    await vm.loadPermissions();

    // 库内无记录 → 默认勾选绿色「无高危因素」标记项
    await vm.selectChild('1');
    expect(vm.browsing, isTrue);
    expect(vm.checkedHighRiskIds, {'G1'}, reason: '库内无记录时默认选中绿色无高危因素');

    // 库内有记录（带备注）→ 按库回显，不再注入默认项
    childService.savedHighRiskFactors = [
      const ChildHighRiskFactor(
        id: 'row-1',
        childId: '1',
        highRiskFactorId: 'R1',
        riskFactorCode: 'CODE-R1',
        riskFactorName: '妊娠期高血压',
        riskColor: '红色',
        remark: '需随访',
        creatorId: '1',
        creatorName: '系统管理员',
        hospId: '1',
        hospName: '示例人民医院',
      ),
    ];
    await vm.loadHighRiskData();
    expect(vm.checkedHighRiskIds, {'R1'});
    expect(vm.highRiskRemarkOf('R1'), '需随访');
  });
}
