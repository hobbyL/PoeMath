// lib/core/theme/poem_theme.dart
//
// 层级：core/theme
// 职责：构建诗词国风水墨主题 ThemeData（light / dark），并通过
// `PoemThemeExt` 暴露诗句正文、拼音等专属样式。
// 依赖：ColorTokens / TypographyTokens。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/color_tokens.dart';
import 'package:poemath/core/theme/typography_tokens.dart';

/// 诗词国风主题构建器。
class PoemTheme {
  const PoemTheme._();

  /// 亮色主题：宣纸底 + 墨绿主色 + 朱砂点缀。
  static ThemeData light() {
    const primary = ColorTokens.poemGreen;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      secondary: ColorTokens.poemCinnabar,
      onSecondary: Colors.white,
      surface: ColorTokens.poemPaper,
      onSurface: ColorTokens.poemInk,
      error: ColorTokens.error,
    );
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: ColorTokens.poemPaper,
      dividerColor: ColorTokens.poemDivider,
      textTheme: _textTheme(ColorTokens.poemInk),
      appBarTheme: const AppBarTheme(
        backgroundColor: ColorTokens.poemPaper,
        foregroundColor: ColorTokens.poemInk,
        elevation: 0,
        centerTitle: true,
      ),
      chipTheme: _chipTheme(primary),
      extensions: const <ThemeExtension<dynamic>>[PoemThemeExt()],
    );
  }

  /// 暗色主题：深色底 + 墨绿主色（护眼模式）。
  static ThemeData dark() {
    const primary = ColorTokens.poemGreen;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      primary: primary,
      onPrimary: Colors.white,
      secondary: ColorTokens.poemCinnabar,
      surface: ColorTokens.darkSurface,
      onSurface: ColorTokens.darkTextPrimary,
      error: ColorTokens.error,
    );
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: ColorTokens.darkBackground,
      dividerColor: ColorTokens.poemDivider,
      textTheme: _textTheme(ColorTokens.darkTextPrimary),
      appBarTheme: const AppBarTheme(
        backgroundColor: ColorTokens.darkBackground,
        foregroundColor: ColorTokens.darkTextPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      chipTheme: _chipTheme(primary),
      extensions: const <ThemeExtension<dynamic>>[PoemThemeExt()],
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
          fontFamily: TypographyTokens.poemFontFamily,
          fontSize: TypographyTokens.fsDisplay,
          fontWeight: FontWeight.w700,
          color: color,
        ),
        displayMedium: TextStyle(
          fontFamily: TypographyTokens.poemFontFamily,
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        displaySmall: TextStyle(
          fontFamily: TypographyTokens.poemFontFamily,
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        headlineLarge: TextStyle(
          fontFamily: TypographyTokens.poemFontFamily,
          fontSize: TypographyTokens.fsHeadline,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        headlineMedium: TextStyle(
          fontFamily: TypographyTokens.poemFontFamily,
          fontSize: TypographyTokens.fsHeadline,
          color: color,
        ),
        headlineSmall: TextStyle(
          fontFamily: TypographyTokens.poemFontFamily,
          fontSize: 22,
          color: color,
        ),
        titleLarge: TextStyle(
          fontFamily: TypographyTokens.poemFontFamily,
          fontSize: TypographyTokens.fsTitle,
          color: color,
        ),
        titleMedium: TextStyle(
          fontFamily: TypographyTokens.uiFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: color,
        ),
        titleSmall: TextStyle(
          fontFamily: TypographyTokens.uiFontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: color,
        ),
        bodyLarge: TextStyle(
          fontFamily: TypographyTokens.uiFontFamily,
          fontSize: TypographyTokens.fsBody,
          height: 1.5,
          color: color,
        ),
        bodyMedium: TextStyle(
          fontFamily: TypographyTokens.uiFontFamily,
          fontSize: TypographyTokens.fsBody,
          color: color,
        ),
        bodySmall: TextStyle(
          fontFamily: TypographyTokens.uiFontFamily,
          fontSize: TypographyTokens.fsCaption,
          color: color,
        ),
        labelLarge: TextStyle(
          fontFamily: TypographyTokens.uiFontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: color,
        ),
        labelMedium: TextStyle(
          fontFamily: TypographyTokens.uiFontFamily,
          fontSize: TypographyTokens.fsLabel,
          color: color,
        ),
        labelSmall: TextStyle(
          fontFamily: TypographyTokens.uiFontFamily,
          fontSize: 11,
          color: color,
        ),
      );
}

/// 挂在 ThemeData 上的诗词专属样式扩展。
///
/// 使用：`Theme.of(context).extension<PoemThemeExt>()!.poemContent`
class PoemThemeExt extends ThemeExtension<PoemThemeExt> {
  const PoemThemeExt();

  TextStyle get poemContent => TypographyTokens.poemContentStyle();

  TextStyle get pinyin => const TextStyle(
        fontFamily: TypographyTokens.uiFontFamily,
        fontSize: TypographyTokens.fsPinyin,
        color: ColorTokens.poemInkLight,
      );

  @override
  PoemThemeExt copyWith() => const PoemThemeExt();

  @override
  PoemThemeExt lerp(ThemeExtension<PoemThemeExt>? other, double t) => this;
}
