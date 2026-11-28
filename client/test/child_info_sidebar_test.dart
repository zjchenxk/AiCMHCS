// 右侧儿童信息侧边栏（多 TAB 工作台）测试：
// - 默认「当前儿童」TAB：基础信息/出生日期/五色分级/高危因素（REMARK 在
//   名称下方）/历次检查；未选定儿童时显示指引占位（侧边栏常驻显示）；
// - 最右缘活动条 5 个垂直 TAB；标题栏收起钮最左、标题靠右；
// - 「初筛儿童」TAB：日期区间分页列表（服务端口径）、翻页、双击记录
//   切换当前儿童 + 打开初筛记录表菜单 + 登记待定位月龄；
// - 复筛/诊断/干预 TAB：查询栏与列头占位、功能暂缓开放提示；
// - 收起后仅保留竖排 TAB 图标，展开后内容恢复。
import 'package:client/main.dart' as app;
import 'package:client/services/child_service.dart';
import 'package:client/services/initial_screening_service.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/services/time_service.dart';
import 'package:client/view_models/asd/initial_screening_view_model.dart';
import 'package:client/view_models/main/initial_screening_list_view_model.dart';
import 'package:client/view_models/main/main_view_model.dart';
import 'package:client/views/main/child_info_sidebar.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// 返回固定儿童整档与高危因素记录的伪儿童服务（load 按 id 返回同名
/// 儿童，供双击记录切换上下文用例验证）。
class FakeChildService extends ChildService {
  FakeChildService(this.child, this.ext, {this.factors = const []});

  final ChildInfo child;
  final ChildExtInfo ext;
  List<ChildHighRiskFactor> factors;

  @override
  Future<ChildArchive> load(String id) async => (
    ChildInfo(
      id: id,
      checkTime: '2026-11-17',
      name: '列表儿童',
      sex: '2',
      birthDate: '2024-03-05',
      addressProvince: '330000',
      addressCity: '330100',
      addressCounty: '330106',
      addressDetails: '测试路 1 号',
      creatorId: 'user-1',
      creatorName: '测试医生',
      hospId: 'hosp-1',
      hospName: '测试医院',
      phone: '13900000000',
    ),
    ext,
    const <ChildGuardianInfo>[],
  );

  @override
  Future<ChildPhoto?> latestPhoto(String childId) async => null;

  @override
  Future<List<ChildHighRiskFactor>> highRiskFactors(String childId) async => factors;

  @override
  Future<List<ChildCheckRecord>> checkRecords(String childId) async => const [];
}

/// 返回固定初筛记录分页的伪初筛服务（本地模拟日期区间过滤与切片）。
class FakeScreeningListService extends InitialScreeningService {
  FakeScreeningListService(this.records);

  final List<InitialScreeningListItem> records;

  @override
  Future<(List<InitialScreeningListItem>, int, int, int)> list({String? startDate, String? endDate, int page = 1, int pageSize = 10}) async {
    var filtered = records;
    if (startDate != null && startDate.isNotEmpty) {
      filtered = filtered.where((r) => r.checkDate.compareTo(startDate) >= 0).toList();
    }
    if (endDate != null && endDate.isNotEmpty) {
      filtered = filtered.where((r) => r.checkDate.compareTo(endDate) <= 0).toList();
    }
    final total = filtered.length;
    final slice = filtered.skip((page - 1) * pageSize).take(pageSize).toList();
    return (slice, total, page, pageSize);
  }
}

/// 测试用儿童基础档案（2023-09-01 出生，3 岁已过矫正窗口）。
ChildInfo buildChild() => ChildInfo(
  id: 'child-1',
  checkTime: '2026-11-17',
  name: '测试儿童',
  sex: '1',
  birthDate: '2023-09-01',
  addressProvince: '330000',
  addressCity: '330100',
  addressCounty: '330106',
  addressDetails: '测试路 1 号',
  creatorId: 'user-1',
  creatorName: '测试医生',
  hospId: 'hosp-1',
  hospName: '测试医院',
  phone: '13800000000',
);

/// 测试用儿童扩展档案。
ChildExtInfo buildExt() => const ChildExtInfo(
  childId: 'child-1',
  creatorId: 'user-1',
  creatorName: '测试医生',
  hospId: 'hosp-1',
  hospName: '测试医院',
  gestationalWeek: '33',
  gestationalDay: '4',
  gravidity: '2',
  parity: '1',
);

/// 测试用高危因素：橙色 + 紫色（叠加）。
List<ChildHighRiskFactor> buildFactors() => [
  const ChildHighRiskFactor(
    id: 'f1',
    childId: 'child-1',
    highRiskFactorId: 'dict-1',
    riskFactorCode: '0399',
    riskFactorName: '早产（32~33⁺⁶周）',
    riskColor: '橙色',
    remark: '出生孕周 33 周 + 4 天',
    creatorId: 'user-1',
    creatorName: '测试医生',
    hospId: 'hosp-1',
    hospName: '测试医院',
  ),
  const ChildHighRiskFactor(
    id: 'f2',
    childId: 'child-1',
    highRiskFactorId: 'dict-2',
    riskFactorCode: '0599',
    riskFactorName: '母亲梅毒感染',
    riskColor: '紫色',
    creatorId: 'user-1',
    creatorName: '测试医生',
    hospId: 'hosp-1',
    hospName: '测试医院',
  ),
];

/// 测试用初筛记录（12 条 → 第 1 页 10 条 / 第 2 页 2 条）。
List<InitialScreeningListItem> buildScreeningRecords() => [
  for (var i = 0; i < 12; i++)
    InitialScreeningListItem(
      id: 'r$i',
      childId: 'child-$i',
      childName: '筛查儿童$i',
      checkDate: '2026-${(12 - i ~/ 2).toString().padLeft(2, '0')}-15',
      checkMonth: 12,
      checkResult: i % 3 == 0 ? '异常' : '未见异常',
    ),
];

/// 主界面角色菜单（含初筛记录表路由，验证双击跳转选中）。
List<Menu> buildMenus() => const [
  Menu(id: 'm1', parentId: null, itemCode: 'ASD01', itemName: '孤独症筛查', itemType: '1', menuRoute: null, menuIcon: 'psychology', visible: '1'),
  Menu(id: 'm2', parentId: 'm1', itemCode: 'ASD0101', itemName: '初筛记录表', itemType: '2', menuRoute: '/asd/initialScreening', menuIcon: 'fact_check', visible: '1'),
];

void main() {
  setUp(() {
    // 侧边栏构建年龄/日期选择默认值依赖全局时间服务（未校准即本地时钟）
    if (!app.getIt.isRegistered<TimeService>()) {
      app.getIt.registerLazySingleton<TimeService>(() => TimeService());
    }
  });

  Future<MainViewModel> pumpSidebar(
    WidgetTester tester, {
    MainViewModel? mainViewModel,
    InitialScreeningListViewModel? listViewModel,
    InitialScreeningViewModel? screeningViewModel,
    bool withChild = true,
  }) async {
    final child = buildChild();
    final fakeChildService = FakeChildService(child, buildExt(), factors: buildFactors());
    final vm = mainViewModel ?? MainViewModel(childService: fakeChildService);
    if (withChild) {
      vm.setCurrentChild(child);
    }
    final listVm = listViewModel ?? InitialScreeningListViewModel(screeningService: FakeScreeningListService(buildScreeningRecords()));
    final screeningVm =
        screeningViewModel ??
        InitialScreeningViewModel(
          screeningService: FakeScreeningListService(const []),
          childService: fakeChildService,
          menuService: app.getIt.isRegistered<MenuService>() ? app.getIt<MenuService>() : MenuService(),
          timeService: app.getIt<TimeService>(),
        );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MainViewModel>.value(value: vm),
          ChangeNotifierProvider<InitialScreeningListViewModel>.value(value: listVm),
          ChangeNotifierProvider<InitialScreeningViewModel>.value(value: screeningVm),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(child: SizedBox()),
                ChildInfoSidebar(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return vm;
  }

  testWidgets('默认当前儿童 TAB：标题靠右、基础信息与出生日期在孕次产次上方', (tester) async {
    await pumpSidebar(tester);

    // 标题栏：收起钮（Tooltip）在左、标题「当前儿童」靠右
    expect(find.byTooltip('收起'), findsOneWidget);
    final collapseCenter = tester.getCenter(find.byTooltip('收起'));
    final titleCenter = tester.getCenter(find.text('当前儿童'));
    expect(titleCenter.dx, greaterThan(collapseCenter.dx));

    expect(find.text('测试儿童'), findsOneWidget);
    expect(find.text('2023-09-01'), findsOneWidget);
    expect(find.text('出生日期'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('出生日期')).dy,
      lessThan(tester.getTopLeft(find.text('孕次产次')).dy),
    );
    expect(find.text('高危五色分级'), findsOneWidget);
    expect(find.text('早产（32~33⁺⁶周）'), findsOneWidget);
  });

  testWidgets('未选定儿童时侧边栏常驻，当前儿童 TAB 显示指引占位', (tester) async {
    await pumpSidebar(tester, withChild: false);

    expect(find.byType(ChildInfoSidebar), findsOneWidget);
    expect(find.text('未选定儿童'), findsOneWidget);
    expect(find.text('测试儿童'), findsNothing);
  });

  testWidgets('初筛 TAB：切入自动加载、列表字段与分页、翻页到第二页', (tester) async {
    final vm = await pumpSidebar(tester);

    await tester.tap(find.byTooltip('初筛儿童'));
    await tester.pumpAndSettle();

    // 标题切换 + 列表展示（第 1 页 10 条 / 共 12 条）
    expect(find.text('初筛儿童'), findsOneWidget);
    expect(find.text('第 1 / 2 页 · 共 12 条'), findsOneWidget);
    expect(find.text('筛查儿童0'), findsOneWidget);
    expect(find.text('12月龄'), findsWidgets);
    expect(find.text('异常'), findsWidgets);

    // 翻到第二页
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 2 页 · 共 12 条'), findsOneWidget);
    expect(find.text('筛查儿童10'), findsOneWidget);
    expect(find.text('筛查儿童11'), findsOneWidget);
    expect(find.text('筛查儿童0'), findsNothing);

    // 未影响当前儿童上下文
    expect(vm.child.id, 'child-1');
  });

  testWidgets('初筛 TAB 双击记录：切换当前儿童、打开初筛记录表菜单、登记月龄', (tester) async {
    // 注册双击链路依赖（ChildService 经 getIt 解析）
    final fakeChildService = FakeChildService(buildChild(), buildExt(), factors: buildFactors());
    app.getIt.registerLazySingleton<ChildService>(() => fakeChildService);
    addTearDown(app.getIt.unregister<ChildService>);

    final vm = MainViewModel(childService: fakeChildService);
    vm.setRoleMenus(buildMenus());
    final listVm = InitialScreeningListViewModel(
      screeningService: FakeScreeningListService([
        const InitialScreeningListItem(
          id: 'r9',
          childId: 'child-9',
          childName: '筛查儿童9',
          checkDate: '2026-06-15',
          checkMonth: 12,
          checkResult: '异常',
        ),
      ]),
    );
    final screeningVm = InitialScreeningViewModel(
      screeningService: FakeScreeningListService(const []),
      childService: fakeChildService,
      menuService: MenuService(),
      timeService: app.getIt<TimeService>(),
    );
    await pumpSidebar(tester, mainViewModel: vm, listViewModel: listVm, screeningViewModel: screeningVm);

    await tester.tap(find.byTooltip('初筛儿童'));
    await tester.pumpAndSettle();

    // 双击记录（双击判定约 300ms：两次 tap 间 pump 推进时钟）
    await tester.tap(find.text('筛查儿童9'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('筛查儿童9'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // 当前儿童上下文已切换到记录所属儿童
    expect(vm.child.id, 'child-9');
    expect(vm.child.name, '列表儿童');
    // 已自动打开初筛记录表菜单，且左侧菜单树的祖先模块「孤独症筛查」
    // 一并展开（与手工逐级点击菜单一致）
    expect(vm.selectedMenuId, 'm2');
    expect(vm.isExpanded('m1'), isTrue);
    // 已登记待定位月龄（页面挂载后消费并切到 12 月龄 TAB）
    expect(screeningVm.consumePendingOpenMonth(), 12);
  });

  testWidgets('复筛/诊断/干预 TAB：标题切换与暂缓开放占位', (tester) async {
    await pumpSidebar(tester);

    await tester.tap(find.byTooltip('复筛儿童'));
    await tester.pumpAndSettle();
    expect(find.text('复筛儿童'), findsOneWidget);
    expect(find.text('复筛儿童查询功能暂缓开放'), findsOneWidget);
    expect(find.text('检查日期'), findsOneWidget);
    expect(find.text('复筛结果'), findsOneWidget);

    await tester.tap(find.byTooltip('诊断儿童'));
    await tester.pumpAndSettle();
    expect(find.text('诊断儿童'), findsOneWidget);
    expect(find.text('诊断儿童查询功能暂缓开放'), findsOneWidget);

    await tester.tap(find.byTooltip('干预儿童'));
    await tester.pumpAndSettle();
    expect(find.text('干预儿童'), findsOneWidget);
    expect(find.text('干预儿童查询功能暂缓开放'), findsOneWidget);
    expect(find.text('管理日期'), findsOneWidget);
    expect(find.text('康复效果'), findsOneWidget);
  });

  testWidgets('暂缓 TAB 与初筛 TAB 共用日期查询栏（同款起始/截止日期框）', (tester) async {
    await pumpSidebar(tester);

    await tester.tap(find.byTooltip('复筛儿童'));
    await tester.pumpAndSettle();
    // 日期框 hint 即「起始/截止日期」，与初筛 TAB 同一 _buildQueryBar 实现
    expect(find.text('起始日期'), findsOneWidget);
    expect(find.text('截止日期'), findsOneWidget);
    expect(find.text('查询'), findsOneWidget);
    expect(find.text('重置'), findsOneWidget);
  });

  testWidgets('收起后仅保留竖排 TAB 图标，点图标展开并激活对应页', (tester) async {
    await pumpSidebar(tester);
    expect(find.text('高危五色分级'), findsOneWidget);

    await tester.tap(find.byTooltip('收起'));
    await tester.pumpAndSettle();
    expect(find.text('高危五色分级'), findsNothing);
    expect(find.byTooltip('展开侧边栏'), findsOneWidget);

    // 收起态点初筛 TAB 图标 → 展开并激活初筛列表
    await tester.tap(find.byTooltip('初筛儿童'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('收起'), findsOneWidget);
    expect(find.text('初筛儿童'), findsOneWidget);
    expect(find.textContaining('共 12 条'), findsOneWidget);
  });
}
