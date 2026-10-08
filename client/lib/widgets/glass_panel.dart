import 'dart:ui';

import 'package:material_ui/material_ui.dart';

class GlassPanel extends StatelessWidget {
  final Widget child;

  /// 模糊强度（sigmaX = sigmaY）
  final double blur;

  /// 面板底色；传 null 时默认取 [ColorScheme.surface] 的 90% 透明度
  final Color? color;

  /// 圆角，默认 16
  final double borderRadius;

  /// 描边颜色；传 null 时默认取 outlineVariant 的 30% 透明度
  final Color? borderColor;

  /// 描边宽度
  final double borderWidth;

  const GlassPanel({
    super.key,
    required this.child,
    this.blur = 20,
    this.color,
    this.borderRadius = 16,
    this.borderColor,
    this.borderWidth = 0.5,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(borderRadius);
    final effectiveColor = color ?? theme.colorScheme.surface.withValues(alpha: 0.9);
    final effectiveBorder = borderColor ?? theme.colorScheme.outlineVariant.withValues(alpha: 0.3);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: effectiveColor,
            borderRadius: radius,
            border: Border.all(color: effectiveBorder, width: borderWidth),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: child,
          ),
        ),
      ),
    );
  }
}
