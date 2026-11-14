import 'package:flutter/material.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';

/// The review shell is shared; content and approval rules belong to each subject.
class TextbookReviewHeading extends StatelessWidget {
  const TextbookReviewHeading({
    super.key,
    required this.title,
    required this.summary,
  });

  final String title;
  final String summary;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: SpacingTokens.sm),
      Text(summary),
      const SizedBox(height: SpacingTokens.md),
    ],
  );
}

class TextbookReviewSectionHeader extends StatelessWidget {
  const TextbookReviewSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.summary,
    this.actionIcon = Icons.chevron_right,
    this.actionIconAlignment = IconAlignment.end,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? summary;
  final IconData actionIcon;
  final IconAlignment actionIconAlignment;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(height: SpacingTokens.xl),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: SpacingTokens.md,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (actionLabel != null)
            TextButton.icon(
              onPressed: onAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, SpacingTokens.minTapTarget),
                padding: const EdgeInsetsDirectional.only(
                  start: SpacingTokens.sm,
                ),
                iconSize: SpacingTokens.lg,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              iconAlignment: actionIconAlignment,
              icon: Icon(actionIcon),
              label: Text(actionLabel!),
            )
          else if (summary != null)
            Text(summary!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ],
  );
}

class TextbookReviewProgressCard extends StatelessWidget {
  const TextbookReviewProgressCard({
    super.key,
    required this.message,
    required this.completed,
    required this.total,
    required this.running,
    required this.onPause,
    required this.onResume,
  });

  final String message;
  final int completed;
  final int total;
  final bool running;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
    child: ColoredCard(
      color: Theme.of(context).colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(liveRegion: true, child: Text(message)),
          if (running) ...[
            const SizedBox(height: SpacingTokens.sm),
            LinearProgressIndicator(
              value: total > 0 ? completed / total : null,
            ),
          ],
          TextButton(
            onPressed: running ? onPause : onResume,
            child: Text(running ? '暂停整理' : '继续整理'),
          ),
        ],
      ),
    ),
  );
}
