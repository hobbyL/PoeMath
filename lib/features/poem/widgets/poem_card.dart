// lib/features/poem/widgets/poem_card.dart
//
// 诗词列表卡片：无边框、纯色背景、圆角，与首页卡片风格一致。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/poem_progress.dart';

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
    final primary = theme.colorScheme.primary;
    final secondary = theme.colorScheme.secondary;

    // 收集标签
    final tags = <Widget>[
      ...poem.tags.take(3).map((tag) => _buildTag(tag, primary)),
      if (poem.isRequired) _buildTag('必背', secondary),
    ];

    // 判断是否显示已背诵丝带
    final showRibbon = learningStatus != null &&
        learningStatus != LearningStatus.notStarted;
    final ribbonLabel = switch (learningStatus) {
      LearningStatus.mastered => '已掌握',
      LearningStatus.reviewing => '复习中',
      LearningStatus.learning => '学习中',
      _ => '',
    };
    final ribbonColor = switch (learningStatus) {
      LearningStatus.mastered => theme.colorScheme.primary,
      LearningStatus.reviewing => theme.colorScheme.secondary,
      _ => theme.colorScheme.tertiary,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(SpacingTokens.md),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.06),
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

      // 右上角斜向丝带
      if (showRibbon)
        Positioned(
          top: 0,
          right: 0,
          child: _RibbonBadge(
            label: ribbonLabel,
            color: ribbonColor,
          ),
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

/// 右上角斜向丝带标签。
class _RibbonBadge extends StatelessWidget {
  const _RibbonBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RibbonPainter(color: color),
      child: SizedBox(
        width: 64,
        height: 64,
        child: Transform.rotate(
          angle: math.pi / 4, // 45°
          child: Align(
            alignment: const Alignment(0.4, -0.65),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 绘制右上角三角丝带背景。
class _RibbonPainter extends CustomPainter {
  _RibbonPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(size.width * 0.2, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.8)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_RibbonPainter oldDelegate) => color != oldDelegate.color;
}
