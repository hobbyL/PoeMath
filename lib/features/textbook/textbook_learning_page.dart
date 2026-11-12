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
import 'package:poemath/features/textbook/widgets/textbook_cover_grid.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_cover.dart';
import 'package:poemath/features/chinese/expression/widgets/content_preparation_actions.dart';

/// 孩子的课本学习入口；全量书目配置继续由设置中的书籍管理负责。
class TextbookLearningPage extends ConsumerStatefulWidget {
  const TextbookLearningPage({
    super.key,
    this.navigationTitle,
    this.navigationToolbarHeight,
  });

  final Widget? navigationTitle;
  final double? navigationToolbarHeight;

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
    final books = ref.watch(currentTextbooksProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: widget.navigationTitle != null,
        title:
            widget.navigationTitle ??
            Text(
              '课本(${books.length})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        toolbarHeight: widget.navigationToolbarHeight,
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: CustomScrollView(
          key: PageStorageKey('textbook-list-$volume'),
          slivers: [
            if (books.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: AppEmptyState(
                  icon: Icons.menu_book_outlined,
                  title: '暂无$volume课本',
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
    return Semantics(
      label: '${book.title}，${book.volumeLabel}，第 $page / ${book.pageCount} 页',
      button: true,
      excludeSemantics: true,
      onTap: () => _open(book),
      child: ColoredCard(
        key: ValueKey('textbook-${book.pdfSha256}'),
        color: theme.colorScheme.primary,
        padding: EdgeInsets.zero,
        onTap: () => _open(book),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
          child: path.when(
            data: (path) => path == null
                ? TextbookCoverPlaceholder(title: title, status: '请家长补齐课本文件')
                : TextbookPdfCover(path: path, title: title),
            loading: () =>
                TextbookCoverPlaceholder(title: title, status: '正在加载'),
            error: (error, stackTrace) =>
                TextbookCoverPlaceholder(title: title, status: '暂时无法读取'),
          ),
        ),
      ),
    );
  }
}
