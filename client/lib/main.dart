import 'package:client/providers/font_provider.dart';
import 'package:client/providers/theme_provider.dart';
import 'package:client/services/admin_divisions_service.dart';
import 'package:client/services/log_service.dart';
import 'package:client/view_models/home/home_view_model.dart';
import 'package:client/view_models/main/main_view_model.dart';
import 'package:client/view_models/login/login_view_model.dart';
import 'package:client/view_models/system/hospital_management_view_model.dart';
import 'package:client/views/login/login_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';

///当前登录用户token
late String? token;

///注册服务
final getIt = GetIt.instance;

void setupServiceLocator() {
  getIt.registerLazySingleton<LogService>(() => LogService());
  getIt.registerLazySingleton<AdminDivisionsService>(() => AdminDivisionsService());
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  //注册服务
  setupServiceLocator();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(create: (context) => FontProvider()),
        ChangeNotifierProvider(create: (context) => LoginViewModel()),
        ChangeNotifierProvider(create: (context) => MainViewModel()),
        ChangeNotifierProvider(create: (context) => HomeViewModel()),
        ChangeNotifierProvider(create: (context) => HospitalManagementViewModel()),
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
          builder: (context, child) => ResponsiveBreakpoints.builder(
            child: child!,
            breakpoints: const [
              Breakpoint(start: 0, end: 450, name: MOBILE),
              Breakpoint(start: 451, end: 800, name: TABLET),
              Breakpoint(start: 801, end: double.infinity, name: DESKTOP),
            ],
          ),
          debugShowCheckedModeBanner: false, //隐藏右上角DEBUG标识
          title: 'AiCMHCS智慧儿童心理保健系统',
          theme: baseTheme.copyWith(
            textTheme: textTheme,
            filledButtonTheme: FilledButtonThemeData(
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll<TextStyle>(
                  TextStyle(
                    fontSize: (baseTheme.textTheme.bodyLarge?.fontSize ?? 16) * fontScale,
                  ),
                ),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll<TextStyle>(
                  TextStyle(
                    fontSize: (baseTheme.textTheme.bodyLarge?.fontSize ?? 16) * fontScale,
                  ),
                ),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll<TextStyle>(
                  TextStyle(
                    fontSize: (baseTheme.textTheme.bodyLarge?.fontSize ?? 16) * fontScale,
                  ),
                ),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll<TextStyle>(
                  TextStyle(
                    fontSize: (baseTheme.textTheme.bodyLarge?.fontSize ?? 16) * fontScale,
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
                    fontSize: (baseTheme.textTheme.bodyLarge?.fontSize ?? 16) * fontScale,
                  ),
                ),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll<TextStyle>(
                  TextStyle(
                    fontSize: (baseTheme.textTheme.bodyLarge?.fontSize ?? 16) * fontScale,
                  ),
                ),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll<TextStyle>(
                  TextStyle(
                    fontSize: (baseTheme.textTheme.bodyLarge?.fontSize ?? 16) * fontScale,
                  ),
                ),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll<TextStyle>(
                  TextStyle(
                    fontSize: (baseTheme.textTheme.bodyLarge?.fontSize ?? 16) * fontScale,
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
