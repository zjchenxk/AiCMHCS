// 儿童建档 ViewModel 单元测试：Fake 服务构造注入，覆盖操作权限灰化
// （canCreate/canUpdate/canSave/canDelete）、整档载入
// 浏览态、新增/修改/删除流转、保存走新增或修改分支、监护人本地工作
// 列表增删改（不做权限控制）。
import 'package:client/services/admin_divisions_service.dart';
import 'package:client/services/child_service.dart';
import 'package:client/services/high_risk_factor_exclusion_service.dart';
import 'package:client/services/high_risk_factor_service.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/utils/high_risk_auto_screening.dart';
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

/// 内存版高危因素互斥规则服务：规则清单可预置。
class FakeHighRiskFactorExclusionService extends HighRiskFactorExclusionService {
  List<BaseHighRiskFactorExclusion> rules = const [];

  @override
  Future<List<BaseHighRiskFactorExclusion>> queryAll() async => rules;
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

/// 构造扩展信息草稿（自动筛查用例只需触发字段，其余缺省为空）。
ChildExtInfo _extInfo({
  String? gestationalWeek,
  String? birthWeight,
  String? apgar5,
  String? intracranialHemorrhageLevel,
  String? birthDefect06d,
  String? birthDefect728d,
  String? sgaType,
  String? hasSpontaneousAbortionHistory,
  String? hasInducedAbortionHistory,
  String? hasRecurrentAbortionHistory,
  String? hasPretermBirthHistory,
  String? hasFetalDeadHistory,
  String? hasStillbirthHistory,
  String? hasFetalMalformationHistory,
  String? conceptionMethod,
  String? hasDiabetes,
  String? hasGestationalHypertension,
  String? hasCmvInfection,
  String? hasHyperthyroidismInPregnancy,
  String? hasHypothyroidismInPregnancy,
  String? hasHivInfection,
  String? hasSyphilisInfection,
  String? parity,
  String? maternalAgeAtDelivery,
  String? hasParentalDrugAbuseHistory,
}) => ChildExtInfo(
  childId: '',
  creatorId: '',
  creatorName: '',
  hospId: '',
  hospName: '',
  gestationalWeek: gestationalWeek,
  birthWeight: birthWeight,
  apgar5: apgar5,
  intracranialHemorrhageLevel: intracranialHemorrhageLevel,
  birthDefect06d: birthDefect06d,
  birthDefect728d: birthDefect728d,
  sgaType: sgaType,
  hasSpontaneousAbortionHistory: hasSpontaneousAbortionHistory,
  hasInducedAbortionHistory: hasInducedAbortionHistory,
  hasRecurrentAbortionHistory: hasRecurrentAbortionHistory,
  hasPretermBirthHistory: hasPretermBirthHistory,
  hasFetalDeadHistory: hasFetalDeadHistory,
  hasStillbirthHistory: hasStillbirthHistory,
  hasFetalMalformationHistory: hasFetalMalformationHistory,
  conceptionMethod: conceptionMethod,
  hasDiabetes: hasDiabetes,
  hasGestationalHypertension: hasGestationalHypertension,
  hasCmvInfection: hasCmvInfection,
  hasHyperthyroidismInPregnancy: hasHyperthyroidismInPregnancy,
  hasHypothyroidismInPregnancy: hasHypothyroidismInPregnancy,
  hasHivInfection: hasHivInfection,
  hasSyphilisInfection: hasSyphilisInfection,
  parity: parity,
  maternalAgeAtDelivery: maternalAgeAtDelivery,
  hasParentalDrugAbuseHistory: hasParentalDrugAbuseHistory,
);

ChildCreateViewModel _buildViewModel({
  required Set<String> operationCodes,
  FakeChildService? childService,
  FakeHighRiskFactorService? highRiskFactorService,
  FakeHighRiskFactorExclusionService? highRiskFactorExclusionService,
}) {
  final menu = FakeMenuService(operationCodes);
  final child = childService ?? FakeChildService();
  return ChildCreateViewModel(
    childService: child,
    menuService: menu,
    adminDivisionsService: FakeAdminDivisionsService(),
    highRiskFactorService: highRiskFactorService ?? FakeHighRiskFactorService(),
    highRiskFactorExclusionService: highRiskFactorExclusionService ?? FakeHighRiskFactorExclusionService(),
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

  test('高危因素规则表互斥：同组三选一自动清除冲突项与备注，组外项不受影响', () async {
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
    BaseHighRiskFactorExclusion rule(String id, String first, String second, [String? third]) => BaseHighRiskFactorExclusion(
      id: id,
      firstRiskFactorId: first,
      secondRiskFactorId: second,
      thirdRiskFactorId: third,
      creatorId: '1',
      creatorName: '系统管理员',
      hospId: '1',
      hospName: '示例人民医院',
    );
    final dict = [
      factor('G1', '绿色', ChildCreateViewModel.noneHighRiskFactorName),
      factor('Y1', '黄色', '早产(出生胎龄34-37周)'),
      factor('O1', '橙色', '早产(出生胎龄32-34周)'),
      factor('R1', '红色', '早产(出生胎龄<32周，尤其<28周早产儿)'),
      factor('Y2', '黄色', '低出生体重'),
    ];
    final riskService = FakeHighRiskFactorService()..dict = dict;
    final exclusionService = FakeHighRiskFactorExclusionService()..rules = [rule('EX-1', 'Y1', 'O1', 'R1')];
    final childService = FakeChildService();

    final vm = _buildViewModel(
      operationCodes: {ChildCreateViewModel.opCreate},
      childService: childService,
      highRiskFactorService: riskService,
      highRiskFactorExclusionService: exclusionService,
    );
    await vm.startCreate();
    await vm.loadHighRiskData();

    // 规则展开：组内三项互为互斥，组外项无互斥
    expect(vm.exclusiveHighRiskIdsOf('Y1'), {'O1', 'R1'});
    expect(vm.exclusiveHighRiskIdsOf('O1'), {'Y1', 'R1'});
    expect(vm.exclusiveHighRiskIdsOf('R1'), {'Y1', 'O1'});
    expect(vm.exclusiveHighRiskIdsOf('Y2'), isEmpty);

    // 默认勾选绿色「无高危因素」→ 勾黄色早产项时清除它
    expect(vm.checkedHighRiskIds, {'G1'});
    vm.toggleHighRiskFactor(dict[1], true); // 黄 34-37 周
    expect(vm.checkedHighRiskIds, {'Y1'});
    vm.setHighRiskRemark('Y1', '需随访');

    // 勾橙色 → 黄色被自动清除，其备注一并清除
    vm.toggleHighRiskFactor(dict[2], true);
    expect(vm.checkedHighRiskIds, {'O1'});
    expect(vm.highRiskRemarkOf('Y1'), isEmpty, reason: '互斥清除时备注同步清理');

    // 勾红色 → 橙色被自动清除
    vm.toggleHighRiskFactor(dict[3], true);
    expect(vm.checkedHighRiskIds, {'R1'});

    // 组外项可并存；切回组内另一项只清除组内冲突项
    vm.toggleHighRiskFactor(dict[4], true); // 低出生体重（组外）
    vm.toggleHighRiskFactor(dict[1], true); // 黄 34-37 周 → 红色被清除
    expect(vm.checkedHighRiskIds, {'Y1', 'Y2'});
    expect(vm.savedHighRiskCount, 2);

    // 保存透传最终集合（冲突项不出现）
    await vm.save(child: _child(''));
    final savedIds = childService.lastHighRiskFactors!.map((f) => f.factorId).toList();
    expect(savedIds, containsAll(['Y1', 'Y2']));
    expect(savedIds, isNot(contains('R1')));
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

  test('高危因素勾选切换必须通知监听者（面板即时刷新勾选状态）', () async {
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
      factor('R1', '红色', '妊娠期高血压'),
    ];
    final vm = _buildViewModel(
      operationCodes: {ChildCreateViewModel.opCreate},
      highRiskFactorService: FakeHighRiskFactorService()..dict = dict,
    );
    await vm.startCreate();
    await vm.loadHighRiskData();
    var notified = 0;
    vm.addListener(() => notified++);

    // 手动勾选/取消各通知一次（通知缺失时面板勾选状态不刷新）
    vm.toggleHighRiskFactor(dict[1], true);
    expect(vm.checkedHighRiskIds, {'R1'});
    expect(notified, 1);
    vm.toggleHighRiskFactor(dict[1], false);
    expect(vm.checkedHighRiskIds, isEmpty);
    expect(notified, 2);

    // 备注变更同样通知
    vm.setHighRiskRemark('R1', '备注');
    expect(notified, 3);
  });

  test('高危因素自动筛查：触发字段区间命中、规则表互斥三选一、条件消失自动清除', () async {
    // 字典覆盖自动筛查全部映射目标（名称须与字典原文一致，含橙色窒息项的
    // 「室息」用字）
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
      factor('P1', '黄色', HighRiskAutoScreening.preterm3437),
      factor('P2', '橙色', HighRiskAutoScreening.preterm3234),
      factor('P3', '红色', HighRiskAutoScreening.pretermLt32),
      factor('W1', '黄色', HighRiskAutoScreening.weightGt4000),
      factor('W2', '橙色', HighRiskAutoScreening.weight20002500),
      factor('W3', '红色', HighRiskAutoScreening.weightLt2000),
      factor('A1', '橙色', HighRiskAutoScreening.asphyxia47),
      factor('A2', '红色', HighRiskAutoScreening.asphyxiaLe3),
      factor('H1', '橙色', HighRiskAutoScreening.hemorrhage12),
      factor('H2', '红色', HighRiskAutoScreening.hemorrhage3),
      factor('S1', '橙色', HighRiskAutoScreening.sgaAsymmetric),
      factor('S2', '红色', HighRiskAutoScreening.sgaSymmetric),
      factor('X1', '黄色', '妊娠期糖尿病'),
      factor('X2', '黄色', '唇裂合并腭裂，尚不需要特殊护理和治疗'),
      factor('M1', '黄色', '其他手动高危因素（不在筛查映射内）'),
    ];
    final riskService = FakeHighRiskFactorService()..dict = dict;
    // 互斥名单唯一来源为互斥规则表：配置早产三选一（窒息/体重等其余组
    // 未配置，不影响筛查按区间自动替换）
    final exclusionService = FakeHighRiskFactorExclusionService()
      ..rules = [
        BaseHighRiskFactorExclusion(
          id: 'EX-1',
          firstRiskFactorId: 'P1',
          secondRiskFactorId: 'P2',
          thirdRiskFactorId: 'P3',
          creatorId: '1',
          creatorName: '系统管理员',
          hospId: '1',
          hospName: '示例人民医院',
        ),
      ];
    final vm = _buildViewModel(
      operationCodes: {ChildCreateViewModel.opCreate},
      highRiskFactorService: riskService,
      highRiskFactorExclusionService: exclusionService,
    );
    await vm.startCreate();
    await vm.loadHighRiskData();

    // 互斥映射来自规则表：早产三选一；未配置规则的组为空集
    expect(vm.exclusiveHighRiskIdsOf('P1'), {'P2', 'P3'});
    expect(vm.exclusiveHighRiskIdsOf('A1'), isEmpty);
    expect(vm.exclusiveHighRiskIdsOf('X1'), isEmpty);

    // 孕周区间：33 → 橙 32-34（默认勾选的绿色无高危因素被自动清除）
    vm.applyHighRiskAutoScreening(_extInfo(gestationalWeek: '33'));
    expect(vm.checkedHighRiskIds, {'P2'});
    // 改为 36 → 黄 34-37 自动替换（同组互斥清除旧命中）
    vm.applyHighRiskAutoScreening(_extInfo(gestationalWeek: '36'));
    expect(vm.checkedHighRiskIds, {'P1'});
    // 改为 38 → 条件消失，旧命中自动清除；边界：34 命中黄、32 命中橙、31 命中红
    vm.applyHighRiskAutoScreening(_extInfo(gestationalWeek: '38'));
    expect(vm.checkedHighRiskIds, isEmpty);
    vm.applyHighRiskAutoScreening(_extInfo(gestationalWeek: '34'));
    expect(vm.checkedHighRiskIds, {'P1'});
    vm.applyHighRiskAutoScreening(_extInfo(gestationalWeek: '32'));
    expect(vm.checkedHighRiskIds, {'P2'});
    vm.applyHighRiskAutoScreening(_extInfo(gestationalWeek: '31'));
    expect(vm.checkedHighRiskIds, {'P3'});

    // 出生体重边界：4001 黄 / 4000 不命中 / 2500 橙 / 2501 不命中 / 1999 红 / 2000 橙
    vm.applyHighRiskAutoScreening(_extInfo(birthWeight: '4001'));
    expect(vm.checkedHighRiskIds, {'W1'});
    vm.applyHighRiskAutoScreening(_extInfo(birthWeight: '4000'));
    expect(vm.checkedHighRiskIds, isEmpty);
    vm.applyHighRiskAutoScreening(_extInfo(birthWeight: '2500'));
    expect(vm.checkedHighRiskIds, {'W2'});
    vm.applyHighRiskAutoScreening(_extInfo(birthWeight: '2501'));
    expect(vm.checkedHighRiskIds, isEmpty);
    vm.applyHighRiskAutoScreening(_extInfo(birthWeight: '1999'));
    expect(vm.checkedHighRiskIds, {'W3'});
    vm.applyHighRiskAutoScreening(_extInfo(birthWeight: '2000'));
    expect(vm.checkedHighRiskIds, {'W2'});

    // Apgar5：5 橙（字典原文「室息」）/ 2 红 / 8 不命中
    vm.applyHighRiskAutoScreening(_extInfo(apgar5: '5'));
    expect(vm.checkedHighRiskIds, {'A1'});
    vm.applyHighRiskAutoScreening(_extInfo(apgar5: '2'));
    expect(vm.checkedHighRiskIds, {'A2'});
    vm.applyHighRiskAutoScreening(_extInfo(apgar5: '8'));
    expect(vm.checkedHighRiskIds, isEmpty);

    // 颅内出血级别（字典项目值）：Ⅰ级/Ⅱ级 橙、Ⅲ级及以上 红、不详不命中
    vm.applyHighRiskAutoScreening(_extInfo(intracranialHemorrhageLevel: 'Ⅰ级'));
    expect(vm.checkedHighRiskIds, {'H1'});
    vm.applyHighRiskAutoScreening(_extInfo(intracranialHemorrhageLevel: 'Ⅲ级及以上'));
    expect(vm.checkedHighRiskIds, {'H2'});
    vm.applyHighRiskAutoScreening(_extInfo(intracranialHemorrhageLevel: '不详'));
    expect(vm.checkedHighRiskIds, isEmpty);

    // SGA 分型：非匀称型 橙 / 匀称型 红 / 未选不命中
    vm.applyHighRiskAutoScreening(_extInfo(sgaType: '非匀称型'));
    expect(vm.checkedHighRiskIds, {'S1'});
    vm.applyHighRiskAutoScreening(_extInfo(sgaType: '匀称型'));
    expect(vm.checkedHighRiskIds, {'S2'});
    vm.applyHighRiskAutoScreening(_extInfo());
    expect(vm.checkedHighRiskIds, isEmpty);

    // 出生缺陷两字段并集；清空后自动清除
    vm.applyHighRiskAutoScreening(_extInfo(birthDefect06d: '左唇裂合并腭裂'));
    expect(vm.checkedHighRiskIds, {'X2'});
    vm.applyHighRiskAutoScreening(_extInfo());
    expect(vm.checkedHighRiskIds, isEmpty);

    // 手动勾选不受筛查影响、永久保留（需求 2026-11-21：允许自由勾选，
    // 不必非在扩展信息输入；筛查只清除自己自动勾选的项）
    vm.toggleHighRiskFactor(dict.firstWhere((f) => f.id == 'X1'), true); // 妊娠期糖尿病（筛查映射目标，手动勾）
    vm.toggleHighRiskFactor(dict.firstWhere((f) => f.id == 'M1'), true); // 筛查映射外的手动项
    vm.applyHighRiskAutoScreening(_extInfo(gestationalWeek: '33'));
    expect(vm.checkedHighRiskIds, {'P2', 'X1', 'M1'}, reason: '自动命中 P2 勾选；手动项 X1/M1 均保留');
    // 手动勾选同组互斥项 → 规则表互斥自动清除 P2
    vm.toggleHighRiskFactor(dict.firstWhere((f) => f.id == 'P3'), true);
    expect(vm.checkedHighRiskIds, {'P3', 'X1', 'M1'});
    // 条件消失 → 仅清除筛查自动勾选的 P2（已被互斥清除）；P3 为手动勾选，
    // 不受筛查清除
    vm.applyHighRiskAutoScreening(_extInfo(gestationalWeek: '38'));
    expect(vm.checkedHighRiskIds, {'P3', 'X1', 'M1'});
  });

  test('手动勾选可自由保存：不受筛查清除、保存透传、保存后仍显示', () async {
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
      factor('X1', '黄色', '妊娠期糖尿病'),
      factor('M1', '黄色', '其他手动高危因素（不在筛查映射内）'),
    ];
    final riskService = FakeHighRiskFactorService()..dict = dict;
    final childService = FakeChildService();
    final vm = _buildViewModel(
      operationCodes: {ChildCreateViewModel.opCreate},
      childService: childService,
      highRiskFactorService: riskService,
    );
    await vm.startCreate();
    await vm.loadHighRiskData();

    // 手动勾选两项（扩展信息未输入任何触发条件）
    vm.toggleHighRiskFactor(dict.firstWhere((f) => f.id == 'X1'), true);
    vm.toggleHighRiskFactor(dict.firstWhere((f) => f.id == 'M1'), true);
    vm.applyHighRiskAutoScreening(_extInfo());
    expect(vm.checkedHighRiskIds, {'X1', 'M1'}, reason: '筛查未命中不动手动勾选');

    // 保存 → 手动勾选随整单透传入库（Fake 库回显设为两项，模拟已存档）
    childService.savedHighRiskFactors = [
      const ChildHighRiskFactor(
        id: 'row-1',
        childId: '1',
        highRiskFactorId: 'X1',
        riskFactorCode: 'CODE-X1',
        riskFactorName: '妊娠期糖尿病',
        riskColor: '黄色',
        creatorId: '1',
        creatorName: '系统管理员',
        hospId: '1',
        hospName: '示例人民医院',
      ),
      const ChildHighRiskFactor(
        id: 'row-2',
        childId: '1',
        highRiskFactorId: 'M1',
        riskFactorCode: 'CODE-M1',
        riskFactorName: '其他手动高危因素（不在筛查映射内）',
        riskColor: '黄色',
        creatorId: '1',
        creatorName: '系统管理员',
        hospId: '1',
        hospName: '示例人民医院',
      ),
    ];
    await vm.save(child: _child(''));
    final savedIds = childService.lastHighRiskFactors!.map((f) => f.factorId).toList();
    expect(savedIds, containsAll(['X1', 'M1']));

    // 保存成功后按已存扩展信息重算筛查（未命中）→ 库记录回显手动勾选
    expect(vm.checkedHighRiskIds, containsAll({'X1', 'M1'}));

    // 扩展信息条件成立 → 对应项自动勾选（已在勾选集内的不重复处理）
    vm.applyHighRiskAutoScreening(_extInfo(hasDiabetes: '1'));
    expect(vm.checkedHighRiskIds, contains('X1'));
  });

  test('高危因素自动筛查：孕产史/受孕方式/孕期情况/年龄产次/吸毒史命中', () async {
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
      factor('B1', '黄色', '有不良妊娠结局及分娩史'),
      factor('B2', '黄色', '因不孕不育行辅助医学技术受孕等'),
      factor('B3', '黄色', '妊娠期糖尿病'),
      factor('B4', '黄色', '妊娠期高血压疾病'),
      factor('B5', '黄色', 'TORCH感染'),
      factor('B6', '黄色', '甲状腺疾病'),
      factor('B7', '黄色', '感染人类免疫缺陷病毒、梅毒螺旋体及乙肝病毒'),
      factor('B8', '黄色', '高龄(初产>35岁，经产>40岁)或年龄<18岁'),
      factor('B9', '黄色', '未婚先孕或受虐、吸毒等'),
    ];
    final vm = _buildViewModel(
      operationCodes: {ChildCreateViewModel.opCreate},
      highRiskFactorService: FakeHighRiskFactorService()..dict = dict,
    );
    await vm.startCreate();
    await vm.loadHighRiskData();

    // 孕产史任一为有
    vm.applyHighRiskAutoScreening(_extInfo(hasStillbirthHistory: '1'));
    expect(vm.checkedHighRiskIds, {'B1'});
    vm.applyHighRiskAutoScreening(_extInfo(hasStillbirthHistory: '0'));

    // 受孕方式：体外受精胚胎移植命中、自然受孕清除
    vm.applyHighRiskAutoScreening(_extInfo(conceptionMethod: '体外受精胚胎移植'));
    expect(vm.checkedHighRiskIds, {'B2'});
    vm.applyHighRiskAutoScreening(_extInfo(conceptionMethod: '自然受孕'));
    expect(vm.checkedHighRiskIds, isEmpty);

    // 孕期情况：糖尿病/高血压/巨细胞病毒/甲亢甲减任一/HIV 梅毒任一
    vm.applyHighRiskAutoScreening(_extInfo(hasDiabetes: '1'));
    expect(vm.checkedHighRiskIds, {'B3'});
    vm.applyHighRiskAutoScreening(_extInfo(hasGestationalHypertension: '1'));
    expect(vm.checkedHighRiskIds, {'B4'});
    vm.applyHighRiskAutoScreening(_extInfo(hasCmvInfection: '1'));
    expect(vm.checkedHighRiskIds, {'B5'});
    vm.applyHighRiskAutoScreening(_extInfo(hasHypothyroidismInPregnancy: '1'));
    expect(vm.checkedHighRiskIds, {'B6'});
    vm.applyHighRiskAutoScreening(_extInfo(hasHivInfection: '1'));
    expect(vm.checkedHighRiskIds, {'B7'});
    vm.applyHighRiskAutoScreening(_extInfo(hasSyphilisInfection: '1'));
    expect(vm.checkedHighRiskIds, {'B7'});
    vm.applyHighRiskAutoScreening(_extInfo(hasHivInfection: '0', hasSyphilisInfection: '0'));
    expect(vm.checkedHighRiskIds, isEmpty);

    // 产次+年龄：初产>35 / 经产>40 / 年龄<18（不依赖产次）/ 其余不命中
    vm.applyHighRiskAutoScreening(_extInfo(parity: '1', maternalAgeAtDelivery: '36'));
    expect(vm.checkedHighRiskIds, {'B8'});
    vm.applyHighRiskAutoScreening(_extInfo(parity: '2', maternalAgeAtDelivery: '41'));
    expect(vm.checkedHighRiskIds, {'B8'});
    vm.applyHighRiskAutoScreening(_extInfo(parity: '2', maternalAgeAtDelivery: '36'));
    expect(vm.checkedHighRiskIds, isEmpty);
    vm.applyHighRiskAutoScreening(_extInfo(maternalAgeAtDelivery: '17'));
    expect(vm.checkedHighRiskIds, {'B8'});
    vm.applyHighRiskAutoScreening(_extInfo(maternalAgeAtDelivery: '30'));
    expect(vm.checkedHighRiskIds, isEmpty);

    // 父母亲吸毒史
    vm.applyHighRiskAutoScreening(_extInfo(hasParentalDrugAbuseHistory: '1'));
    expect(vm.checkedHighRiskIds, {'B9'});
    vm.applyHighRiskAutoScreening(_extInfo(hasParentalDrugAbuseHistory: '0'));
    expect(vm.checkedHighRiskIds, isEmpty);
  });

  test('高危因素自动筛查：载入档案按已存扩展信息初始化命中集，编辑触发字段增量清选', () async {
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
      factor('P1', '黄色', HighRiskAutoScreening.preterm3437),
      factor('P2', '橙色', HighRiskAutoScreening.preterm3234),
    ];
    final riskService = FakeHighRiskFactorService()..dict = dict;
    final childService = FakeChildService()
      ..archives['1'] = (_child('1'), _extInfo(gestationalWeek: '35'), const [])
      ..savedHighRiskFactors = [
        const ChildHighRiskFactor(
          id: 'row-1',
          childId: '1',
          highRiskFactorId: 'P1',
          riskFactorCode: 'CODE-P1',
          riskFactorName: HighRiskAutoScreening.preterm3437,
          riskColor: '黄色',
          remark: '早产随访',
          creatorId: '1',
          creatorName: '系统管理员',
          hospId: '1',
          hospName: '示例人民医院',
        ),
      ];

    final vm = _buildViewModel(
      operationCodes: {ChildCreateViewModel.opUpdate},
      childService: childService,
      highRiskFactorService: riskService,
    );
    await vm.loadPermissions();
    await vm.selectChild('1');

    // 库记录回显 + 按扩展信息初始化命中集（孕周 35 → 黄 34-37，与库记录一致）
    expect(vm.checkedHighRiskIds, {'P1'});
    expect(vm.highRiskRemarkOf('P1'), '早产随访');

    // 编辑：孕周改为 38 → 自动命中的黄项被清除（含备注）
    vm.startEdit();
    vm.applyHighRiskAutoScreening(_extInfo(gestationalWeek: '38'));
    expect(vm.checkedHighRiskIds, isEmpty);
    expect(vm.highRiskRemarkOf('P1'), isEmpty);

    // 改回 33 → 命中橙项（同组互斥，黄项不复活）
    vm.applyHighRiskAutoScreening(_extInfo(gestationalWeek: '33'));
    expect(vm.checkedHighRiskIds, {'P2'});
  });
}
