import 'package:flutter/material.dart';
import 'package:poemath/core/theme/design_tokens.dart';

/// 词汇练习共用的单行操作区，由页面管理草稿、切题和提交。
class EnglishPracticeActions extends StatelessWidget {
  const EnglishPracticeActions({
    super.key,
    required this.submitKey,
    required this.busy,
    required this.answered,
    required this.canSubmit,
    required this.complete,
    required this.onSkip,
    required this.onSubmit,
    required this.onContinue,
    this.onPrevious,
    this.onNext,
  });

  final Key submitKey;
  final bool busy, answered, canSubmit, complete;
  final VoidCallback onSkip, onSubmit, onContinue;
  final VoidCallback? onPrevious, onNext;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SpacingTokens.md,
      SpacingTokens.sm,
      SpacingTokens.md,
      SpacingTokens.sm,
    ),
    child: Row(
      children: [
        for (final direction in [
          (label: '上一题', icon: Icons.chevron_left, action: onPrevious),
          (label: '下一题', icon: Icons.chevron_right, action: onNext),
        ])
          IconButton(
            tooltip: direction.label,
            constraints: const BoxConstraints.tightFor(
              width: SpacingTokens.minTapTarget,
              height: SpacingTokens.minTapTarget,
            ),
            visualDensity: VisualDensity.standard,
            onPressed: busy ? null : direction.action,
            icon: Icon(direction.icon),
          ),
        const SizedBox(width: SpacingTokens.xs),
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(
              SpacingTokens.minTapTarget,
              SpacingTokens.minTapTarget,
            ),
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.xs),
          ),
          onPressed: busy || answered ? null : onSkip,
          child: const Text('跳过', textAlign: TextAlign.center),
        ),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(
          child: FilledButton(
            key: submitKey,
            style: FilledButton.styleFrom(
              minimumSize: const Size(
                SpacingTokens.minTapTarget,
                SpacingTokens.minTapTarget,
              ),
              padding: const EdgeInsets.all(SpacingTokens.sm),
            ),
            onPressed: busy
                ? null
                : answered
                ? onContinue
                : canSubmit
                ? onSubmit
                : null,
            child: Text(
              !answered
                  ? '提交答案'
                  : complete
                  ? '完成练习'
                  : '继续练习',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    ),
  );
}
