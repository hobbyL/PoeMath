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
    final secondary = theme.colorScheme.secondary;

    // 收集标签
    final tags = <Widget>[
      ...poem.tags.take(3).map((tag) => _buildTag(tag, primary)),
      if (poem.isRequired) _buildTag('必背', secondary),
    ];

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
      child: Container(
        padding: const EdgeInsets.all(SpacingTokens.md),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 第一行：标题 + 朝代·作者（baseline 对齐）
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.ideographic,
              children: [
                if (isFavorite) ...[
                  Icon(Icons.favorite, color: secondary, size: 16),
                  const SizedBox(width: SpacingTokens.xs),
                ],
                Flexible(
                  child: Text(
                    poem.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: SpacingTokens.sm),
                Text(
                  '${poem.dynasty} · ${poem.author}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            // 第二行：标签
            if (tags.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.xs),
              Wrap(
                spacing: SpacingTokens.xs,
                runSpacing: SpacingTokens.xs,
                alignment: WrapAlignment.center,
                children: tags,
              ),
            ],

            // 第三行：诗词内容
            const SizedBox(height: SpacingTokens.sm),
            Text(
              _firstLine(poem.content),
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
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
