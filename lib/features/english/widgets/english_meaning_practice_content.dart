import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/domain/english_practice.dart';
import 'package:poemath/features/english/widgets/english_practice_actions.dart';

/// 词义选择题面和固定操作区；作答与草稿仍由练习页管理。
class EnglishMeaningPracticeContent extends StatelessWidget {
  const EnglishMeaningPracticeContent({
    super.key,
    required this.question,
    required this.selected,
    required this.busy,
    required this.lastQuestion,
    required this.onSelect,
    this.onPrevious,
    this.onNext,
    required this.onSkip,
    required this.onSubmit,
    required this.onContinue,
    this.feedback,
  });

  final EnglishQuestion question;
  final String selected;
  final bool busy, lastQuestion;
  final EnglishAnswer? feedback;
  final ValueChanged<String> onSelect;
  final VoidCallback onSkip, onSubmit, onContinue;
  final VoidCallback? onPrevious, onNext;

  @override
  Widget build(BuildContext context) {
    final answer = feedback;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ResponsiveLayout.wideBreakpoint,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _body(context)),
            EnglishPracticeActions(
              key: const ValueKey('english-meaning-actions'),
              submitKey: const ValueKey('english-meaning-submit'),
              busy: busy,
              answered: answer != null,
              canSubmit: question.options.contains(selected),
              complete: lastQuestion,
              onPrevious: onPrevious,
              onNext: onNext,
              onSkip: onSkip,
              onSubmit: onSubmit,
              onContinue: onContinue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) => CustomScrollView(
    key: ValueKey('english-meaning-question-${question.id}'),
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.all(SpacingTokens.md),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) => SliverCardGrid(
            columnCount:
                (constraints.crossAxisExtent /
                        ResponsiveLayout.compactCardWidth)
                    .floor()
                    .clamp(1, 2),
            itemCount: question.options.length,
            itemBuilder: _option,
          ),
        ),
      ),
    ],
  );

  Widget _option(BuildContext context, int index) {
    final theme = Theme.of(context);
    final option = question.options[index];
    final answer = feedback;
    final chosen = (answer?.answer ?? selected) == option;
    final correct = answer != null && question.accepts(option);
    final wrong = answer != null && chosen && !correct;
    final color = correct
        ? theme.semantic.success
        : wrong
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    final label = String.fromCharCode('A'.codeUnitAt(0) + index);
    final enabled = !busy && answer == null;
    final select = enabled ? () => onSelect(option) : null;
    final status = correct
        ? '，正确答案'
        : wrong
        ? '，所选答案不正确'
        : '';
    return Semantics(
      button: true,
      enabled: enabled,
      selected: chosen,
      inMutuallyExclusiveGroup: true,
      label: '选项 $label，$option$status',
      onTap: select,
      excludeSemantics: true,
      child: ColoredCard(
        key: ValueKey('english-meaning-option-$index'),
        color: color,
        backgroundOpacity: chosen || correct ? .12 : .02,
        onTap: select,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: SpacingTokens.minTapTarget,
          ),
          child: Row(
            children: [
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: SpacingTokens.md),
              Expanded(child: Text(option, style: theme.textTheme.titleMedium)),
              const SizedBox(width: SpacingTokens.sm),
              Icon(
                correct
                    ? Icons.check_circle_outline
                    : wrong
                    ? Icons.cancel_outlined
                    : chosen
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: chosen || correct
                    ? color
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
