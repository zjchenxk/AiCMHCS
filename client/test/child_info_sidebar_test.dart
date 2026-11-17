// 右侧儿童信息侧边栏渲染测试：当前儿童写入后展示头像/姓名/性别/年龄、
// 扩展档案字段（G/P、出生孕周、出生体重、电话）与按共识评估的五色
// 高危分级/因素；扩展档案存在时不应标注「演示数据」（检查记录除外）；
// 收起后仅保留竖条，展开后内容恢复。
import 'package:client/main.dart' as app;
import 'package:client/services/child_service.dart';
import 'package:client/services/time_service.dart';
import 'package:client/view_models/main/main_view_model.dart';
import 'package:client/views/main/child_info_sidebar.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// 返回固定儿童整档的伪儿童服务（扩展信息由用例注入）。
class FakeChildService extends ChildService {
  FakeChildService(this.child, this.ext);

  final ChildInfo child;
  final ChildExtInfo ext;

  @override
  Future<ChildArchive> load(String id) async => (child, ext, const <ChildGuardianInfo>[]);

  @override
  Future<ChildPhoto?> latestPhoto(String childId) async => null;
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

/// 测试用儿童扩展档案（33⁺⁴周早产、2280 g、母亲梅毒感染 → 橙色 + 紫色叠加）。
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
  hasSyphilisInfection: '1',
);

void main() {
  setUp(() {
    // 侧边栏构建年龄/演示检查时间轴依赖全局时间服务（未校准即本地时钟）
    if (!app.getIt.isRegistered<TimeService>()) {
      app.getIt.registerLazySingleton<TimeService>(() => TimeService());
    }
  });

  Future<MainViewModel> pumpSidebar(WidgetTester tester, {ChildInfo? child, ChildExtInfo? ext}) async {
    final target = child ?? buildChild();
    final vm = MainViewModel(childService: FakeChildService(target, ext ?? buildExt()));
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

  testWidgets('展示儿童基础信息、扩展字段与五色高危分级/因素', (tester) async {
    await pumpSidebar(tester);

    expect(find.text('当前儿童'), findsOneWidget);
    expect(find.text('测试儿童'), findsOneWidget);
    expect(find.text('男'), findsOneWidget);
    expect(find.text('13800000000'), findsOneWidget);
    expect(find.text('G2 P1'), findsOneWidget);
    expect(find.text('33周+4天'), findsOneWidget);
    expect(find.text('2280 g'), findsOneWidget);

    // 33⁺⁴周 + 2280 g → 橙色；母亲梅毒 → 紫色叠加
    expect(find.text('高危五色分级'), findsOneWidget);
    expect(find.text('橙色'), findsWidgets);
    expect(find.text('紫色'), findsWidgets);
    expect(find.textContaining('综合分级：橙色'), findsOneWidget);
    expect(find.textContaining('叠加紫色'), findsOneWidget);
    expect(find.text('母亲梅毒感染'), findsOneWidget);

    // 扩展档案存在 → 高危因素为真实评估（仅检查记录标注演示数据）
    expect(find.text('高危因素'), findsOneWidget);
    expect(find.text('演示数据'), findsOneWidget);

    // 3 岁儿童已超出早产儿矫正窗口（矫正月龄 24 个月）→ 不展示矫正年龄
    expect(find.textContaining('矫正年龄'), findsNothing);
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
