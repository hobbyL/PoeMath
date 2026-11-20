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
    return Padding(
      padding: storybook
          ? const EdgeInsets.fromLTRB(
              SpacingTokens.sm,
              SpacingTokens.md,
              SpacingTokens.sm,
              SpacingTokens.sm,
            )
          : EdgeInsets.zero,
      child: ColoredCard(
        color: storybook
            ? theme.colorScheme.surface
            : theme.scaffoldBackgroundColor,
        backgroundOpacity: 1,
        borderRadius: storybook
            ? BorderRadius.circular(SpacingTokens.radiusLarge)
            : BorderRadius.zero,
        padding: EdgeInsets.zero,
        child: CustomPaint(
          painter: storybook
              ? _BookBindingPainter(
                  rule: theme.colorScheme.outlineVariant,
                  hole: theme.scaffoldBackgroundColor,
                )
              : null,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              storybook
                  ? SpacingTokens.xl
                  : theme.appearance.pine
                  ? SpacingTokens.lg
                  : SpacingTokens.md,
              theme.appearance.pine ? SpacingTokens.lg : SpacingTokens.md,
              theme.appearance.pine ? SpacingTokens.lg : SpacingTokens.md,
              SpacingTokens.md,
            ),
            child: child,
          ),
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
    canvas.drawLine(
      const Offset(SpacingTokens.lg, SpacingTokens.md),
      Offset(SpacingTokens.lg, size.height - SpacingTokens.md),
      line,
    );
    for (
      var y = SpacingTokens.xl;
      y < size.height - SpacingTokens.md;
      y += SpacingTokens.xxl
    ) {
      canvas.drawCircle(Offset(SpacingTokens.sm, y), SpacingTokens.xs, fill);
      canvas.drawLine(
        Offset(0, y),
        Offset(SpacingTokens.sm, y),
        line..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_BookBindingPainter oldDelegate) =>
      oldDelegate.rule != rule || oldDelegate.hole != hole;
}
