// lib/features/poem/widgets/poem_card.dart
//
// 诗词列表卡片：无边框、纯色背景、圆角，与首页卡片风格一致。

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
    final primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.md,
        vertical: SpacingTokens.xs,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        child: Container(
          padding: const EdgeInsets.all(SpacingTokens.md),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题 + 标签行
              _buildTitleRow(theme),
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
            ],
          ),
        ),
      ),
    );
  }

  /// 标题 + 收藏 + 必背 + 标签（baseline 对齐）。
  Widget _buildTitleRow(ThemeData theme) {
    final secondary = theme.colorScheme.secondary;
    final primary = theme.colorScheme.primary;

    return Wrap(
      spacing: SpacingTokens.xs,
      runSpacing: SpacingTokens.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          poem.title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (isFavorite)
          Icon(
            Icons.favorite,
            color: secondary,
            size: 16,
          ),
        ...poem.tags.take(3).map((tag) => _buildTag(tag, primary)),
        if (poem.isRequired) _buildTag('必背', secondary),
      ],
    );
  }

  /// 小标签：与「必背」同款样式。
  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w500,
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
