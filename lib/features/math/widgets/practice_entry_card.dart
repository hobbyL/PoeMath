// lib/features/math/widgets/practice_entry_card.dart
//
// 练习入口卡片：纸面上的图标、楷体标题与说明，按自然高度排成网格。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';

class PracticeEntryCard extends StatelessWidget {
  const PracticeEntryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.appearance.storybook
        ? accent ?? theme.colorScheme.primary
        : theme.colorScheme.primary;
    final playful = theme.appearance.playful;

    if (theme.appearance.ochre) {
      return AppTile(
        icon: icon,
        iconColor: theme.colorScheme.primary,
        title: title,
        titleMaxLines: 1,
        subtitle: description,
        onTap: onTap,
      );
    }

    if (theme.appearance.space) {
      return AppTile(
        icon: icon,
        iconColor: primary,
        title: title,
        subtitle: description,
        trailingIcon: Icons.arrow_forward_rounded,
        onTap: onTap,
      );
    }

    return ColoredCard(
      color: primary,
      backgroundOpacity: playful ? .1 : .02,
      onTap: onTap,
      padding: const EdgeInsets.all(SpacingTokens.md),
      child: Column(
        crossAxisAlignment: playful
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          if (playful)
            Icon(icon, color: primary, size: SpacingTokens.xl)
          else
            Row(
              children: [
                Icon(icon, size: SpacingTokens.xl, color: primary),
                const Spacer(),
                Icon(
                  Icons.arrow_forward,
                  size: SpacingTokens.md,
                  color: primary,
                ),
              ],
            ),
          const SizedBox(height: SpacingTokens.lg),
          Text(
            title,
            textAlign: playful ? TextAlign.center : TextAlign.start,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          Text(
            description,
            textAlign: playful ? TextAlign.center : TextAlign.start,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
