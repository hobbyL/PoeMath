import 'package:flutter/material.dart';
import 'package:poemath/core/theme/design_tokens.dart';

/// 使用独立的透明伴读插画，保留人物细节并融入明暗页头。
class ThemeCharacterArt extends StatelessWidget {
  const ThemeCharacterArt({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExcludeSemantics(
      child: Image.asset(
        theme.appearance.heroImage,
        width: size,
        height: size,
        fit: BoxFit.contain,
        cacheWidth: 480,
        excludeFromSemantics: true,
      ),
    );
  }
}
