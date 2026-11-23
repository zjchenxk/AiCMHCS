import 'package:client/models/current_child.dart';
import 'package:client/services/time_service.dart';
import 'package:client/view_models/home/home_view_model.dart';
import 'package:client/views/home/home_page.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('首页 Dashboard 渲染四个板块与 KPI 标签', (tester) async {
    final timeService = TimeService();
    final viewModel = HomeViewModel(timeService: timeService);
    expect(await viewModel.loadDashboard(), isTrue);

    await tester.pumpWidget(
      ChangeNotifierProvider<HomeViewModel>.value(
        value: viewModel,
        child: MaterialApp(
          home: Scaffold(
            body: HomePage(
              loginUser: LoginUser(id: 'u1', userCode: 'admin', userName: '管理员', roleId: 'r1'),
              // DateTime 构造非 const，CurrentChild 实例不取 const
              child: CurrentChild(
                visitCardNo: '',
                patientId: '',
                name: '',
                gender: '',
                birthDate: DateTime(2023, 1, 1),
                phone: '',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 四个板块标题
    expect(find.text('数量统计'), findsOneWidget);
    expect(find.text('初筛统计'), findsOneWidget);
    expect(find.text('复筛统计'), findsOneWidget);
    expect(find.text('诊断统计'), findsOneWidget);

    // KPI 三标签
    expect(find.text('初筛异常儿童数量'), findsOneWidget);
    expect(find.text('复筛异常儿童数量'), findsOneWidget);
    expect(find.text('确诊儿童数量'), findsOneWidget);

    // 各板块起止月筛选控件（默认区间「起」共 4 处）
    final range = viewModel.rangeOf(DashboardBoard.kpi);
    expect(find.text(range.from), findsNWidgets(4));
    expect(find.text(range.to), findsNWidgets(4));

    // 图例：初筛 2 项、复筛/诊断各 3 项（复筛与诊断的「复查人数」各一处）
    expect(find.text('初筛人数'), findsOneWidget);
    expect(find.text('异常人数'), findsNWidgets(2));
    expect(find.text('复筛人数'), findsOneWidget);
    expect(find.text('诊断人数'), findsOneWidget);
    expect(find.text('确认人数'), findsOneWidget);
    expect(find.text('复查人数'), findsNWidgets(2));
  });
}
