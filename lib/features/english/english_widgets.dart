import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/data/models/math_textbook_course.dart'
    show MathTextbookRegion;
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/features/english/english_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_source_preview.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_preview.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_view.dart';

void englishMessage(BuildContext context, Object error) {
  if (!context.mounted) return;
  final message = error is FormatException
      ? error.message.toString()
      : error is StateError
      ? error.message
      : '暂时没有完成，请重试';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Widget englishHeading(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
  child: Text(text, style: Theme.of(context).textTheme.titleMedium),
);

typedef EnglishReviewPageImageBuilder = Widget Function(
  Textbook book,
  int page,
);

final englishReviewPageImageBuilderProvider =
    Provider<EnglishReviewPageImageBuilder>(
      (ref) =>
          (book, page) => EnglishSourceImage(
            book: book,
            source: EnglishSource(page),
            expandToWidth: true,
            framed: false,
          ),
    );

class EnglishCourseBody extends ConsumerWidget {
  const EnglishCourseBody({
    super.key,
    required this.bookId,
    required this.builder,
  });
  final String bookId;
  final Widget Function(Textbook, EnglishCourse) builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(englishBookProvider(bookId));
    if (book == null) {
      return const AppEmptyState(
        icon: Icons.menu_book_outlined,
        title: '这本英语课本不在书架中',
        description: '重新添加同版本课本，学习记录仍保留。',
      );
    }
    return ref
        .watch(englishCourseProvider(bookId))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AppEmptyState(
            icon: Icons.refresh,
            title: '课程暂时无法读取',
            description: '请重试，学习记录仍保留。',
            actions: [
              TextButton(
                onPressed: () => ref.invalidate(englishCourseProvider(bookId)),
                child: const Text('重新读取'),
              ),
            ],
          ),
          data: (course) => course == null
              ? AppEmptyState(
                  icon: Icons.auto_stories_outlined,
                  title: '先请家长整理这本课本',
                  description: '家长整理并核对后即可开始学习。',
                  actions: [
                    FilledButton(
                      onPressed: () => context.push(
                        AppRoutes.englishBookOf(bookId, review: true),
                      ),
                      child: const Text('家长整理与审核'),
                    ),
                  ],
                )
              : builder(book, course),
        );
  }
}

/// 仅在展示边界适配现有通用 PDF 区域渲染器，英语课程不依赖数学领域模型。
class EnglishSourceImage extends StatelessWidget {
  const EnglishSourceImage({
    super.key,
    required this.book,
    required this.source,
    this.expandToWidth = false,
    this.framed = true,
  });
  final Textbook book;
  final EnglishSource source;
  final bool expandToWidth;
  final bool framed;
  @override
  Widget build(BuildContext context) => MathTextbookSourcePreview(
    book: book,
    source: MathTextbookRegion(
      page: source.page,
      left: source.left,
      top: source.top,
      right: source.right,
      bottom: source.bottom,
      printedPage: source.printedPage,
    ),
    expandToWidth: expandToWidth,
    framed: framed,
  );
}

class EnglishSourcePage extends ConsumerStatefulWidget {
  const EnglishSourcePage({
    super.key,
    required this.bookId,
    required this.page,
  });
  final String bookId;
  final int page;
  @override
  ConsumerState<EnglishSourcePage> createState() => _EnglishSourcePageState();
}

class _EnglishSourcePageState extends ConsumerState<EnglishSourcePage> {
  TextbookGoToPage? _go;
  late int _page = widget.page;
  @override
  Widget build(BuildContext context) {
    final book = ref.watch(englishBookProvider(widget.bookId));
    return AppScaffold(
      appBar: AppBar(title: Text('原书 · PDF 第 $_page 页')),
      body: SafeArea(
        top: false,
        child: book == null
            ? const AppEmptyState(
                icon: Icons.menu_book_outlined,
                title: '请先添加同一版本课本',
              )
            : Column(
                children: [
                  Expanded(
                    child: ref
                        .watch(textbookPathProvider(widget.bookId))
                        .when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (_, __) => const AppEmptyState(
                            icon: Icons.error_outline,
                            title: '原书暂时无法读取',
                          ),
                          data: (path) => path == null
                              ? const AppEmptyState(
                                  icon: Icons.menu_book_outlined,
                                  title: '原书文件不在本机',
                                )
                              : ref.watch(textbookPreviewBuilderProvider)(
                                  context,
                                  TextbookViewerOptions(
                                    path: path,
                                    initialPage: widget.page.clamp(
                                      1,
                                      book.pageCount,
                                    ),
                                    contentCache: ref
                                        .read(textbookFileServiceProvider)
                                        .contentCache(book),
                                    onPageChanged: (page) {
                                      if (mounted) setState(() => _page = page);
                                    },
                                    onReady: (go) => _go = go,
                                    onRetry: () => ref.invalidate(
                                      textbookPathProvider(widget.bookId),
                                    ),
                                  ),
                                ),
                        ),
                  ),
                  Wrap(
                    spacing: SpacingTokens.sm,
                    children: [
                      TextButton(
                        onPressed: _page > 1
                            ? () => unawaited(_go?.call(_page - 1))
                            : null,
                        child: const Text('上一页'),
                      ),
                      TextButton(
                        onPressed: _page < book.pageCount
                            ? () => unawaited(_go?.call(_page + 1))
                            : null,
                        child: const Text('下一页'),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
