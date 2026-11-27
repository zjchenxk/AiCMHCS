// 初筛记录表 ViewModel 单元测试：Fake 服务构造注入，聚焦「当前儿童同步」
// 的同一儿童档案修改场景——儿童建档页改出生日期保存后经
// MainViewModel.setCurrentChild 重新下发，儿童 ID 不变而字段变化，快照
// 须替换（工具栏年龄/实足纠正年龄/自动 TAB 推算均由快照派生）、扩展
// 档案（孕周/孕天，纠正年龄依据）单独重载，初筛记录与医生候选不重载；
// 以及同字段幂等空操作、切换儿童全量重载的原有行为回归。
import 'package:client/models/current_child.dart';
import 'package:client/services/child_service.dart';
import 'package:client/services/initial_screening_service.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/services/time_service.dart';
import 'package:client/view_models/asd/initial_screening_view_model.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存版菜单服务：仅覆写操作权限查询。
class _FakeMenuService extends MenuService {
  @override
  Future<Set<String>> queryOperationCodes() async => {};
}

/// 内存版初筛服务：按儿童 ID 存初筛记录，统计 query 调用次数（同 ID 档案
/// 修改不应重拉记录）。
class _FakeScreeningService extends InitialScreeningService {
  final Map<String, List<InitialScreening>> store = {};

  int queryCalls = 0;

  void put(String childId, InitialScreening record) {
    store.putIfAbsent(childId, () => []).add(record);
  }

  @override
  Future<List<InitialScreening>> query(String childId) async {
    queryCalls++;
    return [...(store[childId] ?? const <InitialScreening>[])].where((r) => r.id != null).toList();
  }

  @override
  Future<List<DoctorOption>> doctors() async => [];

  @override
  Future<List<WscmbdItem>> wscmbdItems(int month) async => [];
}

/// 内存版儿童服务：返回固定整档三元组，统计 load 调用次数（同 ID 档案
/// 修改后扩展档案须单独重载）。
class _FakeChildService extends ChildService {
  _FakeChildService(this.ext);

  /// 每次返回的扩展档案（孕周/孕天可被外部修改后更新）。
  ChildExtInfo? ext;

  int loadCalls = 0;

  @override
  Future<ChildArchive> load(String id) async {
    loadCalls++;
    return (_childInfo(id), ext, const <ChildGuardianInfo>[]);
  }
}

ChildInfo _childInfo(String id, {String birthDate = '2025-06-01'}) => ChildInfo(
  id: id,
  checkTime: '2026-01-01',
  name: '王小明',
  sex: '1',
  birthDate: birthDate,
  addressProvince: '110000',
  addressCity: '110100',
  addressCounty: '110101',
  addressDetails: '示例街道 1 号',
  creatorId: 'u1',
  creatorName: '张医生',
  hospId: 'h1',
  hospName: '示例人民医院',
);

ChildExtInfo _extInfo(String childId, {String? week, String? day}) => ChildExtInfo(
  childId: childId,
  creatorId: 'u1',
  creatorName: '张医生',
  hospId: 'h1',
  hospName: '示例人民医院',
  gestationalWeek: week,
  gestationalDay: day,
);

InitialScreening _record(String childId, {int month = 3}) => InitialScreening(
  id: 'r-$childId-$month',
  childId: childId,
  checkDate: '2026-09-01',
  ageYear: 0,
  ageMonth: 3,
  ageDay: 0,
  checkMonth: month,
  warningSignResult: '未见异常',
  languageSocialCommunicationResult: '未见异常',
  checkResult: '未见异常',
  hasReferral: '0',
  referralHospName: '无',
  doctorId: 'd1',
  doctorName: '李医生',
  creatorId: 'u1',
  creatorName: '张医生',
  hospId: 'h1',
  hospName: '示例人民医院',
);

void main() {
  CurrentChild childOf(DateTime birthDate) => CurrentChild(
    id: 'c1',
    visitCardNo: 'V001',
    patientId: 'P001',
    name: '王小明',
    gender: '男',
    birthDate: birthDate,
    phone: '',
  );

  test('syncChild：同 ID 出生日期被修改（建档页保存后重新下发）→ 快照替换 + 扩展档案重载 + 记录不重拉', () async {
    final screening = _FakeScreeningService();
    screening.put('c1', _record('c1'));
    final childService = _FakeChildService(_extInfo('c1', week: '36', day: '3'));
    final vm = InitialScreeningViewModel(screeningService: screening, childService: childService, menuService: _FakeMenuService(), timeService: TimeService());

    var notifications = 0;
    vm.addListener(() => notifications++);

    // 首次选定：三路并行装载（记录 query + 扩展档案 load + 医生）
    await vm.syncChild(childOf(DateTime(2025, 6, 1)));
    expect(vm.child!.birthDate, DateTime(2025, 6, 1));
    expect(vm.hasRecord(3), isTrue);
    expect(screening.queryCalls, 1);
    expect(childService.loadCalls, 1);
    expect(vm.extSignature, '36|3');
    final notifyAfterFirstLoad = notifications;

    // 同 ID 但出生日期/孕周被修改（建档页保存后 setCurrentChild 重新下发）
    final modified = CurrentChild(
      id: 'c1',
      visitCardNo: 'V001',
      patientId: 'P001',
      name: '王小明',
      gender: '男',
      birthDate: DateTime(2025, 9, 15),
      phone: '',
    );
    childService.ext = _extInfo('c1', week: '38', day: '0');
    await vm.syncChild(modified);

    // 快照替换为新出生日期，且发出通知（页面据此重算派生显示）
    expect(vm.child!.birthDate, DateTime(2025, 9, 15));
    expect(notifications, greaterThan(notifyAfterFirstLoad));

    // 扩展档案单独重载（纠正年龄依据），快照签名随新孕周更新
    expect(childService.loadCalls, 2);
    expect(vm.extSignature, '38|0');

    // 初筛记录不随档案字段变化重拉，已做记录红点保留
    expect(screening.queryCalls, 1);
    expect(vm.hasRecord(3), isTrue);
  });

  test('syncChild：同 ID 同字段重复同步幂等——不重载扩展档案不发通知', () async {
    final screening = _FakeScreeningService();
    final childService = _FakeChildService(_extInfo('c1'));
    final vm = InitialScreeningViewModel(screeningService: screening, childService: childService, menuService: _FakeMenuService(), timeService: TimeService());

    var notifications = 0;
    vm.addListener(() => notifications++);

    await vm.syncChild(childOf(DateTime(2025, 6, 1)));
    expect(childService.loadCalls, 1);
    expect(screening.queryCalls, 1);
    final notifyAfterFirstLoad = notifications;

    // MainViewModel 侧边栏异步装载等会多次 notify，页面随之重复传同一
    // 快照实例：字段未变必须幂等空操作
    await vm.syncChild(
      CurrentChild(
        id: 'c1',
        visitCardNo: 'V001',
        patientId: 'P001',
        name: '王小明',
        gender: '男',
        birthDate: DateTime(2025, 6, 1),
        phone: '',
      ),
    );
    expect(childService.loadCalls, 1);
    expect(notifications, notifyAfterFirstLoad);
    expect(screening.queryCalls, 1, reason: '同字段重复同步不重拉记录');
  });

  test('syncChild：切换儿童走全量重载（原有行为回归）', () async {
    final screening = _FakeScreeningService();
    screening.put('c1', _record('c1', month: 3));
    screening.put('c2', _record('c2', month: 6));
    final childService = _FakeChildService(null);
    final vm = InitialScreeningViewModel(screeningService: screening, childService: childService, menuService: _FakeMenuService(), timeService: TimeService());

    await vm.syncChild(childOf(DateTime(2025, 6, 1)));
    expect(vm.hasRecord(3), isTrue);
    expect(vm.hasRecord(6), isFalse);

    // 切换到 c2：记录清空重载，不会残留 c1 的记录
    final c2 = CurrentChild(
      id: 'c2',
      visitCardNo: 'V002',
      patientId: 'P002',
      name: '李小红',
      gender: '女',
      birthDate: DateTime(2025, 3, 1),
      phone: '',
    );
    await vm.syncChild(c2);
    expect(vm.child!.id, 'c2');
    expect(vm.hasRecord(3), isFalse, reason: '切换儿童须清空上一儿童的记录映射');
    expect(vm.hasRecord(6), isTrue);
    expect(screening.queryCalls, 2);
  });
}
