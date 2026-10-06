import 'package:aicmhcs_client/utils/theme_data_util.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  ///当前主题名称
  String _currentThemeName = 'Teal';

  ///获取当前主题名称
  String get currentThemeName => _currentThemeName;

  ///获取当前主题
  ThemeData get currentTheme => AppThemes.themes[_currentThemeName]!;

  ///获取所有主题名称
  List<String> get themeNames => AppThemes.themes.keys.toList();

  ThemeProvider() {
    _loadTheme();
  }

  ///加载保存的主题
  Future<void> _loadTheme() async {
    //获取保存的主题名称
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('current_theme')) {
      _currentThemeName = prefs.getString('current_theme') ?? 'Teal';
    } else {
      _currentThemeName = 'Teal';
    }

    //通知UI更新
    notifyListeners();
  }

  ///切换主题
  ///@param themeName 主题名称
  Future<void> switchTheme(String themeName) async {
    if (AppThemes.themes.containsKey(themeName)) {
      //切换主题
      _currentThemeName = themeName;

      //保存主题
      final prefs = await SharedPreferences.getInstance();
      prefs.setString('current_theme', themeName);

      //通知UI更新
      notifyListeners();
    }
  }
}
