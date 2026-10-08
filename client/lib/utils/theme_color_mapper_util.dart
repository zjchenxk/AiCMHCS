import 'dart:ui';

import 'package:flutter_svg/flutter_svg.dart';

class ThemeColorMapper extends ColorMapper {
  const ThemeColorMapper({required this.primary});
  final Color primary;

  @override
  Color substitute(String? id, String elementName, String attributeName, Color color) {
    // 原 Teal 主色
    if (color == const Color(0xFF006a60)) {
      return primary;
    }
    // 原浅色装饰
    // if (color == const Color(0xFFB2DFDB)) {
    //   return primary.withValues(alpha: 0.3);
    // }
    return color; // 其余颜色保持原样（人物、文字等中性色不动）
  }
}
