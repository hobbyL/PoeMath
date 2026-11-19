import 'package:flutter/material.dart';

import 'package:poemath/core/theme/color_tokens.dart';
import 'package:poemath/core/theme/ink_theme.dart';
import 'package:poemath/core/theme/poem_theme.dart';
import 'package:poemath/core/theme/typography_tokens.dart';

/// 宣纸·赭石；沿用 math 偏好值，已有选择无需迁移。
class MathTheme {
  const MathTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final theme = InkTheme.build(brightness: brightness, ochre: true);
    return theme.copyWith(
      extensions: [
        ...theme.extensions.values,
        MathThemeExt(contentColor: theme.colorScheme.onSurface),
        PoemThemeExt(
          contentColor: theme.colorScheme.onSurface,
          pinyinColor: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

/// 口算大数字随明暗模式使用可读的墨色。
class MathThemeExt extends ThemeExtension<MathThemeExt> {
  const MathThemeExt({this.contentColor = ColorTokens.poemInk});

  final Color contentColor;
  TextStyle get problemNumber =>
      TypographyTokens.mathProblemStyle(color: contentColor);

  @override
  MathThemeExt copyWith({Color? contentColor}) =>
      MathThemeExt(contentColor: contentColor ?? this.contentColor);

  @override
  MathThemeExt lerp(ThemeExtension<MathThemeExt>? other, double t) {
    if (other is! MathThemeExt) return this;
    return MathThemeExt(
      contentColor: Color.lerp(contentColor, other.contentColor, t)!,
    );
  }
}
