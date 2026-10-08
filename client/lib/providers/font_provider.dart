import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FontProvider extends ChangeNotifier {
  ///默认字体缩放比例
  double _fontScale = 1.0;

  ///获取当前字体缩放比例
  double get fontScale => _fontScale;

  FontProvider() {
    _loadFontScale();
  }

  ///获取保存的字体缩放比例
  Future<void> _loadFontScale() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('font_scale')) {
      _fontScale = double.parse(prefs.getString('font_scale') ?? '1.0');
    } else {
      _fontScale = 1.0;
    }

    //通知UI更新
    notifyListeners();
  }

  ///设置字体缩放比例
  Future<void> setFontScale(double scale) async {
    if (scale != _fontScale) {
      _fontScale = scale;

      //保存主题
      final prefs = await SharedPreferences.getInstance();
      prefs.setString('font_scale', _fontScale.toString());

      //通知UI更新
      notifyListeners();
    }
  }
}
