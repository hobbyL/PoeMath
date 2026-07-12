// lib/core/theme/math_theme.dart
//
// 层级：core/theme
// 职责：构建口算童趣马卡龙主题 ThemeData（light / dark），并通过
// `MathThemeExt` 暴露口算大数字等专属样式。
// 依赖：ColorTokens / TypographyTokens。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/color_tokens.dart';
import 'package:poemath/core/theme/typography_tokens.dart';

/// 口算马卡龙童趣主题构建器。
class MathTheme {
  const MathTheme._();

  /// 亮色主题：温白底 + 薰衣草紫主色 + 奶油黄/樱花粉次级色。
  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: ColorTokens.mathPurple,
        onPrimary: Colors.white,
        secondary: ColorTokens.mathYellow,
        onSecondary: ColorTokens.mathTextDark,
        tertiary: ColorTokens.mathPink,
        surface: ColorTokens.mathSurface,
        onSurface: ColorTokens.mathTextDark,
        error: ColorTokens.mathCoral,
      ),
      scaffoldBackgroundColor: ColorTokens.mathBackground,
      textTheme: _textTheme(ColorTokens.mathTextDark),
      appBarTheme: const AppBarTheme(
        backgroundColor: ColorTokens.mathBackground,
        foregroundColor: ColorTokens.mathTextDark,
        elevation: 0,
        centerTitle: true,
      ),
      extensions: const <ThemeExtension<dynamic>>[MathThemeExt()],
    );
  }

  /// 暗色主题（占位）：深色底 + 薰衣草紫。
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: ColorTokens.mathPurple,
        onPrimary: Colors.white,
        secondary: ColorTokens.mathYellow,
        tertiary: ColorTokens.mathPink,
        surface: ColorTokens.darkSurface,
        onSurface: ColorTokens.darkTextPrimary,
        error: ColorTokens.mathCoral,
      ),
      scaffoldBackgroundColor: ColorTokens.darkBackground,
      textTheme: _textTheme(ColorTokens.darkTextPrimary),
      appBarTheme: const AppBarTheme(
        backgroundColor: ColorTokens.darkBackground,
        foregroundColor: ColorTokens.darkTextPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      extensions: const <ThemeExtension<dynamic>>[MathThemeExt()],
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
