import 'package:flutter/material.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/colored_card.dart';

/// 正文阅读面：绘本使用装订手账，水墨和探索界面保留平整的内容面。
class ThemePagePanel extends StatelessWidget {
  const ThemePagePanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final storybook = theme.appearance.storybook;
    if (storybook) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          SpacingTokens.sm,
          SpacingTokens.md,
          SpacingTokens.sm,
          SpacingTokens.sm,
        ),
        child: ColoredCard(
          color: theme.colorScheme.surface,
          backgroundOpacity: 1,
          borderRadius: BorderRadius.circular(SpacingTokens.radiusLarge),
          padding: EdgeInsets.zero,
          child: CustomPaint(
            painter: _BookBindingPainter(
              rule: theme.colorScheme.outlineVariant,
              hole: theme.scaffoldBackgroundColor,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SpacingTokens.xl,
                SpacingTokens.lg,
                SpacingTokens.lg,
                SpacingTokens.md,
              ),
              child: child,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.zero,
      child: ColoredCard(
        color: theme.scaffoldBackgroundColor,
        backgroundOpacity: 1,
        borderRadius: BorderRadius.zero,
        padding: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            theme.appearance.ink ? SpacingTokens.lg : SpacingTokens.md,
            theme.appearance.ink ? SpacingTokens.lg : SpacingTokens.md,
            theme.appearance.ink ? SpacingTokens.lg : SpacingTokens.md,
            SpacingTokens.md,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _BookBindingPainter extends CustomPainter {
  const _BookBindingPainter({required this.rule, required this.hole});

  final Color rule;
  final Color hole;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = rule;
    final fill = Paint()..color = hole;
    // 装订只占页边，避免整页长线与密集线圈抢占正文注意力。
    for (
      var y = SpacingTokens.xl;
      y < size.height - SpacingTokens.md;
      y += SpacingTokens.xxl * 2
    ) {
      canvas.drawCircle(
        Offset(SpacingTokens.sm, y),
        SpacingTokens.xs / 2,
        fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            0,
            y - SpacingTokens.xs / 2,
            SpacingTokens.sm,
            SpacingTokens.xs,
          ),
          const Radius.circular(SpacingTokens.xs / 2),
        ),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(_BookBindingPainter oldDelegate) =>
      oldDelegate.rule != rule || oldDelegate.hole != hole;
}
