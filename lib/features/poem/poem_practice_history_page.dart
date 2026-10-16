import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/poem_practice_details.dart';
import 'package:poemath/features/poem/poem_answer_difference.dart';
import 'package:poemath/features/poem/poem_dictation_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

class PoemPracticeHistoryPage extends ConsumerStatefulWidget {
  const PoemPracticeHistoryPage({super.key, required this.poemId});
  final String poemId;
  @override
  ConsumerState<PoemPracticeHistoryPage> createState() =>
      _PoemPracticeHistoryPageState();
}

class _PoemPracticeHistoryPageState
    extends ConsumerState<PoemPracticeHistoryPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = ref.watch(learningActivityRepositoryProvider);
    final activities = repo.forPoem(widget.poemId);
    final poem = ref.watch(poemByIdProvider(widget.poemId));
    final lines = poem == null ? <String>[] : poemPracticeLines(poem.content);
    final wrong = repo
        .unresolvedLines(widget.poemId)
        .where(
          (line) =>
              line.lineIndex < lines.length &&
              lines[line.lineIndex] == line.lineText,
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('练习结果与错句')),
      body: ListView(
        padding: const EdgeInsets.all(SpacingTokens.md),
        children: [
          ColoredCard(
            color: theme.colorScheme.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '待复练 ${wrong.length} 句',
                  style: theme.textTheme.titleMedium,
                ),
                const Text(
                  '错句来自实际作答或使用提示的记录。完整听写该句正确后移出待复练；旧记录无明细时不推断。',
                ),
                if (wrong.isNotEmpty) ...[
                  const SizedBox(height: SpacingTokens.sm),
                  FilledButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).push<Object?>(
                        MaterialPageRoute(
                          builder: (_) => PoemDictationPage(
                            poemId: widget.poemId,
                            targetLineIndices:
                                wrong.map((line) => line.lineIndex).toList(),
                          ),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                    icon: const Icon(Icons.edit_note),
                    label: const Text('仅练错句'),
                  ),
                  const Text('专项只记录练习，不更新全诗掌握等级、不推进复习轮次、不发累计星星。'),
                ],
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.md),
          if (activities.isEmpty) const Text('还没有练习结果，完成一次背诵、测验或听写后可在这里回看。'),
          for (final activity in activities) ...[
            ColoredCard(
              color: theme.colorScheme.secondary,
              child: Builder(
                builder: (context) {
                  final details =
                      PoemPracticeDetails.decode(activity.detailsJson);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${activity.completedAt.toLocal().toString().substring(0, 16)} · ${details?.targeted == true ? '错句专项' : '练习结果'}',
                        style: theme.textTheme.titleSmall,
                      ),
                      if (details == null)
                        const Text('该记录没有逐句作答，无法还原差异；旧记录不推断错句。')
                      else if (details.lines.isEmpty)
                        const Text('本次没有诗句题的作答明细（作者、朝代题不作为错句）。')
                      else
                        for (final line in details.lines)
                          Padding(
                            padding: const EdgeInsets.only(
                              top: SpacingTokens.md,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '第 ${line.lineIndex + 1} 句 · ${line.passed ? '答对' : '需复练'}${line.wholeLine ? '' : '（部分作答）'}',
                                ),
                                if (!line.wholeLine)
                                  Text('完整原句：${line.lineText}'),
                                PoemAnswerDifference(
                                  expected: line.expected,
                                  answer: line.answer,
                                ),
                                if (line.hintUsed) const Text('本句使用了提示'),
                                if (line.wrongAttempts > 0)
                                  Text(
                                    '错误尝试 ${line.wrongAttempts} 次：${line.wrongAnswers.join('、')}',
                                  ),
                              ],
                            ),
                          ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: SpacingTokens.md),
          ],
        ],
      ),
    );
  }
}
