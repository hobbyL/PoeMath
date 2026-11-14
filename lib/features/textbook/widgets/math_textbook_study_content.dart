import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/domain/math_textbook_content_organizer.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_content.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_source_preview.dart';

class MathTextbookStudyContent extends StatefulWidget {
  const MathTextbookStudyContent({
    super.key,
    required this.book,
    required this.block,
  });
  final Textbook book;
  final MathTextbookBlock block;
  @override
  State<MathTextbookStudyContent> createState() =>
      _MathTextbookStudyContentState();
}

class _MathTextbookStudyContentState extends State<MathTextbookStudyContent> {
  bool _showText = false;
  MathTextbookBlock get block => widget.block;

  @override
  void didUpdateWidget(MathTextbookStudyContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.id != block.id) _showText = false;
  }

  @override
  Widget build(BuildContext context) => ColoredCard(
    color: Theme.of(context).colorScheme.primary,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (block.kind == MathTextbookBlockKind.example ||
            block.kind == MathTextbookBlockKind.exercise) ...[
          Text(
            mathTextbookSectionTitle(block),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: SpacingTokens.sm),
        ],
        if (!block.sourceLayout && block.spans.isNotEmpty)
          MathTextbookContent(spans: block.spans),
        if (block.needsSource) ...[
          for (final source in block.sources)
            Padding(
              padding: const EdgeInsets.only(top: SpacingTokens.sm),
              child: MathTextbookSourcePreview(
                book: widget.book,
                source: source,
                expandToWidth: true,
                framed: false,
              ),
            ),
        ],
        if (block.sourceLayout && block.spans.isNotEmpty) ...[
          AppTile(
            flat: true,
            iconColor: Theme.of(context).colorScheme.primary,
            title: _showText ? '收起文字' : '查看文字',
            subtitle: '',
            trailingIcon: _showText ? Icons.expand_less : Icons.expand_more,
            onTap: () => setState(() => _showText = !_showText),
          ),
          if (_showText) MathTextbookContent(spans: block.spans),
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
  Widget build(BuildContext context) {
    final reading = mathTextbookReadingBlocks(blocks);
    void openPage(int page) =>
        context.push(AppRoutes.textbookReadOf(book.pdfSha256), extra: page);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: '打开原书',
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: reading.isEmpty
                ? null
                : () => openPage(reading.first.sources.first.page),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView.builder(
          key: PageStorageKey(
            'math-content-${book.pdfSha256}-$title-${reading.firstOrNull?.id}',
          ),
          padding: const EdgeInsets.all(SpacingTokens.md),
          itemCount: reading.length,
          itemBuilder: (context, index) {
            final block = reading[index], source = block.sources.first;
            final newPage =
                index == 0 ||
                reading[index - 1].sources.last.page != source.page;
            return Padding(
              key: ValueKey('math-reading-${block.id}'),
              padding: const EdgeInsets.only(bottom: SpacingTokens.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (newPage)
                    AppTile(
                      flat: true,
                      icon: Icons.menu_book_outlined,
                      iconColor: Theme.of(context).colorScheme.primary,
                      title: source.printedPage == null
                          ? 'PDF 第 ${source.page} 页'
                          : '书本第 ${source.printedPage} 页',
                      subtitle: '打开完整原页',
                      onTap: () => openPage(source.page),
                    ),
                  if (block.kind == MathTextbookBlockKind.heading &&
                      !block.needsSource &&
                      block.parentNote.isEmpty)
                    Semantics(
                      header: true,
                      child: Text(
                        block.text,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    )
                  else
                    MathTextbookStudyContent(book: book, block: block),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

String mathTextbookDisplayError(Object error, String fallback) =>
    error is FormatException
    ? error.message.toString()
    : error is StateError
    ? error.message.toString()
    : fallback;
