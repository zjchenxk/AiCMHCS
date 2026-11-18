// 高危因素管理 ViewModel 单元测试：Fake 服务构造注入，覆盖按高危颜色
// 分组（绿/黄/橙/红/紫 → 其他颜色 → 未设置）、组内「大类→小类→名称」
// 建树与排序、大类/小类为空时名称逐级上提、操作权限判定、增删改后整表
// 重拉与选中保持。
import 'package:client/services/high_risk_factor_service.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/view_models/system/high_risk_factor_management_view_model.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存版菜单服务：仅覆写操作权限查询（高危因素 VM 只用到该接口）。
class _FakeMenuService extends MenuService {
  _FakeMenuService({Set<String>? operationCodes}) : _operationCodes = operationCodes ?? _allOperationCodes;

  static final Set<String> _allOperationCodes = {
    HighRiskFactorManagementViewModel.opCreate,
    HighRiskFactorManagementViewModel.opUpdate,
    HighRiskFactorManagementViewModel.opDelete,
  };

  final Set<String> _operationCodes;

  @override
  Future<Set<String>> queryOperationCodes() async => {..._operationCodes};
}

/// 内存版高危因素服务：模拟后端查询与增删改（医院/创建人固定）。
class _FakeHighRiskFactorService extends HighRiskFactorService {
  final Map<String, BaseHighRiskFactor> store = {};
  int nextId = 1;
  int queryAllCalls = 0;

  /// 最近一次新增入参（断言字段透传）。
  ({String? category, String? subcategory, String? color, String? level, String? score})? lastCreateArgs;

  void seed(
    String id, {
    String? color,
    String? category,
    String? subcategory,
    required String name,
    required String code,
    String? level,
    String? score,
  }) {
    store[id] = BaseHighRiskFactor(
      id: id,
      riskFactorCategory: category,
      riskFactorSubcategory: subcategory,
      riskFactorCode: code,
      riskFactorName: name,
      riskColor: color,
      riskLevel: level,
      riskScore: score,
      creatorId: 'u1',
      creatorName: '系统管理员',
      hospId: 'h1',
      hospName: '示例人民医院',
    );
    final n = int.tryParse(id);
    if (n != null && n >= nextId) nextId = n + 1;
  }

  BaseHighRiskFactor _build(
    String id, {
    String? category,
    String? subcategory,
    required String name,
    required String code,
    String? color,
    String? level,
    String? score,
  }) {
    return BaseHighRiskFactor(
      id: id,
      riskFactorCategory: category,
      riskFactorSubcategory: subcategory,
      riskFactorCode: code,
      riskFactorName: name,
      riskColor: color,
      riskLevel: level,
      riskScore: score,
      creatorId: 'u1',
      creatorName: '系统管理员',
      hospId: 'h1',
      hospName: '示例人民医院',
    );
  }

  @override
  Future<List<BaseHighRiskFactor>> queryAll() async {
    queryAllCalls++;
    return store.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  @override
  Future<BaseHighRiskFactor> create({
    required String riskFactorCode,
    required String riskFactorName,
    String? riskFactorCategory,
    String? riskFactorSubcategory,
    String? riskColor,
    String? riskLevel,
    String? riskScore,
  }) async {
    lastCreateArgs = (
      category: riskFactorCategory,
      subcategory: riskFactorSubcategory,
      color: riskColor,
      level: riskLevel,
      score: riskScore,
    );
    final id = '${nextId++}';
    final factor = _build(
      id,
      category: riskFactorCategory,
      subcategory: riskFactorSubcategory,
      name: riskFactorName,
      code: riskFactorCode,
      color: riskColor,
      level: riskLevel,
      score: riskScore,
    );
    store[id] = factor;
    return factor;
  }

  @override
  Future<BaseHighRiskFactor> update(String id, Map<String, Object?> changes) async {
    final current = store[id]!;
    final updated = BaseHighRiskFactor(
      id: id,
      riskFactorCategory: changes.containsKey('riskFactorCategory') ? changes['riskFactorCategory'] as String? : current.riskFactorCategory,
      riskFactorSubcategory: changes.containsKey('riskFactorSubcategory') ? changes['riskFactorSubcategory'] as String? : current.riskFactorSubcategory,
      riskFactorCode: changes['riskFactorCode'] as String? ?? current.riskFactorCode,
      riskFactorName: changes['riskFactorName'] as String? ?? current.riskFactorName,
      riskColor: changes.containsKey('riskColor') ? changes['riskColor'] as String? : current.riskColor,
      riskLevel: changes.containsKey('riskLevel') ? changes['riskLevel'] as String? : current.riskLevel,
      riskScore: changes.containsKey('riskScore') ? changes['riskScore']?.toString() : current.riskScore,
      creatorId: current.creatorId,
      creatorName: current.creatorName,
      hospId: current.hospId,
      hospName: current.hospName,
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
  late _FakeHighRiskFactorService factorService;
  late _FakeMenuService menuService;
  late HighRiskFactorManagementViewModel viewModel;

  setUp(() {
    factorService = _FakeHighRiskFactorService();
    menuService = _FakeMenuService();
    viewModel = HighRiskFactorManagementViewModel(
      highRiskFactorService: factorService,
      menuService: menuService,
    );
  });

  test('按颜色分组：绿/黄/橙/红/紫固定序 → 其他颜色 → 未设置', () async {
    factorService.seed('1', color: '红色', name: '因素1', code: 'R001');
    factorService.seed('2', color: '绿色', name: '因素2', code: 'R002');
    factorService.seed('3', color: '蓝色', name: '因素3', code: 'R003');
    factorService.seed('4', name: '因素4', code: 'R004');
    factorService.seed('5', color: '紫色', name: '因素5', code: 'R005');
    factorService.seed('6', color: '黄色', name: '因素6', code: 'R006');

    expect(await viewModel.loadData(), isTrue);
    expect(
      viewModel.groups.map((g) => g.colorName),
      ['绿色', '黄色', '红色', '紫色', '蓝色', null],
    );
    expect(viewModel.groups.map((g) => g.factorCount), [1, 1, 1, 1, 1, 1]);
  });

  test('组内建树：大类→小类→名称；大类/小类为空逐级上提', () async {
    // 完整三级
    factorService.seed('1', color: '绿色', category: 'C1', subcategory: 'S1', name: 'B因素', code: 'R002');
    factorService.seed('2', color: '绿色', category: 'C1', subcategory: 'S1', name: 'A因素', code: 'R001');
    // 有小类无大类 → 小类节点置顶层
    factorService.seed('3', color: '绿色', subcategory: 'S2', name: 'B因素', code: 'R004');
    // 有大类无小类 → 因素直挂大类下
    factorService.seed('4', color: '绿色', category: 'C1', name: 'A因素', code: 'R003');
    // 大类/小类均空 → 因素置顶层
    factorService.seed('5', color: '绿色', name: 'A因素', code: 'R005');

    expect(await viewModel.loadData(), isTrue);
    final green = viewModel.groups.single;
    expect(green.colorName, '绿色');
    expect(green.factorCount, 5);

    // 根层按编码升序：C1（后代最小 R001）→ S2（R004）→ 顶层散落因素（R005）
    expect(green.roots.map((n) => n.name), ['C1', 'S2', 'A因素']);
    expect(green.roots[2].factor?.riskFactorCode, 'R005');

    // C1 下：S1（后代最小 R001）→ A因素（无小类，R003）→ 小类内按编码升序
    final category = green.roots[0];
    expect(category.children.map((n) => n.name), ['S1', 'A因素']);
    expect(category.children[1].factor?.riskFactorCode, 'R003');
    final subcategory = category.children[0];
    expect(subcategory.children.map((n) => n.factor?.riskFactorCode), ['R001', 'R002']);
    expect(subcategory.children.map((n) => n.name), ['A因素', 'B因素']);

    // S2 顶层小类下挂因素
    expect(green.roots[1].children.single.factor?.riskFactorCode, 'R004');
  });

  test('操作权限：编码集决定 canCreate/canUpdate/canDelete', () async {
    expect(await viewModel.loadData(), isTrue);
    expect(viewModel.canCreate, isTrue);
    expect(viewModel.canUpdate, isTrue);
    expect(viewModel.canDelete, isTrue);

    final denied = HighRiskFactorManagementViewModel(
      highRiskFactorService: factorService,
      menuService: _FakeMenuService(operationCodes: {}),
    );
    expect(await denied.loadData(), isTrue);
    expect(denied.canCreate, isFalse);
    expect(denied.canUpdate, isFalse);
    expect(denied.canDelete, isFalse);
  });

  test('新增/修改/删除：参数透传、整表重拉、选中与表单模式联动', () async {
    expect(await viewModel.loadData(), isTrue);
    expect(viewModel.isEmpty, isTrue);
    expect(viewModel.formMode, HighRiskFactorFormMode.empty);

    // 新增：进入新增态 → 提交 → 退出新增态并选中新因素
    viewModel.startCreate();
    expect(viewModel.formMode, HighRiskFactorFormMode.create);
    expect(
      await viewModel.createFactor(
        riskFactorCode: 'R001',
        riskFactorName: '早发败血症',
        riskFactorCategory: '感染',
        riskFactorSubcategory: '新生儿',
        riskColor: '红色',
        riskLevel: 'Ⅲ',
        riskScore: '10',
      ),
      isTrue,
    );
    expect(viewModel.formMode, HighRiskFactorFormMode.edit);
    expect(viewModel.selected?.riskFactorName, '早发败血症');
    expect(factorService.lastCreateArgs?.category, '感染');
    expect(factorService.lastCreateArgs?.subcategory, '新生儿');
    expect(factorService.lastCreateArgs?.color, '红色');
    expect(factorService.lastCreateArgs?.level, 'Ⅲ');
    expect(factorService.lastCreateArgs?.score, '10');

    // 修改：清空小类并改颜色 → 选中项引用刷新
    final id = viewModel.selected!.id;
    expect(
      await viewModel.updateFactor(id, {
        'riskFactorCategory': '感染',
        'riskFactorSubcategory': null,
        'riskFactorCode': 'R001',
        'riskFactorName': '早发败血症（改）',
        'riskColor': '橙色',
        'riskLevel': 'Ⅱ',
        'riskScore': '20',
      }),
      isTrue,
    );
    expect(viewModel.selected?.id, id);
    expect(viewModel.selected?.riskFactorName, '早发败血症（改）');
    expect(viewModel.selected?.riskFactorSubcategory, isNull);
    expect(viewModel.groups.single.colorName, '橙色');

    // 删除选中的因素 → 回退空态
    expect(await viewModel.deleteFactor(viewModel.selected!), isTrue);
    expect(viewModel.selected, isNull);
    expect(viewModel.formMode, HighRiskFactorFormMode.empty);
    expect(viewModel.isEmpty, isTrue);
  });

  test('加载失败：错误信息去前缀并保留可重试状态', () async {
    final failing = HighRiskFactorManagementViewModel(
      highRiskFactorService: _FailingService(),
      menuService: menuService,
    );
    expect(await failing.loadData(), isFalse);
    expect(failing.errorMsg, '模拟后端故障');
    expect(failing.loading, isFalse);
    failing.clearError();
    expect(failing.errorMsg, isNull);
  });
}

/// 查询即抛错的高危因素服务（错误信息去前缀用例）。
class _FailingService extends HighRiskFactorService {
  @override
  Future<List<BaseHighRiskFactor>> queryAll() async {
    throw Exception('模拟后端故障');
  }
}
