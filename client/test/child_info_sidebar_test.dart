// 右侧儿童信息侧边栏渲染测试：当前儿童写入后展示头像/姓名/性别/年龄、
// 出生日期（在孕次产次上方）、扩展档案字段（G/P、出生孕周、出生体重、
// 电话）；五色分级/高危因素来自 CHILD_HIGH_RISK_FACTOR（REMARK 显示在
// 名称下方）；历次检查时间轴来自 CHILD_CHECK_RECORD（CHECK_DATE /
// CHECK_TYPE / CHECK_RESULT，不再有演示数据）；库内无记录时给出空态；
// 加载失败提供重试；收起后仅保留竖条，展开后内容恢复。
import 'package:client/main.dart' as app;
import 'package:client/services/child_service.dart';
import 'package:client/services/time_service.dart';
import 'package:client/view_models/main/main_view_model.dart';
import 'package:client/views/main/child_info_sidebar.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// 返回固定儿童整档、高危因素与检查记录的伪儿童服务。
class FakeChildService extends ChildService {
  FakeChildService(
    this.child,
    this.ext, {
    this.factors = const [],
    this.records = const [],
    this.failHighRisk = false,
    this.failCheckRecords = false,
  });

  final ChildInfo child;
  final ChildExtInfo ext;
  List<ChildHighRiskFactor> factors;
  List<ChildCheckRecord> records;
  bool failHighRisk;
  bool failCheckRecords;

  @override
  Future<ChildArchive> load(String id) async => (child, ext, const <ChildGuardianInfo>[]);

  @override
  Future<ChildPhoto?> latestPhoto(String childId) async => null;

  @override
  Future<List<ChildHighRiskFactor>> highRiskFactors(String childId) async {
    if (failHighRisk) throw Exception('模拟高危因素查询失败');
    return factors;
  }

  @override
  Future<List<ChildCheckRecord>> checkRecords(String childId) async {
    if (failCheckRecords) throw Exception('模拟检查记录查询失败');
    return records;
  }
}

/// 测试用儿童基础档案（默认 2023-09-01 出生）。
ChildInfo buildChild({String birthDate = '2023-09-01'}) => ChildInfo(
  id: 'child-1',
  checkTime: '2026-11-17',
  name: '测试儿童',
  sex: '1',
  birthDate: birthDate,
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

/// 测试用儿童扩展档案（33⁺⁴周早产、2280 g）。
ChildExtInfo buildExt() => const ChildExtInfo(
  childId: 'child-1',
  creatorId: 'user-1',
  creatorName: '测试医生',
  hospId: 'hosp-1',
  hospName: '测试医院',
  gestationalWeek: '33',
  gestationalDay: '4',
  birthWeight: '2280',
  gravidity: '2',
  parity: '1',
  // 高危分级不再由扩展信息推导，此字段存在也不应影响侧边栏
  hasSyphilisInfection: '1',
);

/// 构造一条已保存的高危因素记录（数据库快照口径）。
ChildHighRiskFactor buildFactor(String id, String name, String color, [String? remark]) => ChildHighRiskFactor(
  id: id,
  childId: 'child-1',
  highRiskFactorId: 'dict-$id',
  riskFactorCode: '03$id',
  riskFactorName: name,
  riskColor: color,
  remark: remark,
  creatorId: 'user-1',
  creatorName: '测试医生',
  hospId: 'hosp-1',
  hospName: '测试医院',
);

/// 测试用高危因素记录：橙色 + 黄色 + 紫色（紫色可与橙色叠加）。
List<ChildHighRiskFactor> buildFactors() => [
  buildFactor('1', '早产（32~33⁺⁶周）', '橙色', '出生孕周 33 周 + 4 天，单胎'),
  buildFactor('2', '母亲妊娠期高血压疾病', '黄色'),
  buildFactor('3', '母亲梅毒感染', '紫色'),
];

/// 构造一条检查记录（CHILD_CHECK_RECORD 查询口径）。
ChildCheckRecord buildCheckRecord(String id, String date, String type, String result) => ChildCheckRecord(
  id: id,
  childId: 'child-1',
  checkDate: date,
  ageYear: '3',
  ageMonth: '2',
  ageDay: '9',
  checkType: type,
  checkResult: result,
  creatorId: 'user-1',
  creatorName: '测试医生',
  hospId: 'hosp-1',
  hospName: '测试医院',
);

/// 测试用检查记录（数据库已倒序，模型层再排一次）。
List<ChildCheckRecord> buildCheckRecords() => [
  buildCheckRecord('r1', '2026-11-10', '孤独症初筛', '未见异常'),
  buildCheckRecord('r2', '2026-06-01', '听力筛查', '双耳通过'),
];

void main() {
  setUp(() {
    // 侧边栏构建年龄依赖全局时间服务（未校准即本地时钟）
    if (!app.getIt.isRegistered<TimeService>()) {
      app.getIt.registerLazySingleton<TimeService>(() => TimeService());
    }
  });

  Future<MainViewModel> pumpSidebar(
    WidgetTester tester, {
    ChildInfo? child,
    ChildExtInfo? ext,
    List<ChildHighRiskFactor>? factors,
    List<ChildCheckRecord>? checkRecords,
    FakeChildService? service,
  }) async {
    final target = child ?? buildChild();
    final fake =
        service ??
        FakeChildService(
          target,
          ext ?? buildExt(),
          factors: factors ?? buildFactors(),
          records: checkRecords ?? buildCheckRecords(),
        );
    final vm = MainViewModel(childService: fake);
    vm.setCurrentChild(target);
    await tester.pumpWidget(
      ChangeNotifierProvider<MainViewModel>.value(
        value: vm,
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

  testWidgets('展示基础信息、出生日期与数据库五色分级/高危因素/检查记录', (tester) async {
    await pumpSidebar(tester);

    expect(find.text('当前儿童'), findsOneWidget);
    expect(find.text('测试儿童'), findsOneWidget);
    expect(find.text('男'), findsOneWidget);
    expect(find.text('13800000000'), findsOneWidget);
    expect(find.text('G2 P1'), findsOneWidget);
    expect(find.text('33周+4天'), findsOneWidget);
    expect(find.text('2280 g'), findsOneWidget);

    // 出生日期显示在孕次产次上方
    expect(find.text('出生日期'), findsOneWidget);
    expect(find.text('2023-09-01'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('出生日期')).dy,
      lessThan(tester.getTopLeft(find.text('孕次产次')).dy),
    );

    // 橙色（早产）+ 紫色（梅毒）→ 综合分级橙色、紫色叠加
    expect(find.text('高危五色分级'), findsOneWidget);
    expect(find.text('橙色'), findsWidgets);
    expect(find.text('紫色'), findsWidgets);
    expect(find.textContaining('综合分级：橙色'), findsOneWidget);
    expect(find.textContaining('叠加紫色'), findsOneWidget);
    expect(find.text('早产（32~33⁺⁶周）'), findsOneWidget);
    expect(find.text('母亲妊娠期高血压疾病'), findsOneWidget);
    expect(find.text('母亲梅毒感染'), findsOneWidget);

    // REMARK 显示在因素名称下方
    final nameTop = tester.getTopLeft(find.text('早产（32~33⁺⁶周）')).dy;
    final remarkTop = tester.getTopLeft(find.text('出生孕周 33 周 + 4 天，单胎')).dy;
    expect(remarkTop, greaterThan(nameTop));

    // 历次检查来自 CHILD_CHECK_RECORD（日期/名称/结果），最新在前
    expect(find.text('孤独症初筛'), findsOneWidget);
    expect(find.text('未见异常'), findsOneWidget);
    expect(find.text('听力筛查'), findsOneWidget);
    expect(find.text('双耳通过'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('2026-11-10')).dy,
      lessThan(tester.getTopLeft(find.text('2026-06-01')).dy),
    );

    // 高危因素/检查记录均来自数据库，不再有演示数据标记
    expect(find.text('演示数据'), findsNothing);

    // 3 岁儿童已超出早产儿矫正窗口（矫正月龄 24 个月）→ 不展示矫正年龄
    expect(find.textContaining('矫正年龄'), findsNothing);
  });

  testWidgets('库内无高危因素/检查记录时显示空态', (tester) async {
    await pumpSidebar(tester, factors: const [], checkRecords: const []);

    expect(find.textContaining('综合分级：绿色'), findsOneWidget);
    expect(find.text('无高危因素'), findsOneWidget);
    expect(find.text('暂无检查记录'), findsOneWidget);
    expect(find.text('演示数据'), findsNothing);
  });

  testWidgets('高危因素加载失败显示重试，重试成功后展示数据库因素', (tester) async {
    final fake = FakeChildService(buildChild(), buildExt(), factors: buildFactors(), records: buildCheckRecords(), failHighRisk: true);
    await pumpSidebar(tester, service: fake);

    expect(find.text('高危因素加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('早产（32~33⁺⁶周）'), findsNothing);

    fake.failHighRisk = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('早产（32~33⁺⁶周）'), findsOneWidget);
  });

  testWidgets('检查记录加载失败显示重试，重试成功后展示数据库记录', (tester) async {
    final fake = FakeChildService(buildChild(), buildExt(), factors: buildFactors(), records: buildCheckRecords(), failCheckRecords: true);
    await pumpSidebar(tester, service: fake);

    expect(find.text('检查记录加载失败'), findsOneWidget);
    expect(find.text('孤独症初筛'), findsNothing);

    fake.failCheckRecords = false;
    await tester.ensureVisible(find.text('重试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('孤独症初筛'), findsOneWidget);
  });

  testWidgets('早产儿在矫正窗口内同时展示实足年龄与矫正年龄', (tester) async {
    // 出生 100 天、33⁺⁴ 周早产 → 矫正年龄约 1 个月，仍在窗口内
    final birth = DateTime.now().subtract(const Duration(days: 100));
    final birthDate = '${birth.year.toString().padLeft(4, '0')}-${birth.month.toString().padLeft(2, '0')}-${birth.day.toString().padLeft(2, '0')}';
    await pumpSidebar(tester, child: buildChild(birthDate: birthDate));

    expect(find.textContaining('矫正年龄'), findsOneWidget);
    expect(find.text('测试儿童'), findsOneWidget);
  });

  testWidgets('收起后仅保留竖条，展开后内容恢复', (tester) async {
    await pumpSidebar(tester);
    expect(find.text('高危因素'), findsOneWidget);

    await tester.tap(find.byTooltip('收起'));
    await tester.pumpAndSettle();
    expect(find.text('高危因素'), findsNothing);
    expect(find.byTooltip('展开儿童信息'), findsOneWidget);

    await tester.tap(find.byTooltip('展开儿童信息'));
    await tester.pumpAndSettle();
    expect(find.text('高危因素'), findsOneWidget);
  });
}
