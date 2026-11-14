import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_textbook_session_context.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_content.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_study_content.dart';

class MathTextbookRecordPage extends ConsumerWidget {
  const MathTextbookRecordPage({super.key, required this.snapshot});
  final MathTextbookSessionContext snapshot;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref
        .watch(textbookLocalListProvider)
        .where((book) => book.pdfSha256 == snapshot.bookId)
        .firstOrNull;
    final item = snapshot.item;
    return Scaffold(
      appBar: AppBar(title: const Text('教材作答快照')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SpacingTokens.md),
          children: [
            Text(
              item.exercise.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(snapshot.bookTitle),
            Text(snapshot.correct ? '自动核对通过' : '自动核对未通过'),
            const Text('这里保留的是当时的题目、规则和作答。'),
            if (book == null) const Text('原书已移除或未下载，图形需重新添加同一 PDF 后查看。'),
            const SizedBox(height: SpacingTokens.md),
            for (final block in item.blocks)
              Padding(
                padding: const EdgeInsets.only(bottom: SpacingTokens.md),
                child: book != null
                    ? MathTextbookStudyContent(book: book, block: block)
                    : ColoredCard(
                        color: Theme.of(context).colorScheme.primary,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            MathTextbookContent(spans: block.spans),
                            if (block.needsSource)
                              Text(
                                '原书来源：PDF 第 ${block.sources.map((source) => source.page).toSet().join('、')} 页',
                              ),
                          ],
                        ),
                      ),
              ),
            if (item.exercise.note.isNotEmpty) Text(item.exercise.note),
            for (final field in item.exercise.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
                child: ColoredCard(
                  color: Theme.of(context).colorScheme.primary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(field.label),
                      Text('你的作答：${snapshot.answers[field.id]}'),
                      Text(
                        '参考答案：${field.rule.correctChoices.isNotEmpty ? field.rule.correctChoices.join('、') : '${field.rule.expected}${field.rule.unit}'}',
                      ),
                      if (field.rule.reference.isNotEmpty)
                        Text(field.rule.reference),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
