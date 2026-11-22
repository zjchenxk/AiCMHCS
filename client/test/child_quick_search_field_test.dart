// 主界面顶部儿童快速搜索框交互测试：再次获得焦点且已有内容时默认全选
// 文本（便于清除/覆盖）；MainViewModel 当前儿童上下文变更（选定/切换）
// 时自动清空输入内容，同一儿童重复写入不清空（按 ID 去重）。
import 'package:client/main.dart' as app;
import 'package:client/services/time_service.dart';
import 'package:client/view_models/main/main_view_model.dart';
import 'package:client/views/main/child_quick_search_field.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

void main() {
  setUp(() {
    // setCurrentChild 构建侧边栏基础数据与实际年龄依赖全局时间服务
    //（未校准即本地时钟）
    if (!app.getIt.isRegistered<TimeService>()) {
      app.getIt.registerLazySingleton<TimeService>(() => TimeService());
    }
  });

  Widget wrapWidget(MainViewModel viewModel) {
    return ChangeNotifierProvider<MainViewModel>.value(
      value: viewModel,
      child: MaterialApp(
        localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
        home: Scaffold(
          body: Center(
            child: ChildQuickSearchField(
              onSearch: (_) {},
              onAdvancedSearch: () {},
            ),
          ),
        ),
      ),
    );
  }

  TextEditingController controllerOf(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).controller!;

  testWidgets('再次获得焦点且有内容时默认全选文本', (tester) async {
    final vm = MainViewModel();
    await tester.pumpWidget(wrapWidget(vm));

    await tester.enterText(find.byType(TextField), '王小明');
    await tester.pumpAndSettle();
    final controller = controllerOf(tester);
    expect(controller.text, '王小明');

    // 失焦后再聚焦（「再次获得输入焦点」场景）→ 全选
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(controller.selection, const TextSelection(baseOffset: 0, extentOffset: 3));

    // 失焦 → 修改文本 → 再聚焦 → 依旧全选新文本
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    controller.text = '李小红';
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(controller.selection, const TextSelection(baseOffset: 0, extentOffset: 3));
  });

  testWidgets('空内容时获得焦点不构造选区', (tester) async {
    final vm = MainViewModel();
    await tester.pumpWidget(wrapWidget(vm));

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final controller = controllerOf(tester);
    expect(controller.text, isEmpty);
    expect(controller.selection.isCollapsed, isTrue, reason: '空文本无内容可全选，保持折叠光标');
  });

  testWidgets('MainViewModel 当前儿童变更时清空输入内容', (tester) async {
    final vm = MainViewModel();
    await tester.pumpWidget(wrapWidget(vm));
    final controller = controllerOf(tester);

    await tester.enterText(find.byType(TextField), '王小明');
    await tester.pumpAndSettle();
    expect(controller.text, '王小明');

    // 选定儿童（ID 变化）→ 搜索框清空
    vm.setCurrentChild(_testChildInfo(id: 'child-1'));
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);

    // 再输入关键词，切换到另一儿童 → 再次清空
    await tester.enterText(find.byType(TextField), '张小刚');
    await tester.pumpAndSettle();
    vm.setCurrentChild(_testChildInfo(id: 'child-2'));
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);

    // 同一儿童重复写入（ID 未变）→ 不清空
    await tester.enterText(find.byType(TextField), '李小红');
    await tester.pumpAndSettle();
    vm.setCurrentChild(_testChildInfo(id: 'child-2'));
    await tester.pumpAndSettle();
    expect(controller.text, '李小红');
  });
}

/// 测试用儿童基础档案（最小必填集）。
ChildInfo _testChildInfo({required String id}) => ChildInfo(
  id: id,
  checkTime: '2026-11-22',
  name: '测试儿童$id',
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
);
