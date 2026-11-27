import 'dart:ui' show PlatformDispatcher;

import 'package:client/providers/font_provider.dart';
import 'package:client/providers/theme_provider.dart';
import 'package:client/services/account_service.dart';
import 'package:client/services/admin_divisions_service.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/services/base/base_service.dart';
import 'package:client/services/campus_service.dart';
import 'package:client/services/child_service.dart';
import 'package:client/services/department_service.dart';
import 'package:client/services/dict_service.dart';
import 'package:client/services/high_risk_factor_exclusion_service.dart';
import 'package:client/services/high_risk_factor_service.dart';
import 'package:client/services/holiday_service.dart';
import 'package:client/services/hospital_service.dart';
import 'package:client/services/initial_screening_service.dart';
import 'package:client/services/log_service.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/services/role_service.dart';
import 'package:client/services/time_service.dart';
import 'package:client/services/user_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:client/view_models/asd/initial_screening_view_model.dart';
import 'package:client/view_models/child/child_create_view_model.dart';
import 'package:client/view_models/child/photo_management_view_model.dart';
import 'package:client/view_models/home/home_view_model.dart';
import 'package:client/view_models/main/main_view_model.dart';
import 'package:client/view_models/login/login_view_model.dart';
import 'package:client/view_models/system/admin_division_management_view_model.dart';
import 'package:client/view_models/system/campus_management_view_model.dart';
import 'package:client/view_models/system/department_management_view_model.dart';
import 'package:client/view_models/system/dict_management_view_model.dart';
import 'package:client/view_models/system/high_risk_factor_exclusion_management_view_model.dart';
import 'package:client/view_models/system/high_risk_factor_management_view_model.dart';
import 'package:client/view_models/system/holiday_management_view_model.dart';
import 'package:client/view_models/system/hospital_management_view_model.dart';
import 'package:client/view_models/system/menu_management_view_model.dart';
import 'package:client/view_models/system/role_management_view_model.dart';
import 'package:client/view_models/system/user_management_view_model.dart';
import 'package:client/views/login/login_page.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';

///当前登录用户token
late String? token;

///当前会话API加密密钥（随登录下发，与token同生命周期）
late String? sessionKey;

///当前登录用户（登录成功后由 LoginViewModel 写入，注销时清空）
late LoginUser? loginUser;

///注册服务
final getIt = GetIt.instance;

///全局导航 Key（打印等需要在 Overlay 挂载屏外内容的场景取根上下文）
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void setupServiceLocator() {
  getIt.registerLazySingleton<BaseService>(() => BaseService());
  getIt.registerLazySingleton<AuthService>(() => AuthService());
  getIt.registerLazySingleton<TimeService>(() => TimeService());
  getIt.registerLazySingleton<AccountService>(() => AccountService());
  getIt.registerLazySingleton<LogService>(() => LogService());
  getIt.registerLazySingleton<AdminDivisionsService>(() => AdminDivisionsService());
  getIt.registerLazySingleton<HospitalService>(() => HospitalService());
  getIt.registerLazySingleton<CampusService>(() => CampusService());
  getIt.registerLazySingleton<DepartmentService>(() => DepartmentService());
  getIt.registerLazySingleton<DictService>(() => DictService());
  getIt.registerLazySingleton<HighRiskFactorService>(() => HighRiskFactorService());
  getIt.registerLazySingleton<HighRiskFactorExclusionService>(() => HighRiskFactorExclusionService());
  getIt.registerLazySingleton<HolidayService>(() => HolidayService());
  getIt.registerLazySingleton<ChildService>(() => ChildService());
  getIt.registerLazySingleton<InitialScreeningService>(() => InitialScreeningService());
  getIt.registerLazySingleton<MenuService>(() => MenuService());
  getIt.registerLazySingleton<RoleService>(() => RoleService());
  getIt.registerLazySingleton<UserService>(() => UserService());
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  //初始化全局会话变量（late 变量在赋值前读取会抛错，登录失败等场景
  //LogHelper/BaseService 会先于赋值读取）
  token = null;
  sessionKey = null;
  loginUser = null;

  //全局异常兜底：框架构建/渲染异常与未处理异常上报操作日志（上报自身
  //静默失败，见 LogHelper；原控制台输出保留）
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    LogHelper.error('client:FlutterError', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    LogHelper.error('client:Unhandled', error, stackTrace);
    return true;
  };

  //注册服务
  setupServiceLocator();

  //读取配置文件
  await getIt<AuthService>().loadConfig();
  await getIt<BaseService>().loadConfig();
  await getIt<TimeService>().loadConfig();

  //启动全局时间服务（立即向服务端校准一次并周期重校准；失败静默回退
  //本地时钟，业务侧采集时间统一走 TimeService.now，见 time_service.dart）
  getIt<TimeService>().startAutoSync();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(create: (context) => FontProvider()),
        ChangeNotifierProvider(create: (context) => LoginViewModel()),
        ChangeNotifierProvider(create: (context) => MainViewModel()),
        ChangeNotifierProvider(create: (context) => HomeViewModel()),
        ChangeNotifierProvider(create: (context) => HospitalManagementViewModel()),
        ChangeNotifierProvider(create: (context) => CampusManagementViewModel()),
        ChangeNotifierProvider(create: (context) => DepartmentManagementViewModel()),
        ChangeNotifierProvider(create: (context) => DictManagementViewModel()),
        ChangeNotifierProvider(create: (context) => HighRiskFactorManagementViewModel()),
        ChangeNotifierProvider(create: (context) => HighRiskFactorExclusionManagementViewModel()),
        ChangeNotifierProvider(create: (context) => HolidayManagementViewModel()),
        ChangeNotifierProvider(create: (context) => MenuManagementViewModel()),
        ChangeNotifierProvider(create: (context) => RoleManagementViewModel()),
        ChangeNotifierProvider(create: (context) => UserManagementViewModel()),
        ChangeNotifierProvider(create: (context) => AdminDivisionManagementViewModel()),
        ChangeNotifierProvider(create: (context) => ChildCreateViewModel()),
        ChangeNotifierProvider(create: (context) => InitialScreeningViewModel()),
        ChangeNotifierProvider(create: (context) => PhotoManagementViewModel()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    //获取字体缩放比例
    final fontScale = context.watch<FontProvider>().fontScale;

    //获取当前主题
    ThemeData baseTheme = context.watch<ThemeProvider>().currentTheme;

    //动态调整字体大小
    final textTheme = baseTheme.textTheme.copyWith(
      displayLarge: baseTheme.textTheme.displayLarge?.copyWith(
        fontSize: (baseTheme.textTheme.displayLarge?.fontSize ?? 57) * fontScale,
      ),
      displayMedium: baseTheme.textTheme.displayMedium?.copyWith(
        fontSize: (baseTheme.textTheme.displayMedium?.fontSize ?? 45) * fontScale,
      ),
      displaySmall: baseTheme.textTheme.displaySmall?.copyWith(
        fontSize: (baseTheme.textTheme.displaySmall?.fontSize ?? 36) * fontScale,
      ),
      headlineLarge: baseTheme.textTheme.headlineLarge?.copyWith(
        fontSize: (baseTheme.textTheme.headlineLarge?.fontSize ?? 32) * fontScale,
      ),
      headlineMedium: baseTheme.textTheme.headlineMedium?.copyWith(
        fontSize: (baseTheme.textTheme.headlineMedium?.fontSize ?? 28) * fontScale,
      ),
      headlineSmall: baseTheme.textTheme.headlineSmall?.copyWith(
        fontSize: (baseTheme.textTheme.headlineSmall?.fontSize ?? 24) * fontScale,
      ),
      titleLarge: baseTheme.textTheme.titleLarge?.copyWith(
        fontSize: (baseTheme.textTheme.titleLarge?.fontSize ?? 22) * fontScale,
      ),
      titleMedium: baseTheme.textTheme.titleMedium?.copyWith(
        fontSize: (baseTheme.textTheme.titleMedium?.fontSize ?? 18) * fontScale,
      ),
      titleSmall: baseTheme.textTheme.titleSmall?.copyWith(
        fontSize: (baseTheme.textTheme.titleSmall?.fontSize ?? 14) * fontScale,
      ),
      bodyLarge: baseTheme.textTheme.bodyLarge?.copyWith(
        fontSize: (baseTheme.textTheme.bodyLarge?.fontSize ?? 16) * fontScale,
      ),
      bodyMedium: baseTheme.textTheme.bodyMedium?.copyWith(
        fontSize: (baseTheme.textTheme.bodyMedium?.fontSize ?? 14) * fontScale,
      ),
      bodySmall: baseTheme.textTheme.bodySmall?.copyWith(
        fontSize: (baseTheme.textTheme.bodySmall?.fontSize ?? 12) * fontScale,
      ),
      labelLarge: baseTheme.textTheme.labelLarge?.copyWith(
        fontSize: (baseTheme.textTheme.labelLarge?.fontSize ?? 14) * fontScale,
      ),
      labelMedium: baseTheme.textTheme.labelMedium?.copyWith(
        fontSize: (baseTheme.textTheme.labelMedium?.fontSize ?? 12) * fontScale,
      ),
      labelSmall: baseTheme.textTheme.labelSmall?.copyWith(
        fontSize: (baseTheme.textTheme.labelSmall?.fontSize ?? 11) * fontScale,
      ),
    );

    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          // 全局中文本地化：日期选择器等 Material 组件按中文显示
          // （2026年11月、取消/确定等），系统界面语言固定中文；
          // delegates 为 material_ui 重导出的 Material+Widgets+Cupertino
          // 三件套
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('zh', 'CN')],
          locale: const Locale('zh', 'CN'),
          builder: (context, child) => ResponsiveBreakpoints.builder(
            child: child!,
            breakpoints: const [
              Breakpoint(start: 0, end: 450, name: MOBILE),
              Breakpoint(start: 451, end: 800, name: TABLET),
              Breakpoint(start: 801, end: double.infinity, name: DESKTOP),
            ],
          ),
          debugShowCheckedModeBanner: false, //隐藏右上角DEBUG标识
          title: 'AiCMHCS智慧儿童孤独症管理系统',
          theme: baseTheme.copyWith(
            textTheme: textTheme,
            filledButtonTheme: FilledButtonThemeData(
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll<TextStyle>(
                  TextStyle(
                    fontSize: (baseTheme.textTheme.bodyMedium?.fontSize ?? 14) * fontScale,
                  ),
                ),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll<TextStyle>(
                  TextStyle(
                    fontSize: (baseTheme.textTheme.bodyMedium?.fontSize ?? 14) * fontScale,
                  ),
                ),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll<TextStyle>(
                  TextStyle(
                    fontSize: (baseTheme.textTheme.bodyMedium?.fontSize ?? 14) * fontScale,
                  ),
                ),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll<TextStyle>(
                  TextStyle(
                    fontSize: (baseTheme.textTheme.bodyMedium?.fontSize ?? 14) * fontScale,
                  ),
                ),
              ),
            ),
          ),
          darkTheme: baseTheme.copyWith(
            textTheme: textTheme,
            filledButtonTheme: FilledButtonThemeData(
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll<TextStyle>(
                  TextStyle(
                    fontSize: (baseTheme.textTheme.bodyMedium?.fontSize ?? 14) * fontScale,
                  ),
                ),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll<TextStyle>(
                  TextStyle(
                    fontSize: (baseTheme.textTheme.bodyMedium?.fontSize ?? 14) * fontScale,
                  ),
                ),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll<TextStyle>(
                  TextStyle(
                    fontSize: (baseTheme.textTheme.bodyMedium?.fontSize ?? 14) * fontScale,
                  ),
                ),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll<TextStyle>(
                  TextStyle(
                    fontSize: (baseTheme.textTheme.bodyMedium?.fontSize ?? 14) * fontScale,
                  ),
                ),
              ),
            ),
          ),
          themeMode: ThemeMode.system,
          home: const LoginPage(),
        );
      },
    );
  }
}
