import 'package:flutter/material.dart';
import 'package:poemath/core/theme/app_theme_builder.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/theme/math_theme.dart';
import 'package:poemath/core/theme/poem_theme.dart';

/// 卡通预设共用交互组件，各自提供完整明暗色板与页头插画。
class PlayfulTheme {
  const PlayfulTheme._();

  static ThemeData build({
    required Brightness brightness,
    required bool space,
  }) {
    final dark = brightness == Brightness.dark;
    final palette = _palette(space: space, dark: dark);
    final primary = palette.primary;
    final surface = palette.surface;
    final onAccent = dark ? palette.page : surface;
    Color tint(Color color, double alpha) =>
        Color.alphaBlend(color.withValues(alpha: alpha), surface);
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      onPrimary: onAccent,
      primaryContainer: tint(primary, .12),
      onPrimaryContainer: primary,
      secondary: palette.secondary,
      onSecondary: onAccent,
      secondaryContainer: tint(primary, .12),
      onSecondaryContainer: primary,
      tertiary: palette.tertiary,
      onTertiary: onAccent,
      tertiaryContainer: tint(palette.tertiary, .12),
      onTertiaryContainer: palette.tertiary,
      surface: surface,
      surfaceDim: palette.page,
      surfaceBright: dark ? palette.raised : surface,
      surfaceContainerLowest: palette.page,
      surfaceContainerLow: palette.page,
      surfaceContainer: surface,
      surfaceContainerHigh: palette.raised,
      surfaceContainerHighest: palette.raised,
      onSurface: palette.ink,
      onSurfaceVariant: palette.muted,
      outline: palette.muted,
      outlineVariant: palette.rule,
      error: dark ? ColorTokens.mathCoral : ColorTokens.ochreSeal,
      onError: onAccent,
    );
    final theme = AppThemeBuilder.build(
      scheme: scheme,
      page: palette.page,
      text: AppThemeBuilder.textTheme(
        palette.ink,
        headingWeight: FontWeight.w600,
      ),
      appearance: AppAppearance(
        visualStyle: space ? AppVisualStyle.space : AppVisualStyle.storybook,
        heroImage: space
            ? 'assets/images/space_companion.webp'
            : 'assets/images/candy_companion.webp',
        pageImage: space
            ? 'assets/images/space_companion.webp'
            : 'assets/images/candy_companion.webp',
        adventureImage: space
            ? 'assets/images/space_companion.webp'
            : 'assets/images/candy_companion.webp',
        cardStyle: space ? AppCardStyle.outlined : AppCardStyle.soft,
        cardRadius: space
            ? SpacingTokens.radiusCompact
            : SpacingTokens.radiusLarge,
        controlRadius: space
            ? SpacingTokens.radiusCompact
            : SpacingTokens.radiusLarge,
        navigationRadius: space
            ? SpacingTokens.radiusCompact
            : SpacingTokens.radiusPill,
      ),
      semantic: SemanticColorsExt(
        success: dark ? ColorTokens.mathMint : ColorTokens.ochreSuccess,
        caution: dark
            ? ColorTokens.spaceSecondaryLight
            : ColorTokens.ochreCaution,
        secondaryForeground: palette.secondary,
      ),
    );
    return theme.copyWith(
      extensions: [
        ...theme.extensions.values,
        PoemThemeExt(
          contentColor: scheme.onSurface,
          pinyinColor: scheme.onSurfaceVariant,
          contentFontFamily: null,
        ),
        MathThemeExt(contentColor: scheme.onSurface),
      ],
    );
  }

  static ({
    Color page,
    Color surface,
    Color raised,
    Color primary,
    Color secondary,
    Color tertiary,
    Color ink,
    Color muted,
    Color rule,
  })
  _palette({required bool space, required bool dark}) {
    if (space) {
      return (
        page: dark ? ColorTokens.spaceNight : ColorTokens.spacePage,
        surface: dark
            ? ColorTokens.spaceNightSurface
            : ColorTokens.spaceSurface,
        raised: dark ? ColorTokens.spaceNightRaised : ColorTokens.spaceRaised,
        primary: dark
            ? ColorTokens.spacePrimaryLight
            : ColorTokens.spacePrimary,
        secondary: dark
            ? ColorTokens.spaceSecondaryLight
            : ColorTokens.spaceSecondary,
        tertiary: dark
            ? ColorTokens.spaceTertiaryLight
            : ColorTokens.spaceTertiary,
        ink: dark ? ColorTokens.spaceNightInk : ColorTokens.spaceInk,
        muted: dark ? ColorTokens.spaceNightMuted : ColorTokens.spaceMuted,
        rule: dark ? ColorTokens.spaceNightRule : ColorTokens.spaceRule,
      );
    }
    return (
      page: dark ? ColorTokens.candyNight : ColorTokens.candyPage,
      surface: dark ? ColorTokens.candyNightSurface : ColorTokens.candySurface,
      raised: dark ? ColorTokens.candyNightRaised : ColorTokens.candyRaised,
      primary: dark ? ColorTokens.candyPrimaryLight : ColorTokens.candyPrimary,
      secondary: dark
          ? ColorTokens.candySecondaryLight
          : ColorTokens.candySecondary,
      tertiary: dark
          ? ColorTokens.candyTertiaryLight
          : ColorTokens.candyTertiary,
      ink: dark ? ColorTokens.candyNightInk : ColorTokens.candyInk,
      muted: dark ? ColorTokens.candyNightMuted : ColorTokens.candyMuted,
      rule: dark ? ColorTokens.candyNightRule : ColorTokens.candyRule,
    );
  }
}
