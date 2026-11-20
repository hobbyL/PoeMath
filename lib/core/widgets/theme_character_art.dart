import 'package:flutter/material.dart';
import 'package:poemath/core/theme/design_tokens.dart';

/// 插画拥有独立区域，文字不叠在人物上；太空主题从舷窗中看见伙伴。
class ThemeCharacterArt extends StatelessWidget {
  const ThemeCharacterArt({super.key, this.size = SpacingTokens.xxl * 4});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final art = ClipRect(
      child: OverflowBox(
        maxWidth: size * 2.88,
        maxHeight: size * 1.2,
        alignment: Alignment.centerRight,
        child: Image.asset(
          theme.appearance.heroImage,
          width: size * 2.88,
          height: size * 1.2,
          fit: BoxFit.cover,
          alignment: Alignment.centerRight,
          cacheWidth: 960,
          excludeFromSemantics: true,
        ),
      ),
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: theme.appearance.space
            ? Padding(
                padding: const EdgeInsets.all(SpacingTokens.sm),
                child: Material(
                  color: ColorTokens.spacePage,
                  shape: const CircleBorder(
                    side: BorderSide(
                      color: ColorTokens.spaceNightRule,
                      width: SpacingTokens.xs,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: art,
                ),
              )
            : ShaderMask(
                shaderCallback: (bounds) => RadialGradient(
                  radius: .5,
                  colors: [
                    theme.colorScheme.surface,
                    theme.colorScheme.surface,
                    theme.colorScheme.surface.withValues(alpha: 0),
                  ],
                  stops: const [0, .8, 1],
                ).createShader(bounds),
                blendMode: BlendMode.dstIn,
                child: art,
              ),
      ),
    );
  }
}
