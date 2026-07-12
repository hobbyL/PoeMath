// lib/features/poem/widgets/poem_card.dart
//
// 诗词列表卡片。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/data/models/poem.dart';

class PoemCard extends StatelessWidget {
  const PoemCard({
    super.key,
    required this.poem,
    this.onTap,
    this.isFavorite = false,
  });

  final Poem poem;
  final VoidCallback? onTap;
  final bool isFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.md,
        vertical: SpacingTokens.xs,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      poem.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isFavorite)
                    const Icon(
                      Icons.favorite,
                      color: ColorTokens.poemSeal,
                      size: 18,
                    ),
                  if (poem.isRequired)
                    Container(
                      margin: const EdgeInsets.only(left: SpacingTokens.xs),
                      padding: const EdgeInsets.symmetric(
                        horizontal: SpacingTokens.xs,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: ColorTokens.poemCinnabar.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '必背',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: ColorTokens.poemCinnabar,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: SpacingTokens.xs),
              Text(
                '${poem.dynasty} · ${poem.author}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: SpacingTokens.sm),
              Text(
                _firstLine(poem.content),
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (poem.tags.isNotEmpty) ...[
                const SizedBox(height: SpacingTokens.sm),
                Wrap(
                  spacing: SpacingTokens.xs,
                  children: poem.tags.take(3).map((tag) {
                    return Chip(
                      label: Text(tag),
                      labelStyle: theme.textTheme.labelSmall,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _firstLine(String content) {
    final lines = content.split('\n');
    if (lines.length >= 2) return '${lines[0]}\n${lines[1]}';
    return lines.first;
  }
}
