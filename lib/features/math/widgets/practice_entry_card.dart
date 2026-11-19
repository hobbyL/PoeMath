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
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final playful = theme.appearance.playful;

    return ColoredCard(
      color: primary,
      onTap: onTap,
      padding: const EdgeInsets.all(SpacingTokens.md),
      child: Column(
        crossAxisAlignment: playful
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          if (playful)
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              radius: SpacingTokens.lg,
              child: Icon(icon, size: SpacingTokens.xl, color: primary),
            )
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
