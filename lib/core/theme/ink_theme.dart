import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';

/// 松墨素宣与赭石旧纸：独立完整色板，共用排版与组件交互。
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
    final text = _textTheme(ink);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: page,
      dividerColor: scheme.outlineVariant,
      textTheme: text,
      appBarTheme: AppBarThemeData(
        backgroundColor: page,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: text.titleLarge,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, SpacingTokens.xxl),
          shape: shape,
          textStyle: text.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(0, SpacingTokens.xxl),
          shape: shape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, SpacingTokens.xxl),
          shape: shape,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: shape, textStyle: text.labelLarge),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: surface,
          selectedBackgroundColor: primary,
          selectedForegroundColor: scheme.onPrimary,
          foregroundColor: scheme.onSurfaceVariant,
          side: BorderSide(color: scheme.outlineVariant),
          shape: shape,
          textStyle: text.labelLarge?.copyWith(
            fontFamily: TypographyTokens.inkFontFamily,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.all(SpacingTokens.md),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: scheme.secondaryContainer,
        secondarySelectedColor: scheme.secondaryContainer,
        checkmarkColor: primary,
        showCheckmark: true,
        side: BorderSide(color: scheme.outlineVariant),
        shape: shape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SpacingTokens.radiusLarge),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        constraints: const BoxConstraints(maxWidth: double.infinity),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SpacingTokens.radiusLarge),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return text.labelMedium!.copyWith(
            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          );
        }),
      ),
      extensions: [
        InkThemeExt(
          heroImage: ochre
              ? 'assets/images/ink_study_overlay.png'
              : 'assets/images/ink_landscape_overlay.png',
        ),
        SemanticColorsExt(
          success: dark
              ? ColorTokens.mathMint
              : (ochre ? ColorTokens.ochreSuccess : ColorTokens.successText),
          caution: dark
              ? ColorTokens.inkOchreLight
              : (ochre ? ColorTokens.ochreCaution : ColorTokens.cautionText),
          secondaryForeground: secondary,
        ),
      ],
    );
  }

  static TextTheme _textTheme(Color ink) {
    TextStyle title(double size) => TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w600,
      fontFamily: TypographyTokens.inkFontFamily,
      fontFamilyFallback: TypographyTokens.serifFallback,
      color: ink,
    );
    TextStyle body(double size) => TextStyle(fontSize: size, color: ink);
    return TextTheme(
      displayLarge: title(TypographyTokens.fsDisplay),
      displayMedium: title(TypographyTokens.fsPoemTitle),
      displaySmall: title(TypographyTokens.fsPoemContent),
      headlineLarge: title(TypographyTokens.fsHeadline),
      headlineMedium: title(TypographyTokens.fsHeadline),
      headlineSmall: title(TypographyTokens.fsPoemContent),
      titleLarge: title(TypographyTokens.fsTitle),
      titleMedium: title(TypographyTokens.fsSection),
      titleSmall: body(TypographyTokens.fsBodySmall)
          .copyWith(fontWeight: FontWeight.w500),
      bodyLarge: body(TypographyTokens.fsBody).copyWith(height: 1.5),
      bodyMedium: body(TypographyTokens.fsBody),
      bodySmall: body(TypographyTokens.fsCaption),
      labelLarge: body(TypographyTokens.fsBodySmall)
          .copyWith(fontWeight: FontWeight.w600),
      labelMedium: body(TypographyTokens.fsLabel),
      labelSmall: body(TypographyTokens.fsCompactLabel),
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

/// 页头装饰跟随当前主题；不通过比较颜色猜测配色身份。
class InkThemeExt extends ThemeExtension<InkThemeExt> {
  const InkThemeExt({required this.heroImage});

  final String heroImage;

  @override
  InkThemeExt copyWith({String? heroImage}) =>
      InkThemeExt(heroImage: heroImage ?? this.heroImage);

  @override
  InkThemeExt lerp(ThemeExtension<InkThemeExt>? other, double t) {
    if (other is! InkThemeExt) return this;
    return t < .5 ? this : other;
  }
}
