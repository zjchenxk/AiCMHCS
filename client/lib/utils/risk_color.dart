import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 高危五色语义色板（医学色标固定颜色，不随主题切换）。
///
/// BASE_HIGH_RISK_FACTOR.RISK_COLOR 存中文五色，界面按颜色分组并以
/// 对应色系的浅色底 + 描边区分；未设置颜色归入中性灰（跟随主题
/// outline 色）。与右侧儿童信息侧边栏的五色分级同款色标。
class RiskColorPalette {
  RiskColorPalette._();

  /// 合法颜色名称（顺序即界面分组顺序；与后端共享常量）。
  static const List<String> names = BaseHighRiskFactor.riskColors;

  /// 未设置颜色分组的展示名称。
  static const String unsetLabel = '未设置颜色';

  /// 颜色名称对应的语义色；未设置/非法取值回退主题中性色。
  static Color colorOf(String? name, ThemeData theme) => switch (name) {
    '绿色' => Colors.green.shade700,
    '黄色' => Colors.yellow.shade800,
    '橙色' => Colors.orange.shade800,
    '红色' => Colors.red.shade700,
    '紫色' => Colors.purple.shade700,
    _ => theme.colorScheme.outline,
  };

  /// 分组背景色（语义色的浅色底）。
  static Color backgroundOf(String? name, ThemeData theme) => colorOf(name, theme).withValues(alpha: 0.10);

  /// 分组描边色。
  static Color borderOf(String? name, ThemeData theme) => colorOf(name, theme).withValues(alpha: 0.30);
}
