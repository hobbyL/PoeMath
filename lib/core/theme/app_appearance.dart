import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';

enum AppCardStyle { paper, sheet, soft, outlined }

enum AppVisualStyle { ink, pine, storybook, space }

/// 颜色以外的外观差异，随主题切换一起过渡。
class AppAppearance extends ThemeExtension<AppAppearance> {
  const AppAppearance({
    required this.heroImage,
    String? pageImage,
    String? adventureImage,
    this.visualStyle = AppVisualStyle.ink,
    this.cardStyle = AppCardStyle.paper,
    this.cardRadius = SpacingTokens.radiusMedium,
    this.controlRadius = SpacingTokens.radiusSmall,
    this.navigationRadius = SpacingTokens.radiusSmall,
  }) : pageImage = pageImage ?? heroImage,
       adventureImage = adventureImage ?? heroImage;

  final String heroImage;
  final String pageImage;
  final String adventureImage;
  final AppVisualStyle visualStyle;
  final AppCardStyle cardStyle;
  final double cardRadius;
  final double controlRadius;
  final double navigationRadius;

  bool get pine => visualStyle == AppVisualStyle.pine;
  bool get ochre => visualStyle == AppVisualStyle.ink;
  bool get ink => pine || ochre;
  bool get playful => storybook || space;
  bool get storybook => visualStyle == AppVisualStyle.storybook;
  bool get space => visualStyle == AppVisualStyle.space;

  /// 地图按主题与区域选取独立画作，不用给同一张地形染色模拟主题。
  String adventureTerrain(String region) =>
      'assets/images/adventure_${visualStyle.name}_$region.webp';

  String? get adventureGuide => switch (visualStyle) {
    AppVisualStyle.pine || AppVisualStyle.ink => null,
    AppVisualStyle.storybook => 'assets/images/candy_companion.webp',
    AppVisualStyle.space => 'assets/images/space_companion.webp',
  };

  @override
  AppAppearance copyWith({
    String? heroImage,
    String? pageImage,
    String? adventureImage,
    AppVisualStyle? visualStyle,
    AppCardStyle? cardStyle,
    double? cardRadius,
    double? controlRadius,
    double? navigationRadius,
  }) => AppAppearance(
    heroImage: heroImage ?? this.heroImage,
    pageImage: pageImage ?? this.pageImage,
    adventureImage: adventureImage ?? this.adventureImage,
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
      pageImage: t < .5 ? pageImage : other.pageImage,
      adventureImage: t < .5 ? adventureImage : other.adventureImage,
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
      const AppAppearance(
        heroImage: 'assets/images/ink_landscape_overlay.png',
        pageImage: 'assets/images/ink_landscape_overlay.png',
        adventureImage: 'assets/images/adventure_map_forest.jpg',
      );
}
