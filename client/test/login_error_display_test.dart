// 登录失败错误提示显示链路测试：
// 表单校验通过 → AuthService 抛异常 → ViewModel 记录 errorMessage → LoginPage 弹 SnackBar。
import 'package:client/main.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/view_models/login/login_view_model.dart';
import 'package:client/views/login/login_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 始终抛“用户名或密码错误”的伪认证服务。
class FakeAuthService extends AuthService {
  @override
  Future<Map<String, dynamic>> login(String username, String password) async {
    throw Exception('登录失败！用户名或密码错误');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    token = null;
  });

  Future<LoginViewModel> pumpLoginPage(
    WidgetTester tester, {
    AuthService? authService,
  }) async {
    // 与桌面浏览器一致的视口（默认 800x600 下表单会溢出，登录按钮无法命中）
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final viewModel = LoginViewModel(authService: authService);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: ChangeNotifierProvider.value(
          value: viewModel,
          child: const LoginPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return viewModel;
  }

  testWidgets('登录失败时应在页面上弹出错误 SnackBar', (tester) async {
    final viewModel = await pumpLoginPage(
      tester,
      authService: FakeAuthService(),
    );

    // 填写用户名、密码
    final textFields = find.byType(TextFormField);
    expect(textFields, findsNWidgets(2));
    await tester.enterText(textFields.at(0), 'doctor01');
    await tester.enterText(textFields.at(1), 'Doctor@123');
    await tester.pump();

    // 直接经 ViewModel 设置科室（下拉 overlay 的 tap 命中不稳定，与本测试目标无关）
    viewModel.selectDept('产科');
    await tester.pump();

    // 点击登录按钮
    await tester.tap(find.byType(FilledButton));
    await tester.pump(); // 触发 login() 异步开始
    await tester.pumpAndSettle();

    // 断言：ViewModel 记录了错误信息，SnackBar 展示了后端错误
    expect(viewModel.errorMessage, contains('用户名或密码错误'));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('用户名或密码错误'), findsOneWidget);
  });

  testWidgets('未选科室时点击登录不发请求、不弹提示（静默校验）', (tester) async {
    final viewModel = await pumpLoginPage(tester);

    final textFields = find.byType(TextFormField);
    await tester.enterText(textFields.at(0), 'doctor01');
    await tester.enterText(textFields.at(1), 'Doctor@123');
    await tester.pump();

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pumpAndSettle();

    // 校验失败路径：科室错误显示在输入框下方，无 SnackBar
    expect(viewModel.errorMessage, isNull);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('科室不能为空'), findsOneWidget);
  });
}
