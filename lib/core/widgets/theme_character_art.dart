import 'package:flutter/material.dart';
import 'package:poemath/core/theme/design_tokens.dart';

/// 从主题横幅右侧取完整人物，边缘渐隐后融入页头背景。
class ThemeCharacterArt extends StatelessWidget {
  const ThemeCharacterArt({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: ShaderMask(
          shaderCallback: (bounds) => RadialGradient(
            radius: .5,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surface,
              theme.colorScheme.surface.withValues(alpha: 0),
            ],
            stops: const [0, .65, 1],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: ClipRect(
            child: OverflowBox(
              maxWidth: size * 2.4,
              maxHeight: size,
              alignment: Alignment.centerRight,
              child: Image.asset(
                theme.appearance.heroImage,
                width: size * 2.4,
                height: size,
                fit: BoxFit.contain,
                cacheWidth: 960,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
