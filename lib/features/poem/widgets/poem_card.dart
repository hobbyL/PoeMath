import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/colored_card.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/poem_progress.dart';

/// 自然高度的诗词预览，标题、作者和学习状态均可随系统字号换行。
class PoemCard extends StatelessWidget {
  const PoemCard({
    super.key,
    required this.poem,
    this.onTap,
    this.isFavorite = false,
    this.learningStatus,
  });

  final Poem poem;
  final VoidCallback? onTap;
  final bool isFavorite;
  final LearningStatus? learningStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layerColor = switch (poem.layer) {
      'core' => theme.colorScheme.secondary,
      'extended' => theme.colorScheme.primary,
      _ => theme.colorScheme.tertiary,
    };
    final status = switch (learningStatus) {
      LearningStatus.mastered => '已掌握',
      LearningStatus.reviewing => '复习中',
      LearningStatus.learning => '学习中',
      _ => null,
    };
    final (statusColor, statusForeground) = switch (learningStatus) {
      LearningStatus.mastered => (
        theme.colorScheme.primary,
        theme.colorScheme.onPrimary,
      ),
      LearningStatus.reviewing => (
        theme.colorScheme.secondary,
        theme.colorScheme.onSecondary,
      ),
      LearningStatus.learning => (
        theme.colorScheme.tertiary,
        theme.colorScheme.onTertiary,
      ),
      _ => (theme.colorScheme.primary, theme.colorScheme.onPrimary),
    };
    return ColoredCard(
      width: double.infinity,
      color: theme.colorScheme.primary,
      backgroundOpacity: 0.06,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              children: [
                if (isFavorite)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: SpacingTokens.xs),
                      child: Icon(
                        Icons.favorite,
                        semanticLabel: '已收藏',
                        color: theme.semantic.secondaryForeground,
                        size: theme.textTheme.titleMedium?.fontSize,
                      ),
                    ),
                  ),
                TextSpan(text: poem.title),
              ],
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SpacingTokens.xs),
          Text(
            '${poem.dynasty} · ${poem.author}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          Wrap(
            spacing: SpacingTokens.xs,
            runSpacing: SpacingTokens.xs,
            alignment: WrapAlignment.center,
            children: [
              _tag(
                context,
                poem.layerLabel,
                color: layerColor,
                foreground: poem.layer == 'core'
                    ? theme.semantic.secondaryForeground
                    : layerColor,
              ),
              for (final tag in poem.tags.take(3))
                _tag(context, tag, color: theme.colorScheme.primary),
              if (status != null)
                _tag(
                  context,
                  status,
                  color: statusColor,
                  foreground: statusForeground,
                  filled: true,
                ),
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),
          Text(
            poem.content.split('\n').take(2).join('\n'),
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _tag(
    BuildContext context,
    String label, {
    required Color color,
    Color? foreground,
    bool filled = false,
  }) {
    final theme = Theme.of(context);
    return Chip(
      label: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: foreground ?? (filled ? theme.colorScheme.onPrimary : color),
        ),
      ),
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: SpacingTokens.xs),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      backgroundColor: filled ? color : color.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
      ),
    );
  }
}
