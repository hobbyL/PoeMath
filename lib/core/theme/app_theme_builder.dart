import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:poemath/core/theme/design_tokens.dart';

/// 共享 Material 交互与排版基线；色板、字族和外观由预设提供。
class AppThemeBuilder {
  const AppThemeBuilder._();

  static ThemeData build({
    required ColorScheme scheme,
    required Color page,
    required TextTheme text,
    required AppAppearance appearance,
    required SemanticColorsExt semantic,
  }) {
    final brightness = scheme.brightness;
    final primary = scheme.primary;
    final surface = scheme.surface;
    final ink = scheme.onSurface;
    final statusBarStyle = SystemUiOverlayStyle(
      statusBarColor: page,
      statusBarIconBrightness: brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
      statusBarBrightness: brightness == Brightness.dark
          ? Brightness.dark
          : Brightness.light,
      systemStatusBarContrastEnforced: false,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(appearance.controlRadius),
    );
    final buttonShape = switch (appearance.visualStyle) {
      AppVisualStyle.storybook => const StadiumBorder(),
      AppVisualStyle.space => BeveledRectangleBorder(
        borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
      ),
      AppVisualStyle.ink || AppVisualStyle.pine => shape,
    };
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(appearance.controlRadius),
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
        systemOverlayStyle: statusBarStyle,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, SpacingTokens.xxl),
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(0, SpacingTokens.xxl),
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, SpacingTokens.xxl),
          shape: buttonShape,
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
            fontFamily: text.titleLarge?.fontFamily,
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
            color: selected
                ? appearance.ink
                      ? scheme.primary
                      : scheme.onPrimary
                : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          );
        }),
      ),
      extensions: [appearance, semantic],
    );
  }

  static TextTheme textTheme(
    Color ink, {
    String? headingFontFamily,
    List<String>? headingFallback,
    FontWeight headingWeight = FontWeight.w600,
  }) {
    TextStyle title(double size) => TextStyle(
      fontSize: size,
      fontWeight: headingWeight,
      fontFamily: headingFontFamily,
      fontFamilyFallback: headingFallback,
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
}
