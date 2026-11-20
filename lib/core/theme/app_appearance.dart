import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';

enum AppCardStyle { paper, sheet, soft, outlined }

enum AppVisualStyle { ink, pine, storybook, space }

/// 颜色以外的外观差异，随主题切换一起过渡。
class AppAppearance extends ThemeExtension<AppAppearance> {
  const AppAppearance({
    required this.heroImage,
    this.visualStyle = AppVisualStyle.ink,
    this.cardStyle = AppCardStyle.paper,
    this.cardRadius = SpacingTokens.radiusMedium,
    this.controlRadius = SpacingTokens.radiusSmall,
    this.navigationRadius = SpacingTokens.radiusSmall,
  });

  final String heroImage;
  final AppVisualStyle visualStyle;
  final AppCardStyle cardStyle;
  final double cardRadius;
  final double controlRadius;
  final double navigationRadius;

  bool get pine => visualStyle == AppVisualStyle.pine;
  bool get playful => storybook || space;
  bool get storybook => visualStyle == AppVisualStyle.storybook;
  bool get space => visualStyle == AppVisualStyle.space;

  @override
  AppAppearance copyWith({
    String? heroImage,
    AppVisualStyle? visualStyle,
    AppCardStyle? cardStyle,
    double? cardRadius,
    double? controlRadius,
    double? navigationRadius,
  }) => AppAppearance(
    heroImage: heroImage ?? this.heroImage,
    visualStyle: visualStyle ?? this.visualStyle,
    cardStyle: cardStyle ?? this.cardStyle,
    cardRadius: cardRadius ?? this.cardRadius,
    controlRadius: controlRadius ?? this.controlRadius,
    navigationRadius: navigationRadius ?? this.navigationRadius,
  );

  @override
  AppAppearance lerp(ThemeExtension<AppAppearance>? other, double t) {
    if (other is! AppAppearance) return this;
    return AppAppearance(
      heroImage: t < .5 ? heroImage : other.heroImage,
      visualStyle: t < .5 ? visualStyle : other.visualStyle,
      cardStyle: t < .5 ? cardStyle : other.cardStyle,
      cardRadius: lerpDouble(cardRadius, other.cardRadius, t)!,
      controlRadius: lerpDouble(controlRadius, other.controlRadius, t)!,
      navigationRadius: lerpDouble(
        navigationRadius,
        other.navigationRadius,
        t,
      )!,
    );
  }
}

extension ThemeDataAppearance on ThemeData {
  AppAppearance get appearance =>
      extension<AppAppearance>() ??
      const AppAppearance(heroImage: 'assets/images/ink_landscape_overlay.png');
}
