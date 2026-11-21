import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/theme/app_theme_builder.dart';

/// 松墨素宣与赭石浅绢：独立完整色板，共用排版与组件交互。
/// 学科页面沿用用户的配色选择，切换 Tab 不会改变主题。
class InkTheme {
  const InkTheme._();

  static ThemeData build({
    required Brightness brightness,
    required bool ochre,
  }) {
    final dark = brightness == Brightness.dark;
    final primary = ochre
        ? (dark ? ColorTokens.inkOchreLight : ColorTokens.inkOchre)
        : (dark ? ColorTokens.poemGreenLight : ColorTokens.poemGreen);
    final palette = _palette(ochre: ochre, dark: dark);
    final page = palette.page;
    final surface = palette.surface;
    final ink = palette.ink;
    final onAccent = dark ? page : surface;
    final secondary = ochre
        ? (dark ? ColorTokens.ochreSealLight : ColorTokens.ochreSeal)
        : (dark ? ColorTokens.poemCinnabarLight : ColorTokens.poemCinnabar);
    final tertiary = ochre
        ? (dark ? ColorTokens.ochreAccentLight : ColorTokens.ochreAccent)
        : (dark ? ColorTokens.pineAccentLight : ColorTokens.pineAccent);
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      onPrimary: onAccent,
      primaryContainer: Color.alphaBlend(
        primary.withValues(alpha: .14),
        surface,
      ),
      onPrimaryContainer: primary,
      secondary: secondary,
      onSecondary: onAccent,
      secondaryContainer: Color.alphaBlend(
        primary.withValues(alpha: dark ? .18 : .1),
        surface,
      ),
      onSecondaryContainer: primary,
      tertiary: tertiary,
      onTertiary: onAccent,
      tertiaryContainer: Color.alphaBlend(
        tertiary.withValues(alpha: .16),
        surface,
      ),
      onTertiaryContainer: tertiary,
      surface: surface,
      surfaceDim: dark ? page : palette.deep,
      surfaceBright: dark ? palette.raised : surface,
      surfaceContainerLowest: page,
      surfaceContainerLow: page,
      surfaceContainer: surface,
      surfaceContainerHigh: palette.raised,
      surfaceContainerHighest: palette.deep,
      onSurface: ink,
      onSurfaceVariant: palette.muted,
      outline: palette.muted,
      outlineVariant: palette.rule,
      error: dark ? ColorTokens.mathCoral : ColorTokens.ochreSeal,
      onError: onAccent,
    );
    return AppThemeBuilder.build(
      scheme: scheme,
      page: page,
      text: AppThemeBuilder.textTheme(
        ink,
        headingFontFamily: TypographyTokens.inkFontFamily,
        headingFallback: TypographyTokens.serifFallback,
        headingWeight: FontWeight.w500,
      ),
      appearance: AppAppearance(
        visualStyle: ochre ? AppVisualStyle.ink : AppVisualStyle.pine,
        cardStyle: ochre ? AppCardStyle.paper : AppCardStyle.sheet,
        cardRadius: ochre
            ? SpacingTokens.radiusCompact
            : SpacingTokens.radiusMedium,
        controlRadius: ochre
            ? SpacingTokens.radiusSmall
            : SpacingTokens.radiusCompact,
        heroImage: ochre
            ? 'assets/images/ochre_autumn_header.webp'
            : 'assets/images/ink_landscape_overlay.png',
        pageImage: ochre
            ? 'assets/images/ochre_autumn_page.webp'
            : 'assets/images/ink_landscape_overlay.png',
        adventureImage: ochre
            ? 'assets/images/ochre_autumn_header.webp'
            : 'assets/images/ink_landscape_overlay.png',
      ),
      semantic: SemanticColorsExt(
        success: dark
            ? ColorTokens.mathMint
            : (ochre ? ColorTokens.ochreSuccess : ColorTokens.successText),
        caution: dark
            ? ColorTokens.inkOchreLight
            : (ochre ? ColorTokens.ochreCaution : ColorTokens.cautionText),
        secondaryForeground: secondary,
      ),
    );
  }

  static ({
    Color page,
    Color surface,
    Color raised,
    Color deep,
    Color ink,
    Color muted,
    Color rule,
  })
  _palette({required bool ochre, required bool dark}) {
    if (ochre) {
      return (
        page: dark ? ColorTokens.ochreNight : ColorTokens.ochrePaper,
        surface: dark
            ? ColorTokens.ochreNightSurface
            : ColorTokens.ochreSurface,
        raised: dark ? ColorTokens.ochreNightRaised : ColorTokens.ochreRaised,
        deep: dark ? ColorTokens.ochreNightRaised : ColorTokens.ochrePaperDeep,
        ink: dark ? ColorTokens.ochreNightInk : ColorTokens.ochreInk,
        muted: dark ? ColorTokens.ochreNightMuted : ColorTokens.ochreMutedInk,
        rule: dark ? ColorTokens.ochreNightRule : ColorTokens.ochreRule,
      );
    }
    return (
      page: dark ? ColorTokens.pineNight : ColorTokens.pinePaper,
      surface: dark ? ColorTokens.pineNightSurface : ColorTokens.pineSurface,
      raised: dark ? ColorTokens.pineNightRaised : ColorTokens.pineRaised,
      deep: dark ? ColorTokens.pineNightRaised : ColorTokens.pinePaperDeep,
      ink: dark ? ColorTokens.pineNightInk : ColorTokens.pineInk,
      muted: dark ? ColorTokens.pineNightMuted : ColorTokens.pineMutedInk,
      rule: dark ? ColorTokens.pineNightRule : ColorTokens.pineRule,
    );
  }
}
