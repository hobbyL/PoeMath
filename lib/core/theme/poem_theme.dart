// lib/core/theme/poem_theme.dart
//
// 层级：core/theme
// 职责：构建诗词国风水墨主题 ThemeData（light / dark），并通过
// `PoemThemeExt` 暴露诗句正文、拼音等专属样式。
// 依赖：ColorTokens / TypographyTokens。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/color_tokens.dart';
import 'package:poemath/core/theme/semantic_colors_ext.dart';
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
      secondaryContainer: primary.withValues(alpha: 0.15),
      onSecondaryContainer: primary,
      surface: ColorTokens.poemPaper,
      onSurface: ColorTokens.poemInk,
      error: ColorTokens.poemSeal,
      onError: Colors.white,
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
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      chipTheme: _chipTheme(primary),
      extensions: <ThemeExtension<dynamic>>[
        PoemThemeExt(
          contentColor: scheme.onSurface,
          pinyinColor: scheme.onSurfaceVariant,
        ),
        const SemanticColorsExt(
          success: ColorTokens.successText,
          caution: ColorTokens.cautionText,
          secondaryForeground: ColorTokens.poemSeal,
        ),
      ],
    );
  }

  /// 暗色主题：深色底 + 明亮墨绿前景。
  static ThemeData dark() {
    const primary = ColorTokens.poemGreenLight;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      primary: primary,
      onPrimary: ColorTokens.poemGreenDeep,
      secondary: ColorTokens.poemCinnabarLight,
      onSecondary: ColorTokens.poemInk,
      secondaryContainer: primary.withValues(alpha: 0.25),
      onSecondaryContainer: primary,
      surface: ColorTokens.darkSurface,
      onSurface: ColorTokens.darkTextPrimary,
      error: ColorTokens.mathCoral,
      onError: ColorTokens.poemInk,
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
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      chipTheme: _chipTheme(primary),
      extensions: <ThemeExtension<dynamic>>[
        PoemThemeExt(
          contentColor: scheme.onSurface,
          pinyinColor: scheme.onSurfaceVariant,
        ),
        const SemanticColorsExt(
          success: ColorTokens.mathMint,
          caution: ColorTokens.poemGold,
          secondaryForeground: ColorTokens.poemCinnabarLight,
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

  /// 使用系统默认字体；字号与字重区分层级。
  static TextTheme _textTheme(Color color) => TextTheme(
    displayLarge: TextStyle(
      fontSize: TypographyTokens.fsDisplay,
      fontWeight: FontWeight.w700,
      color: color,
    ),
    displayMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      color: color,
    ),
    displaySmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: color,
    ),
    headlineLarge: TextStyle(
      fontSize: TypographyTokens.fsHeadline,
      fontWeight: FontWeight.w600,
      color: color,
    ),
    headlineMedium: TextStyle(
      fontSize: TypographyTokens.fsHeadline,
      color: color,
    ),
    headlineSmall: TextStyle(fontSize: 22, color: color),
    titleLarge: TextStyle(fontSize: TypographyTokens.fsTitle, color: color),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: color,
    ),
    titleSmall: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: color,
    ),
    bodyLarge: TextStyle(
      fontSize: TypographyTokens.fsBody,
      height: 1.5,
      color: color,
    ),
    bodyMedium: TextStyle(fontSize: TypographyTokens.fsBody, color: color),
    bodySmall: TextStyle(fontSize: TypographyTokens.fsCaption, color: color),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: color,
    ),
    labelMedium: TextStyle(fontSize: TypographyTokens.fsLabel, color: color),
    labelSmall: TextStyle(fontSize: 11, color: color),
  );
}

/// 挂在 ThemeData 上的诗词专属样式扩展。
///
/// 使用：`Theme.of(context).extension<PoemThemeExt>()!.poemContent`
class PoemThemeExt extends ThemeExtension<PoemThemeExt> {
  const PoemThemeExt({
    this.contentColor = ColorTokens.poemInk,
    this.pinyinColor = ColorTokens.poemInkLight,
  });

  final Color contentColor;
  final Color pinyinColor;

  TextStyle get poemContent =>
      TypographyTokens.poemContentStyle(color: contentColor);

  TextStyle get pinyin =>
      TextStyle(fontSize: TypographyTokens.fsPinyin, color: pinyinColor);

  @override
  PoemThemeExt copyWith({Color? contentColor, Color? pinyinColor}) =>
      PoemThemeExt(
        contentColor: contentColor ?? this.contentColor,
        pinyinColor: pinyinColor ?? this.pinyinColor,
      );

  @override
  PoemThemeExt lerp(ThemeExtension<PoemThemeExt>? other, double t) {
    if (other is! PoemThemeExt) return this;
    return PoemThemeExt(
      contentColor: Color.lerp(contentColor, other.contentColor, t)!,
      pinyinColor: Color.lerp(pinyinColor, other.pinyinColor, t)!,
    );
  }
}
