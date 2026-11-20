import 'package:flutter/material.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/animated_hero_header.dart';
import 'package:poemath/core/widgets/theme_character_art.dart';

/// 两种首页构图共用真实打卡行为，探索进度只取当天已完成的目标。
class PlayfulCheckInContent extends StatelessWidget {
  const PlayfulCheckInContent({
    super.key,
    required this.contentWidth,
    required this.summary,
    required this.action,
    required this.completedGoals,
    required this.totalGoals,
  });

  /// 由页面扣除安全区与共享页头留白，避免前景布局回调干扰下拉。
  final double contentWidth;
  final Widget summary;
  final Widget action;
  final int completedGoals;
  final int totalGoals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final colors = AnimatedHeroColors(theme);
    final space = theme.appearance.space;
    final landscape = media.orientation == Orientation.landscape;
    final scale = media.textScaler.scale(16) / 16;
    final effectiveWidth = contentWidth / scale;
    final title = Text(
      space ? '今日探索' : '学习手账',
      key: const ValueKey('home-theme-title'),
      textAlign: TextAlign.center,
      style:
          (landscape
                  ? theme.textTheme.titleMedium
                  : theme.textTheme.headlineSmall)
              ?.copyWith(
                color: colors.foreground,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
    );
    final progressLabel = Text(
      '$completedGoals / $totalGoals 目标完成',
      textAlign: TextAlign.center,
      style: theme.textTheme.labelLarge?.copyWith(color: colors.foreground),
    );
    const artSize = SpacingTokens.xxl + SpacingTokens.lg;
    final art = SizedBox.square(
      dimension: artSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const ThemeCharacterArt(size: artSize),
          if (space)
            Positioned.fill(
              child: ExcludeSemantics(
                child: CircularProgressIndicator(
                  value: totalGoals == 0 ? 0 : completedGoals / totalGoals,
                  strokeWidth: SpacingTokens.xs,
                  color: ColorTokens.spaceSecondaryLight,
                  backgroundColor: ColorTokens.spaceNightRule,
                  strokeCap: StrokeCap.round,
                ),
              ),
            ),
        ],
      ),
    );
    final key = ValueKey(space ? 'space-check-in' : 'storybook-check-in');

    if (landscape) {
      // 矮屏优先展示打卡和正文。大字号时让出装饰占位，不压缩文字或按钮。
      final showArt = effectiveWidth >= 480;
      return Center(
        child: Row(
          key: key,
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (scale <= 1.25) ...[
                    title,
                    const SizedBox(height: SpacingTokens.sm),
                  ],
                  summary,
                ],
              ),
            ),
            if (showArt) ...[const SizedBox(width: SpacingTokens.md), art],
            const SizedBox(width: SpacingTokens.md),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth * .4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (space) ...[
                    progressLabel,
                    const SizedBox(height: SpacingTokens.sm),
                  ],
                  action,
                ],
              ),
            ),
          ],
        ),
      );
    }

    final showArt = effectiveWidth >= 340;
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (scale <= 1.25) ...[title, const SizedBox(height: SpacingTokens.sm)],
        Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              // 两边等宽，让文字始终以卡片中心为轴，插画不挤偏信息。
              padding: EdgeInsets.symmetric(
                horizontal: showArt ? artSize + SpacingTokens.sm : 0,
              ),
              child: summary,
            ),
            if (showArt)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(child: art),
              ),
          ],
        ),
        if (space) ...[const SizedBox(height: SpacingTokens.sm), progressLabel],
        const SizedBox(height: SpacingTokens.sm),
        Align(child: action),
      ],
    );
  }
}
