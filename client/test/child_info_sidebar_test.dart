// 右侧儿童信息侧边栏渲染测试：当前儿童写入后展示头像/姓名/性别/年龄、
// 扩展档案字段（G/P、出生孕周、出生体重、电话）；五色分级与高危因素
// 列表来自 CHILD_HIGH_RISK_FACTOR（颜色取最高级别、紫色叠加），REMARK
// 非空时显示在因素名称下方；库内无记录时显示绿色「无高危因素」；加载
// 失败提供重试；收起后仅保留竖条，展开后内容恢复。
import 'package:client/main.dart' as app;
import 'package:client/services/child_service.dart';
import 'package:client/services/time_service.dart';
import 'package:client/view_models/main/main_view_model.dart';
import 'package:client/views/main/child_info_sidebar.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// 返回固定儿童整档与高危因素记录的伪儿童服务。
class FakeChildService extends ChildService {
  FakeChildService(this.child, this.ext, {this.factors = const [], this.failHighRisk = false});

  final ChildInfo child;
  final ChildExtInfo ext;
  List<ChildHighRiskFactor> factors;
  bool failHighRisk;

  @override
  Future<ChildArchive> load(String id) async => (child, ext, const <ChildGuardianInfo>[]);

  @override
  Future<ChildPhoto?> latestPhoto(String childId) async => null;

  @override
  Future<List<ChildHighRiskFactor>> highRiskFactors(String childId) async {
    if (failHighRisk) throw Exception('模拟高危因素查询失败');
    return factors;
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

void main() {
  setUp(() {
    // 侧边栏构建年龄/演示检查时间轴依赖全局时间服务（未校准即本地时钟）
    if (!app.getIt.isRegistered<TimeService>()) {
      app.getIt.registerLazySingleton<TimeService>(() => TimeService());
    }
  });

  Future<MainViewModel> pumpSidebar(
    WidgetTester tester, {
    ChildInfo? child,
    ChildExtInfo? ext,
    List<ChildHighRiskFactor>? factors,
    FakeChildService? service,
  }) async {
    final target = child ?? buildChild();
    final fake = service ?? FakeChildService(target, ext ?? buildExt(), factors: factors ?? buildFactors());
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

  testWidgets('展示基础信息与数据库五色分级/高危因素，备注显示在名称下方', (tester) async {
    await pumpSidebar(tester);

    expect(find.text('当前儿童'), findsOneWidget);
    expect(find.text('测试儿童'), findsOneWidget);
    expect(find.text('男'), findsOneWidget);
    expect(find.text('13800000000'), findsOneWidget);
    expect(find.text('G2 P1'), findsOneWidget);
    expect(find.text('33周+4天'), findsOneWidget);
    expect(find.text('2280 g'), findsOneWidget);

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

    // 高危因素完全来自数据库，不再由扩展信息推导（2280 g 不产生体重因素）
    expect(find.text('低出生体重（2000~2500 g）'), findsNothing);

    // 仅检查记录标注演示数据（高危因素来自数据库）
    expect(find.text('演示数据'), findsOneWidget);

    // 3 岁儿童已超出早产儿矫正窗口（矫正月龄 24 个月）→ 不展示矫正年龄
    expect(find.textContaining('矫正年龄'), findsNothing);
  });

  testWidgets('库内无高危因素时显示绿色与无高危因素占位', (tester) async {
    await pumpSidebar(tester, factors: const []);

    expect(find.textContaining('综合分级：绿色'), findsOneWidget);
    expect(find.text('无高危因素'), findsOneWidget);
    expect(find.text('演示数据'), findsOneWidget);
  });

  testWidgets('高危因素加载失败显示重试，重试成功后展示数据库因素', (tester) async {
    final fake = FakeChildService(buildChild(), buildExt(), factors: buildFactors(), failHighRisk: true);
    await pumpSidebar(tester, service: fake);

    expect(find.text('高危因素加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('早产（32~33⁺⁶周）'), findsNothing);

    fake.failHighRisk = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('早产（32~33⁺⁶周）'), findsOneWidget);
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
