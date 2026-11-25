import 'package:flutter/material.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_tile.dart';
import 'package:poemath/core/widgets/colored_card.dart';

/// A shared paper surface for related settings and navigation rows.
class AppTileGroup extends StatelessWidget {
  const AppTileGroup({super.key, required this.children});

  final List<AppTile> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final backgroundOpacity = switch (theme.appearance.visualStyle) {
      AppVisualStyle.pine => .02,
      AppVisualStyle.ink => .035,
      AppVisualStyle.storybook => .02,
      AppVisualStyle.space => .015,
    };
    return ColoredCard(
      color: theme.colorScheme.primary,
      backgroundOpacity: backgroundOpacity,
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) const Divider(height: 0),
            child.copyWith(flat: true),
          ],
        ],
      ),
    );
  }
}
