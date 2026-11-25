import 'package:flutter/material.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/domain/english_practice.dart';
import 'package:poemath/features/english/widgets/english_practice_actions.dart';

class EnglishSpellingPracticeContent extends StatelessWidget {
  const EnglishSpellingPracticeContent({
    super.key,
    required this.question,
    required this.tokens,
    required this.busy,
    required this.complete,
    required this.onChange,
    required this.onSkip,
    required this.onSubmit,
    required this.onContinue,
    this.feedback,
    this.onPrevious,
    this.onNext,
  });

  final EnglishQuestion question;
  final List<int> tokens;
  final bool busy, complete;
  final EnglishAnswer? feedback;
  final ValueChanged<List<int>> onChange;
  final VoidCallback onSkip, onSubmit, onContinue;
  final VoidCallback? onPrevious, onNext;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: ResponsiveLayout.wideBreakpoint,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
                final split =
                    constraints.maxWidth >=
                    ResponsiveLayout.mediumBreakpoint * scale;
                return SingleChildScrollView(
                  key: ValueKey('english-spelling-question-${question.id}'),
                  padding: const EdgeInsets.all(SpacingTokens.md),
                  child: split
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _answerCard(context)),
                            const SizedBox(width: SpacingTokens.lg),
                            Expanded(child: _letters(context)),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _answerCard(context),
                            const SizedBox(height: SpacingTokens.lg),
                            _letters(context),
                          ],
                        ),
                );
              },
            ),
          ),
          EnglishPracticeActions(
            key: const ValueKey('english-spelling-actions'),
            submitKey: const ValueKey('english-spelling-submit'),
            busy: busy,
            answered: feedback != null,
            canSubmit:
                tokens.length == question.options.length && tokens.isNotEmpty,
            complete: complete,
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

  Widget _answerCard(BuildContext context) {
    final theme = Theme.of(context);
    final answer = feedback;
    final value =
        answer?.answer ?? tokens.map((i) => question.options[i]).join();
    final editable = !busy && answer == null && tokens.isNotEmpty;
    final color = answer == null || answer.skipped
        ? theme.colorScheme.primary
        : answer.correct == true
        ? theme.semantic.success
        : theme.colorScheme.error;
    return ColoredCard(
      key: const ValueKey('english-spelling-answer'),
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: SpacingTokens.minTapTarget * 2,
            ),
            child: Center(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  value.isEmpty
                      ? answer == null
                            ? '点选字母'
                            : '—'
                      : value,
                  key: const ValueKey('english-spelling-input'),
                  textAlign: TextAlign.center,
                  style: value.isEmpty
                      ? theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : theme.textTheme.headlineMedium?.copyWith(color: color),
                ),
              ),
            ),
          ),
          if (answer != null) ...[
            if (!answer.skipped)
              Icon(
                answer.correct == true
                    ? Icons.check_circle_outline
                    : Icons.cancel_outlined,
                color: color,
                semanticLabel: answer.correct == true ? '拼写正确' : '拼写有误',
              ),
            if (answer.correct != true) ...[
              const SizedBox(height: SpacingTokens.sm),
              Text(
                '正确拼写',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              Text(
                question.answers.join(' / '),
                key: const ValueKey('english-spelling-correct'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
            ],
          ] else
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: '撤回一个字母',
                  constraints: const BoxConstraints(
                    minWidth: SpacingTokens.minTapTarget,
                    minHeight: SpacingTokens.minTapTarget,
                  ),
                  visualDensity: VisualDensity.standard,
                  onPressed: editable
                      ? () => onChange([...tokens]..removeLast())
                      : null,
                  icon: const Icon(Icons.backspace_outlined),
                ),
                TextButton(
                  onPressed: editable ? () => onChange([]) : null,
                  child: const Text('清空'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _letters(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      key: const ValueKey('english-spelling-letters'),
      alignment: WrapAlignment.center,
      spacing: SpacingTokens.sm,
      runSpacing: SpacingTokens.sm,
      children: [
        for (final (index, letter) in question.options.indexed)
          Semantics(
            button: true,
            enabled: !busy && feedback == null && !tokens.contains(index),
            selected: tokens.contains(index),
            label: letter == ' ' ? '空格' : '字母 $letter',
            excludeSemantics: true,
            onTap: !busy && feedback == null && !tokens.contains(index)
                ? () => onChange([...tokens, index])
                : null,
            child: ColoredCard(
              key: ValueKey('english-token-$index'),
              color: theme.colorScheme.primary,
              padding: const EdgeInsets.all(SpacingTokens.sm),
              constraints: const BoxConstraints(
                minWidth: SpacingTokens.minTapTarget + SpacingTokens.sm,
                minHeight: SpacingTokens.minTapTarget + SpacingTokens.sm,
              ),
              onTap: !busy && feedback == null && !tokens.contains(index)
                  ? () => onChange([...tokens, index])
                  : null,
              child: Text(
                letter == ' ' ? '␣' : letter,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: tokens.contains(index) || feedback != null
                      ? theme.disabledColor
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
