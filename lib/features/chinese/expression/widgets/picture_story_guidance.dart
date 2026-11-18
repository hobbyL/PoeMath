import 'package:flutter/material.dart';

import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/picture_story_prompt.dart';

/// 使用原题问题组织观察，不推断题图内容，也不把浏览进度当作答题结果。
class PictureStoryGuidance extends StatelessWidget {
  const PictureStoryGuidance({
    super.key,
    required this.prompt,
    required this.guided,
    required this.questionIndex,
    required this.busy,
    required this.onQuestionChanged,
    required this.onModeChanged,
    required this.onStartSpeaking,
  });

  final PictureStoryPrompt prompt;
  final bool guided;
  final int questionIndex;
  final bool busy;
  final ValueChanged<int> onQuestionChanged;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onStartSpeaking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final questions = prompt.questions;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    SegmentedButton<bool> modeSelector(Axis direction) => SegmentedButton<bool>(
      direction: direction,
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(0, SpacingTokens.xxl),
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm),
      ),
      segments: const [
        ButtonSegment<bool>(value: true, label: Text('问答模式')),
        ButtonSegment<bool>(value: false, label: Text('完整模式')),
      ],
      selected: {guided},
      onSelectionChanged: busy
          ? null
          : (selection) => onModeChanged(selection.first),
    );
    return ColoredCard(
      color: theme.colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (largeText)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(prompt.title, style: theme.textTheme.titleLarge),
                const SizedBox(height: SpacingTokens.xs),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: modeSelector(Axis.vertical),
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(prompt.title, style: theme.textTheme.titleLarge),
                ),
                const SizedBox(width: SpacingTokens.xs),
                modeSelector(Axis.horizontal),
              ],
            ),
          const SizedBox(height: SpacingTokens.md),
          if (guided && questions.isNotEmpty) ...[
            Text(
              '观察问题 ${questionIndex + 1}/${questions.length}',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: SpacingTokens.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                questions[questionIndex],
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (questions.length > 1) ...[
              const SizedBox(height: SpacingTokens.sm),
              Wrap(
                spacing: SpacingTokens.sm,
                children: [
                  TextButton.icon(
                    onPressed: busy || questionIndex == 0
                        ? null
                        : () => onQuestionChanged(questionIndex - 1),
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('上一问'),
                  ),
                  TextButton.icon(
                    onPressed: busy || questionIndex == questions.length - 1
                        ? null
                        : () => onQuestionChanged(questionIndex + 1),
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('下一问'),
                  ),
                ],
              ),
            ],
            TextButton.icon(
              onPressed: busy ? null : onStartSpeaking,
              icon: const Icon(Icons.record_voice_over_outlined),
              label: const Text('把观察连起来讲'),
            ),
          ] else ...[
            const Text('看一看画面，把你发现的事情连起来讲。'),
            for (final question in questions)
              Padding(
                padding: const EdgeInsets.only(top: SpacingTokens.sm),
                child: Text(question),
              ),
          ],
          if (prompt.goals.isNotEmpty) ...[
            const SizedBox(height: SpacingTokens.md),
            Text('这次试一试', style: theme.textTheme.titleSmall),
            for (final goal in prompt.goals)
              Padding(
                padding: const EdgeInsets.only(top: SpacingTokens.xs),
                child: Text(goal),
              ),
          ],
        ],
      ),
    );
  }
}

/// 所有帮手均为本地提示，展开不生成答案或请求 AI。
class PictureStoryLanguageHelp extends StatelessWidget {
  const PictureStoryLanguageHelp({
    super.key,
    required this.prompt,
    required this.canViewReference,
    required this.onUsed,
  });

  final PictureStoryPrompt prompt;
  final bool canViewReference;
  final VoidCallback onUsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String title, List<String> lines) => Material(
      type: MaterialType.transparency,
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: SpacingTokens.md),
        title: Text(title, style: theme.textTheme.titleSmall),
        onExpansionChanged: (open) {
          if (open) onUsed();
        },
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: SpacingTokens.sm),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(line),
              ),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (prompt.sceneFacts.isNotEmpty) section('观察线索', prompt.sceneFacts),
        section('把话说完整', ['想想“谁、在哪里、做什么”。', '图中有……正在……']),
        section('把事情讲顺', ['先……接着……最后……', '图里没有画出的情节，可以说“我猜”或“我想”。']),
        section('加上原因和心情', ['因为……所以……', '我猜……，图里的线索是……']),
        if (prompt.reference.isNotEmpty)
          if (canViewReference)
            section('看看另一种说法', ['这是一种说法，也可以有自己的表达。', prompt.reference])
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: SpacingTokens.sm),
              child: Text('先试着录一段，再看看另一种说法。'),
            ),
      ],
    );
  }
}
