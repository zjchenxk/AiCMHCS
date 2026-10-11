// 登录成功用户信息接线测试：
// 表单校验通过 → AuthService 返回 token+user → LoginViewModel 写入全局 loginUser →
// 登录页跳转前触发 MainViewModel.syncLoginUser() → 工作副本刷新为真实身份
// （医院/院区/科室保留本地默认，后端暂不下发）。
import 'package:client/main.dart';
import 'package:client/providers/font_provider.dart';
import 'package:client/providers/theme_provider.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/view_models/login/login_view_model.dart';
import 'package:client/view_models/main/main_view_model.dart';
import 'package:client/views/login/login_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 返回成功登录数据（doctor01 身份）的伪认证服务。
class FakeAuthService extends AuthService {
  @override
  Future<Map<String, dynamic>> login(String username, String password) async {
    return {
      'token': 'test-token',
      'tokenType': 'Bearer',
      'expiresIn': 7200,
      'user': {
        'id': 2,
        'userCode': 'doctor01',
        'userName': '李医生',
        'roleCode': 'DOCTOR',
        'roleName': '儿童心理医生',
        'phone': '13800000001',
        'lastLoginAt': '2026-10-11 09:00:00',
        'organId': null,
        'organName': null,
        'branchId': null,
        'branchName': null,
        'deptId': null,
        'deptName': null,
      },
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    token = null;
    loginUser = null;
  });

  testWidgets('登录成功后全局 loginUser 写入并同步进 MainViewModel 工作副本', (tester) async {
    // 与桌面浏览器一致的视口（默认 800x600 下表单会溢出，登录按钮无法命中）
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final loginViewModel = LoginViewModel(authService: FakeAuthService());
    final mainViewModel = MainViewModel();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (context) => ThemeProvider()),
          ChangeNotifierProvider(create: (context) => FontProvider()),
          ChangeNotifierProvider.value(value: loginViewModel),
          ChangeNotifierProvider.value(value: mainViewModel),
        ],
        // 与 main.dart 一致的响应式包装：跳转后的 MainPage 依赖断点分支
        // （测试视口 1400 宽 → DESKTOP，与桌面运行环境一致）
        child: MaterialApp(
          localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
          supportedLocales: const [Locale('en')],
          builder: (context, child) => ResponsiveBreakpoints.builder(
            child: child!,
            breakpoints: const [
              Breakpoint(start: 0, end: 450, name: MOBILE),
              Breakpoint(start: 451, end: 800, name: TABLET),
              Breakpoint(
                start: 801,
                end: double.infinity,
                name: DESKTOP,
              ),
            ],
          ),
          home: const LoginPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 填写用户名、密码并选科室
    final textFields = find.byType(TextFormField);
    await tester.enterText(textFields.at(0), 'doctor01');
    await tester.enterText(textFields.at(1), 'Doctor@123');
    loginViewModel.selectDept('产科');
    await tester.pump();

    // 点击登录，等待异步登录与路由跳转完成
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pumpAndSettle();

    // 全局 loginUser 为后端下发的真实身份
    expect(token, 'test-token');
    expect(loginUser, isNotNull);
    expect(loginUser!.id, 2);
    expect(loginUser!.userCode, 'doctor01');
    expect(loginUser!.userName, '李医生');
    expect(loginUser!.roleCode, 'DOCTOR');

    // MainViewModel 工作副本：身份真实、医院/院区/科室保留本地默认
    expect(mainViewModel.loginUser.id, 2);
    expect(mainViewModel.loginUser.userName, '李医生');
    expect(mainViewModel.loginUser.organName, '首都医科大学附属北京儿童医院');
    expect(mainViewModel.loginUser.branchName, '顺义院区');
    expect(mainViewModel.loginUser.deptId, 'D001');
    expect(mainViewModel.loginUser.deptName, '儿童保健科');

    // 顶栏用户菜单数据源使用真实姓名
    expect(mainViewModel.userName, '李医生');
  });
}
