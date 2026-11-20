// 高危因素互斥规则管理 ViewModel 单元测试：Fake 服务构造注入，覆盖
// 规则与高危因素装载、下拉候选按颜色/编码排序、字典项缺失时的名称
// 占位与重选标记、操作权限判定、增删改后整表重拉与选中保持。
import 'package:client/services/high_risk_factor_exclusion_service.dart';
import 'package:client/services/high_risk_factor_service.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/view_models/system/high_risk_factor_exclusion_management_view_model.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存版菜单服务：仅覆写操作权限查询（本 VM 只用到该接口）。
class _FakeMenuService extends MenuService {
  _FakeMenuService({Set<String>? operationCodes}) : _operationCodes = operationCodes ?? _allOperationCodes;

  static final Set<String> _allOperationCodes = {
    HighRiskFactorExclusionManagementViewModel.opCreate,
    HighRiskFactorExclusionManagementViewModel.opUpdate,
    HighRiskFactorExclusionManagementViewModel.opDelete,
  };

  final Set<String> _operationCodes;

  @override
  Future<Set<String>> queryOperationCodes() async => {..._operationCodes};
}

/// 内存版高危因素服务：仅提供查询（VM 用其解析名称与下拉候选）。
class _FakeHighRiskFactorService extends HighRiskFactorService {
  final List<BaseHighRiskFactor> store = [];

  void seed(String id, {required String name, required String code, String? color}) {
    store.add(
      BaseHighRiskFactor(
        id: id,
        riskFactorCode: code,
        riskFactorName: name,
        riskColor: color,
        creatorId: 'u1',
        creatorName: '系统管理员',
        hospId: 'h1',
        hospName: '示例人民医院',
      ),
    );
  }

  @override
  Future<List<BaseHighRiskFactor>> queryAll() async => List.of(store);
}

/// 内存版互斥规则服务：模拟后端查询与增删改（医院/创建人固定）。
class _FakeExclusionService extends HighRiskFactorExclusionService {
  final Map<String, BaseHighRiskFactorExclusion> store = {};
  int nextId = 1;

  /// 最近一次新增/修改入参（断言字段透传）。
  ({String first, String second, String? third})? lastCreateArgs;
  Map<String, Object?>? lastUpdateChanges;

  void seed(String id, {required String first, required String second, String? third}) {
    store[id] = BaseHighRiskFactorExclusion(
      id: id,
      firstRiskFactorId: first,
      secondRiskFactorId: second,
      thirdRiskFactorId: third,
      creatorId: 'u1',
      creatorName: '系统管理员',
      hospId: 'h1',
      hospName: '示例人民医院',
    );
    final n = int.tryParse(id);
    if (n != null && n >= nextId) nextId = n + 1;
  }

  BaseHighRiskFactorExclusion _build(String id, String first, String second, String? third) {
    return BaseHighRiskFactorExclusion(
      id: id,
      firstRiskFactorId: first,
      secondRiskFactorId: second,
      thirdRiskFactorId: third,
      creatorId: 'u1',
      creatorName: '系统管理员',
      hospId: 'h1',
      hospName: '示例人民医院',
    );
  }

  @override
  Future<List<BaseHighRiskFactorExclusion>> queryAll() async {
    return store.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  @override
  Future<BaseHighRiskFactorExclusion> create({
    required String firstRiskFactorId,
    required String secondRiskFactorId,
    String? thirdRiskFactorId,
  }) async {
    lastCreateArgs = (first: firstRiskFactorId, second: secondRiskFactorId, third: thirdRiskFactorId);
    final id = '${nextId++}';
    final rule = _build(id, firstRiskFactorId, secondRiskFactorId, thirdRiskFactorId);
    store[id] = rule;
    return rule;
  }

  @override
  Future<BaseHighRiskFactorExclusion> update(String id, Map<String, Object?> changes) async {
    lastUpdateChanges = changes;
    final current = store[id]!;
    final updated = _build(
      id,
      changes.containsKey('firstRiskFactorId') ? changes['firstRiskFactorId'] as String : current.firstRiskFactorId,
      changes.containsKey('secondRiskFactorId') ? changes['secondRiskFactorId'] as String : current.secondRiskFactorId,
      changes.containsKey('thirdRiskFactorId') ? changes['thirdRiskFactorId'] as String? : current.thirdRiskFactorId,
    );
    store[id] = updated;
    return updated;
  }

  @override
  Future<int> delete(String id) async {
    return store.remove(id) == null ? 0 : 1;
  }
}

void main() {
  late _FakeExclusionService exclusionService;
  late _FakeHighRiskFactorService factorService;
  late _FakeMenuService menuService;
  late HighRiskFactorExclusionManagementViewModel viewModel;

  setUp(() {
    exclusionService = _FakeExclusionService();
    factorService = _FakeHighRiskFactorService();
    menuService = _FakeMenuService();
    viewModel = HighRiskFactorExclusionManagementViewModel(
      exclusionService: exclusionService,
      highRiskFactorService: factorService,
      menuService: menuService,
    );
  });

  test('装载规则与高危因素：名称解析、下拉候选按颜色/编码排序', () async {
    factorService.seed('f1', name: '早产', code: 'R003', color: '红色');
    factorService.seed('f2', name: '低出生体重', code: 'R002', color: '绿色');
    factorService.seed('f3', name: '无颜色因素', code: 'R001');
    factorService.seed('f4', name: '新生儿窒息', code: 'R004', color: '绿色');
    exclusionService.seed('1', first: 'f1', second: 'f2');

    expect(await viewModel.loadData(), isTrue);
    expect(viewModel.exclusions, hasLength(1));
    expect(viewModel.isEmpty, isFalse);
    expect(viewModel.hasNoFactors, isFalse);

    // 绿（R002/R004）→ 红（R003）→ 未设置（R001）
    expect(viewModel.sortedFactors.map((f) => f.id), ['f2', 'f4', 'f1', 'f3']);
    expect(viewModel.factorNameOf('f1'), '早产');
    expect(viewModel.factorColorOf('f1'), '红色');
    expect(viewModel.factorCodeOf('f1'), 'R003');
    expect(viewModel.hasMissingFactors(viewModel.exclusions.single), isFalse);
  });

  test('高危因素已被删除：名称占位并标记需重新选择', () async {
    factorService.seed('f1', name: '早产', code: 'R001', color: '红色');
    exclusionService.seed('1', first: 'f1', second: 'gone');

    expect(await viewModel.loadData(), isTrue);
    final rule = viewModel.exclusions.single;
    expect(viewModel.factorNameOf('gone'), '（高危因素已删除）');
    expect(viewModel.factorCodeOf('gone'), '');
    expect(viewModel.hasMissingFactors(rule), isTrue);
  });

  test('无高危因素时 hasNoFactors 为 true（表单给出先维护字典的引导）', () async {
    exclusionService.seed('1', first: 'f1', second: 'f2');
    expect(await viewModel.loadData(), isTrue);
    expect(viewModel.hasNoFactors, isTrue);
  });

  test('操作权限：编码集决定 canCreate/canUpdate/canDelete', () async {
    expect(await viewModel.loadData(), isTrue);
    expect(viewModel.canCreate, isTrue);
    expect(viewModel.canUpdate, isTrue);
    expect(viewModel.canDelete, isTrue);

    final denied = HighRiskFactorExclusionManagementViewModel(
      exclusionService: exclusionService,
      highRiskFactorService: factorService,
      menuService: _FakeMenuService(operationCodes: {}),
    );
    expect(await denied.loadData(), isTrue);
    expect(denied.canCreate, isFalse);
    expect(denied.canUpdate, isFalse);
    expect(denied.canDelete, isFalse);
  });

  test('新增/修改/删除：参数透传、整表重拉、选中与表单模式联动', () async {
    factorService.seed('f1', name: '早产', code: 'R001', color: '黄色');
    factorService.seed('f2', name: '低出生体重', code: 'R002', color: '橙色');
    factorService.seed('f3', name: '新生儿窒息', code: 'R003', color: '红色');
    expect(await viewModel.loadData(), isTrue);
    expect(viewModel.isEmpty, isTrue);
    expect(viewModel.formMode, HighRiskFactorExclusionFormMode.empty);

    // 新增：进入新增态 → 提交 → 退出新增态并选中新规则
    viewModel.startCreate();
    expect(viewModel.formMode, HighRiskFactorExclusionFormMode.create);
    expect(
      await viewModel.createExclusion(firstRiskFactorId: 'f1', secondRiskFactorId: 'f2'),
      isTrue,
    );
    expect(viewModel.formMode, HighRiskFactorExclusionFormMode.edit);
    expect(viewModel.selected?.riskFactorIds, ['f1', 'f2']);
    expect(exclusionService.lastCreateArgs?.first, 'f1');
    expect(exclusionService.lastCreateArgs?.second, 'f2');
    expect(exclusionService.lastCreateArgs?.third, isNull);

    // 修改：补第三项 → 选中项引用刷新
    final id = viewModel.selected!.id;
    expect(
      await viewModel.updateExclusion(id, {
        'firstRiskFactorId': 'f1',
        'secondRiskFactorId': 'f2',
        'thirdRiskFactorId': 'f3',
      }),
      isTrue,
    );
    expect(viewModel.selected?.id, id);
    expect(viewModel.selected?.thirdRiskFactorId, 'f3');
    expect(exclusionService.lastUpdateChanges?['thirdRiskFactorId'], 'f3');

    // 删除选中的规则 → 回退空态
    expect(await viewModel.deleteExclusion(viewModel.selected!), isTrue);
    expect(viewModel.selected, isNull);
    expect(viewModel.formMode, HighRiskFactorExclusionFormMode.empty);
    expect(viewModel.isEmpty, isTrue);
  });

  test('加载失败：错误信息去前缀并保留可重试状态', () async {
    final failing = HighRiskFactorExclusionManagementViewModel(
      exclusionService: _FailingExclusionService(),
      highRiskFactorService: factorService,
      menuService: menuService,
    );
    expect(await failing.loadData(), isFalse);
    expect(failing.errorMsg, '模拟后端故障');
    expect(failing.loading, isFalse);
    failing.clearError();
    expect(failing.errorMsg, isNull);
  });
}

/// 查询即抛错的互斥规则服务（错误信息去前缀用例）。
class _FailingExclusionService extends HighRiskFactorExclusionService {
  @override
  Future<List<BaseHighRiskFactorExclusion>> queryAll() async {
    throw Exception('模拟后端故障');
  }
}
