// 高级搜索对话框高危因素条件测试：多选选择器从本院字典（Fake 服务）加载
// 因素、勾选后随查询透传 highRiskFactorIds；不选时请求不带该键（null）
// ——「任一命中」过滤由服务端实现，客户端仅负责收集与透传。
import 'package:client/main.dart' as app;
import 'package:client/services/child_service.dart';
import 'package:client/services/high_risk_factor_service.dart';
import 'package:client/widgets/child_advanced_search_dialog.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 捕获 advancedQuery 入参的伪儿童服务（返回空结果页）。
class _FakeChildService extends ChildService {
  List<String>? capturedFactorIds;

  @override
  Future<ChildAdvancedQueryPage> advancedQuery({
    String? checkTimeFrom,
    String? checkTimeTo,
    String? birthDateFrom,
    String? birthDateTo,
    String? name,
    String? sex,
    String? visitCardNo,
    String? certificateNo,
    String? phone,
    String? guardianName,
    List<String>? highRiskFactorIds,
    int? gestationalWeekFrom,
    int? gestationalWeekTo,
    int? birthWeightFrom,
    int? birthWeightTo,
    int page = 1,
    int pageSize = 20,
  }) async {
    capturedFactorIds = highRiskFactorIds;
    return (<ChildInfo>[], 0);
  }
}

/// 返回固定本院字典的伪高危因素服务。
class _FakeHighRiskFactorService extends HighRiskFactorService {
  @override
  Future<List<BaseHighRiskFactor>> queryAll() async => [
    BaseHighRiskFactor(
      id: 'HRF-2',
      riskFactorCode: '04990001',
      riskFactorName: '妊娠期高血压',
      riskColor: '红色',
      creatorId: 'u1',
      creatorName: '张医生',
      hospId: 'h1',
      hospName: '示例人民医院',
    ),
    BaseHighRiskFactor(
      id: 'HRF-3',
      riskFactorCode: '02990001',
      riskFactorName: '低出生体重',
      riskColor: '黄色',
      creatorId: 'u1',
      creatorName: '张医生',
      hospId: 'h1',
      hospName: '示例人民医院',
    ),
  ];
}

void main() {
  setUp(() {
    // 对话框经 getIt 取高危因素字典服务（isRegistered 守卫防重复注册）
    if (!app.getIt.isRegistered<HighRiskFactorService>()) {
      app.getIt.registerLazySingleton<HighRiskFactorService>(() => _FakeHighRiskFactorService());
    }
  });

  Future<void> openDialog(WidgetTester tester, ChildService service) async {
    // 对话框含双 Tab 高内容区（560）+ 条件全量行，默认 800×600 视口下
    // 高危因素行在可视区外（tap 落在遮罩上），须放大视口
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showChildAdvancedSearchDialog(context, service: service),
                child: const Text('打开高级搜索'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开高级搜索'));
    await tester.pumpAndSettle();
  }

  testWidgets('不选高危因素时查询请求不带 highRiskFactorIds（null 不过滤）', (tester) async {
    final service = _FakeChildService();
    await openDialog(tester, service);

    await tester.tap(find.widgetWithText(FilledButton, '查询'));
    await tester.pumpAndSettle();

    expect(service.capturedFactorIds, isNull);
  });

  testWidgets('勾选两个高危因素后查询随请求透传 ID 列表', (tester) async {
    final service = _FakeChildService();
    await openDialog(tester, service);

    // 打开多选选择器（字典经 Fake 服务即时加载）
    await tester.tap(find.text('请选择高危因素（可多选，留空不过滤）'));
    await tester.pumpAndSettle();

    // 勾选两项（点条目文本即切换勾选）
    await tester.tap(find.text('妊娠期高血压（04990001）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('低出生体重（02990001）'));
    await tester.pumpAndSettle();

    // 确定提交（关闭选择器），字段回显所选摘要（按五色排序口径：黄在红前）
    await tester.tap(find.widgetWithText(FilledButton, '确 定'));
    await tester.pumpAndSettle();
    expect(find.text('低出生体重（02990001）、妊娠期高血压（04990001）'), findsOneWidget);

    // 查询 → 透传所选 ID（插入序）
    await tester.tap(find.widgetWithText(FilledButton, '查询'));
    await tester.pumpAndSettle();
    expect(service.capturedFactorIds, ['HRF-2', 'HRF-3']);
  });

  testWidgets('选择器内清空后确定 → 提交空集（清除过滤语义）', (tester) async {
    final service = _FakeChildService();
    await openDialog(tester, service);

    await tester.tap(find.text('请选择高危因素（可多选，留空不过滤）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('妊娠期高血压（04990001）'));
    await tester.pumpAndSettle();
    // 清空 → 确定仍可用（空集=清除过滤）
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确 定'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '查询'));
    await tester.pumpAndSettle();
    expect(service.capturedFactorIds, isNull, reason: '空集提交后在查询收集处归一为 null（不过滤）');
  });
}
