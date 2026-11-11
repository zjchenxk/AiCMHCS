// 登录成功用户信息接线测试：
// 表单校验通过 → AuthService 返回 token+user → LoginViewModel 写入全局 loginUser →
// 登录页跳转前触发 MainViewModel.syncLoginUser() → 工作副本刷新为真实身份
// （医院/院区/科室名称优先用登录接口关联下发的真实数据，
// 未设置的字段保底本地默认示例）。
import 'package:client/main.dart';
import 'package:client/providers/font_provider.dart';
import 'package:client/providers/theme_provider.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/view_models/login/login_view_model.dart';
import 'package:client/view_models/main/main_view_model.dart';
import 'package:client/views/login/login_page.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 返回成功登录数据（doctor01 身份）的伪认证服务。
class FakeAuthService extends AuthService {
  /// 登录时捕获的角色 ID（断言登录请求带上下拉框绑定的角色 ID）。
  String? capturedRole;

  @override
  Future<List<Map<String, String>>> fetchUserRoles(String userCode) async {
    return [
      {'id': '2', 'roleName': '儿童心理医生'},
      {'id': '6', 'roleName': '系统管理员'},
    ];
  }

  @override
  Future<Map<String, dynamic>> login(String username, String password, String role) async {
    capturedRole = role;
    return {
      'token': 'test-token',
      'sessionKey': 'MDEyMzQ1Njc4OWFiY2RlZmdoaWprbG1ub3BxcnN0dXY=',
      'tokenType': 'Bearer',
      'expiresIn': 7200,
      'user': {
        'id': 2,
        'userCode': 'doctor01',
        'userName': '李医生',
        'userType': 'DOCTOR',
        'userTypeName': '儿童心理医生',
        'phone': '13800000001',
        'hospId': '1',
        'hospName': '测试三级医院',
        'campusId': '8',
        'campusName': '城南院区',
        'deptId': '7',
        'deptName': '儿童心理科',
      },
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    token = null;
    sessionKey = null;
    loginUser = null;
  });

  testWidgets('登录成功后全局 loginUser 写入并同步进 MainViewModel 工作副本', (tester) async {
    // 与桌面浏览器一致的视口（默认 800x600 下表单会溢出，登录按钮无法命中）
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fakeAuth = FakeAuthService();
    final loginViewModel = LoginViewModel(authService: fakeAuth);
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

    // 填写用户名、密码并选角色（角色值域来自 FakeAuthService.fetchUserRoles，
    // 模拟输入用户名回车后从后端加载该用户拥有的角色）
    final textFields = find.byType(TextFormField);
    await tester.enterText(textFields.at(0), 'doctor01');
    await tester.enterText(textFields.at(1), 'Doctor@123');
    await loginViewModel.loadRoles();
    await tester.pump();
    expect(loginViewModel.roles, isNotEmpty); //角色下拉框已绑定该用户名拥有的角色
    loginViewModel.selectRole('2');
    await tester.pump();

    // 点击登录，等待异步登录与路由跳转完成
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pumpAndSettle();

    // 全局 loginUser 为后端下发的真实身份
    expect(token, 'test-token');
    expect(sessionKey, 'MDEyMzQ1Njc4OWFiY2RlZmdoaWprbG1ub3BxcnN0dXY=');
    expect(fakeAuth.capturedRole, '2'); //登录请求携带下拉框绑定的角色 ID
    expect(loginUser, isNotNull);
    expect(loginUser!.id, 2);
    expect(loginUser!.userCode, 'doctor01');
    expect(loginUser!.userName, '李医生');
    expect(loginUser!.userType, 'DOCTOR');

    // MainViewModel 工作副本：身份真实、医院/院区/科室为登录接口
    // 关联下发的真实数据（不被本地默认覆盖）
    expect(mainViewModel.loginUser.id, 2);
    expect(mainViewModel.loginUser.userName, '李医生');
    expect(mainViewModel.loginUser.hospId, '1');
    expect(mainViewModel.loginUser.hospName, '测试三级医院');
    expect(mainViewModel.loginUser.campusName, '城南院区');
    expect(mainViewModel.loginUser.deptId, '7');
    expect(mainViewModel.loginUser.deptName, '儿童心理科');

    // 顶栏用户菜单数据源使用真实姓名
    expect(mainViewModel.userName, '李医生');
  });

  test('未设置归属的账号：工作副本名称字段保底本地默认示例', () {
    loginUser = const LoginUser(
      id: 3,
      userCode: 'teacher01',
      userName: '李老师',
      userType: 'TEACHER',
    );
    final vm = MainViewModel();
    vm.syncLoginUser();
    expect(vm.loginUser.userName, '李老师');
    expect(vm.loginUser.hospName, '首都医科大学附属北京儿童医院');
    expect(vm.loginUser.campusName, '顺义院区');
    expect(vm.loginUser.deptName, '儿童保健科');
  });
}
