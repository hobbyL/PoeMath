import 'package:flutter/material.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_content.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_source_preview.dart';

class MathTextbookStudyContent extends StatelessWidget {
  const MathTextbookStudyContent({
    super.key,
    required this.book,
    required this.block,
  });
  final Textbook book;
  final MathTextbookBlock block;
  @override
  Widget build(BuildContext context) => ColoredCard(
    color: Theme.of(context).colorScheme.primary,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (block.spans.isNotEmpty) MathTextbookContent(spans: block.spans),
        if (block.needsSource) ...[
          for (final source in block.sources)
            Padding(
              padding: const EdgeInsets.only(top: SpacingTokens.sm),
              child: MathTextbookSourcePreview(book: book, source: source),
            ),
        ],
        if (block.parentNote.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: SpacingTokens.sm),
            child: Text(block.parentNote),
          ),
      ],
    ),
  );
}

class MathTextbookSourceContentPage extends StatelessWidget {
  const MathTextbookSourceContentPage({
    super.key,
    required this.book,
    required this.title,
    required this.blocks,
  });
  final Textbook book;
  final String title;
  final List<MathTextbookBlock> blocks;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: ListView.builder(
        padding: const EdgeInsets.all(SpacingTokens.md),
        itemCount: blocks.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: SpacingTokens.md),
          child: MathTextbookStudyContent(book: book, block: blocks[index]),
        ),
      ),
    ),
  );
}

String mathTextbookDisplayError(Object error, String fallback) =>
    error is FormatException
    ? error.message.toString()
    : error is StateError
    ? error.message.toString()
    : fallback;
