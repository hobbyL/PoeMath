import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_learning_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_number_label.dart';
import 'package:poemath/features/textbook/widgets/textbook_cover_grid.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_cover.dart';
import 'package:poemath/features/chinese/expression/widgets/content_preparation_actions.dart';

/// 孩子的课本学习入口；全量书目配置继续由设置中的书籍管理负责。
class TextbookLearningPage extends ConsumerStatefulWidget {
  const TextbookLearningPage({
    super.key,
    this.navigationTitle,
    this.navigationToolbarHeight,
    this.centerTitle = false,
    this.subject = TextbookSubject.chinese,
    this.showAppBar = true,
    this.bodySwipeWrapper,
  });

  final Widget? navigationTitle;
  final double? navigationToolbarHeight;
  final bool centerTitle;
  final TextbookSubject subject;
  final bool showAppBar;
  final Widget Function(Widget child)? bodySwipeWrapper;

  @override
  ConsumerState<TextbookLearningPage> createState() =>
      _TextbookLearningPageState();
}

class _TextbookLearningPageState extends ConsumerState<TextbookLearningPage> {
  Future<void> _open(Textbook book) async {
    await context.push(AppRoutes.textbookDetailOf(book.pdfSha256));
    // 阅读页回写续读位置后，返回即更新封面下的页码。
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsRepositoryProvider);
    final volume =
        '${Textbook.gradeLabels[settings.selectedGrade]}'
        '${settings.selectedSemester}册';
    final books = widget.subject == TextbookSubject.chinese
        ? ref.watch(currentTextbooksProvider)
        : ref.watch(subjectTextbooksProvider(widget.subject));
    final body = SafeArea(
      top: false,
      bottom: false,
      child: PineInkSurface(
        scene: PineInkScene.study,
        page: true,
        child: CustomScrollView(
          key: PageStorageKey('textbook-list-${widget.subject.name}-$volume'),
          slivers: [
            if (books.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: AppEmptyState(
                  icon: Icons.menu_book_outlined,
                  title:
                      '暂无$volume${switch (widget.subject) {
                        TextbookSubject.math => '数学',
                        TextbookSubject.english => '英语',
                        _ => '',
                      }}课本',
                  description: '请家长在“设置 → 学习与内容 → 书籍管理”中添加。',
                  actions: const [
                    ContentPreparationActions(
                      managementRoute: AppRoutes.textbookManagement,
                    ),
                  ],
                ),
              )
            else
              TextbookCoverGrid(
                itemCount: books.length,
                itemBuilder: (context, index) => _bookCard(books[index]),
              ),
          ],
        ),
      ),
    );
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              automaticallyImplyLeading: false,
              centerTitle: widget.centerTitle || widget.navigationTitle != null,
              // 与同一学科的工具栏保留相同空间，栏目标签不随工具数量跳动。
              titleSpacing: widget.navigationTitle != null
                  ? SpacingTokens.sm
                  : null,
              leadingWidth: widget.navigationTitle != null
                  ? SpacingTokens.xxl *
                        (widget.subject == TextbookSubject.math ? 2 : 1)
                  : null,
              leading: widget.navigationTitle != null
                  ? const SizedBox.shrink()
                  : null,
              actions: widget.navigationTitle != null
                  ? [
                      SizedBox(
                        width:
                            SpacingTokens.xxl *
                            (widget.subject == TextbookSubject.math ? 1 : 2),
                      ),
                    ]
                  : null,
              title:
                  widget.navigationTitle ??
                  Text(
                    '课本(${books.length})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              toolbarHeight: widget.navigationToolbarHeight,
            )
          : null,
      body: widget.bodySwipeWrapper?.call(body) ?? body,
    );
  }

  Widget _bookCard(Textbook book) {
    final path = ref.watch(textbookPathProvider(book.pdfSha256));
    final page = ref
        .watch(textbookRepositoryProvider)
        .reading(ProfileScope.currentId, book.pdfSha256)
        .page
        .clamp(1, book.pageCount);
    final theme = Theme.of(context);
    final title = '${book.title}\n${book.volumeLabel}';
    final pageLabel = asyncTextbookPageLabel(
      ref.watch(
        textbookPrintedPageProvider((bookId: book.pdfSha256, page: page)),
      ),
    );
    return Semantics(
      label: '${book.title}，${book.volumeLabel}，$pageLabel',
      button: true,
      excludeSemantics: true,
      onTap: () => _open(book),
      child: ColoredCard(
        key: ValueKey('textbook-${book.pdfSha256}'),
        color: theme.colorScheme.primary,
        padding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        onTap: () => _open(book),
        child: path.when(
          data: (path) => path == null
              ? TextbookCoverPlaceholder(title: title, status: '请家长补齐课本文件')
              : TextbookPdfCover(path: path, title: title),
          loading: () => TextbookCoverPlaceholder(title: title, status: '正在加载'),
          error: (error, stackTrace) =>
              TextbookCoverPlaceholder(title: title, status: '暂时无法读取'),
        ),
      ),
    );
  }
}
