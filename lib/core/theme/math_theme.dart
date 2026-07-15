// lib/core/theme/math_theme.dart
//
// 层级：core/theme
// 职责：构建口算童趣马卡龙主题 ThemeData（light / dark），并通过
// `MathThemeExt` 暴露口算大数字等专属样式。
// 依赖：ColorTokens / TypographyTokens。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/color_tokens.dart';
import 'package:poemath/core/theme/semantic_colors_ext.dart';
import 'package:poemath/core/theme/typography_tokens.dart';

/// 口算马卡龙童趣主题构建器。
class MathTheme {
  const MathTheme._();

  /// 亮色主题：温白底 + 薰衣草紫主色 + 奶油黄/樱花粉次级色。
  static ThemeData light() {
    const primary = ColorTokens.mathPurple;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      secondary: ColorTokens.mathYellow,
      onSecondary: ColorTokens.mathTextDark,
      secondaryContainer: primary.withValues(alpha: 0.15),
      onSecondaryContainer: primary,
      tertiary: ColorTokens.mathPink,
      surface: ColorTokens.mathSurface,
      onSurface: ColorTokens.mathTextDark,
      error: ColorTokens.mathCoral,
    );
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: ColorTokens.mathBackground,
      textTheme: _textTheme(ColorTokens.mathTextDark),
      appBarTheme: const AppBarTheme(
        backgroundColor: ColorTokens.mathBackground,
        foregroundColor: ColorTokens.mathTextDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      chipTheme: _chipTheme(primary),
      extensions: const <ThemeExtension<dynamic>>[
        MathThemeExt(),
        SemanticColorsExt(
          success: ColorTokens.mathMint,
          caution: ColorTokens.mathYellow,
        ),
      ],
    );
  }

  /// 暗色主题（占位）：深色底 + 薰衣草紫。
  static ThemeData dark() {
    const primary = ColorTokens.mathPurple;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      primary: primary,
      onPrimary: Colors.white,
      secondary: ColorTokens.mathYellow,
      secondaryContainer: primary.withValues(alpha: 0.25),
      onSecondaryContainer: primary,
      tertiary: ColorTokens.mathPink,
      surface: ColorTokens.darkSurface,
      onSurface: ColorTokens.darkTextPrimary,
      error: ColorTokens.mathCoral,
    );
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: ColorTokens.darkBackground,
      textTheme: _textTheme(ColorTokens.darkTextPrimary),
      appBarTheme: const AppBarTheme(
        backgroundColor: ColorTokens.darkBackground,
        foregroundColor: ColorTokens.darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      chipTheme: _chipTheme(primary),
      extensions: const <ThemeExtension<dynamic>>[
        MathThemeExt(),
        SemanticColorsExt(
          success: ColorTokens.mathMint,
          caution: ColorTokens.mathYellow,
        ),
      ],
    );
  }

  /// ChoiceChip / FilterChip 选中态跟随 primary。
  static ChipThemeData _chipTheme(Color primary) {
    return ChipThemeData(
      selectedColor: primary.withValues(alpha: 0.15),
      checkmarkColor: primary,
      secondarySelectedColor: primary.withValues(alpha: 0.15),
      showCheckmark: true,
    );
  }

  static TextTheme _textTheme(Color color) => TextTheme(
        displayLarge: TextStyle(
          fontFamily: TypographyTokens.mathFontFamily,
          fontSize: TypographyTokens.fsDisplay,
          fontWeight: FontWeight.w800,
          color: color,
        ),
        displayMedium: TextStyle(
          fontFamily: TypographyTokens.mathFontFamily,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: color,
        ),
        displaySmall: TextStyle(
          fontFamily: TypographyTokens.mathFontFamily,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: color,
        ),
        headlineLarge: TextStyle(
          fontFamily: TypographyTokens.mathFontFamily,
          fontSize: TypographyTokens.fsHeadline,
          fontWeight: FontWeight.w700,
          color: color,
        ),
        headlineMedium: TextStyle(
          fontFamily: TypographyTokens.mathFontFamily,
          fontSize: TypographyTokens.fsHeadline,
          fontWeight: FontWeight.w700,
          color: color,
        ),
        headlineSmall: TextStyle(
          fontFamily: TypographyTokens.mathFontFamily,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        titleLarge: TextStyle(
          fontFamily: TypographyTokens.mathFontFamily,
          fontSize: TypographyTokens.fsTitle,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        titleMedium: TextStyle(
          fontFamily: TypographyTokens.mathFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        titleSmall: TextStyle(
          fontFamily: TypographyTokens.mathFontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: color,
        ),
        bodyLarge: TextStyle(
          fontFamily: TypographyTokens.mathFontFamily,
          fontSize: TypographyTokens.fsBody,
          height: 1.5,
          color: color,
        ),
        bodyMedium: TextStyle(
          fontFamily: TypographyTokens.mathFontFamily,
          fontSize: TypographyTokens.fsBody,
          color: color,
        ),
        bodySmall: TextStyle(
          fontFamily: TypographyTokens.mathFontFamily,
          fontSize: TypographyTokens.fsCaption,
          color: color,
        ),
        labelLarge: TextStyle(
          fontFamily: TypographyTokens.mathFontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: color,
        ),
        labelMedium: TextStyle(
          fontFamily: TypographyTokens.mathFontFamily,
          fontSize: TypographyTokens.fsLabel,
          color: color,
        ),
        labelSmall: TextStyle(
          fontFamily: TypographyTokens.mathFontFamily,
          fontSize: 11,
          color: color,
        ),
      );
}

/// 挂在 ThemeData 上的口算专属样式扩展。
///
/// 使用：`Theme.of(context).extension<MathThemeExt>()!.problemNumber`
class MathThemeExt extends ThemeExtension<MathThemeExt> {
  const MathThemeExt();

  TextStyle get problemNumber => TypographyTokens.mathProblemStyle();

  @override
  MathThemeExt copyWith() => const MathThemeExt();

  @override
  MathThemeExt lerp(ThemeExtension<MathThemeExt>? other, double t) => this;
}
