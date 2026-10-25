import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_toc.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/domain/textbook_lesson_content.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_dialog.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_layout.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_cover.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_preview.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_view.dart';
import 'package:poemath/features/textbook/widgets/textbook_search_dialog.dart';
import 'package:poemath/features/textbook/widgets/textbook_text_search.dart';
import 'package:poemath/features/textbook/widgets/textbook_toc_dialog.dart';

class TextbookDetailPage extends ConsumerStatefulWidget {
  const TextbookDetailPage({
    super.key,
    required this.bookId,
    this.manage = false,
    this.previewBuilder,
  });
  final String bookId;
  final bool manage;
  final TextbookViewerBuilder? previewBuilder;
  @override
  ConsumerState<TextbookDetailPage> createState() => _TextbookDetailPageState();
}

class _TextbookDetailPageState extends ConsumerState<TextbookDetailPage> {
  bool _busy = false;
  bool _previewVisible = true;
  bool _turning = false;
  int _previewPage = 1;
  int _previewRevision = 0;
  TextbookGoToPage? _goToPage;
  TextbookSearch? _search;
  TextbookTocLoader? _toc;

  Future<void> _remove(Textbook book) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除本地 PDF？'),
        content: const Text('书目、核对状态和阅读位置会保留。重新下载或导入同一文件后，可以继续阅读。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除 PDF'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      setState(() {
        _previewVisible = false;
        _goToPage = null;
        _search = null;
        _toc = null;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await ref.read(textbookFileServiceProvider).removePdf(book.pdfSha256);
      if (!mounted) return;
      ref.invalidate(textbookPathProvider(book.pdfSha256));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已移除本地 PDF，阅读位置已保留')));
    } on Object catch (error) {
      AppLogger.e('教材移除失败', tag: 'Textbook', error: error);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('本地 PDF 移除失败，请重试')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _previewVisible = true;
          _previewRevision++;
        });
      }
    }
  }

  Future<void> _read() => _openRoute(
        AppRoutes.textbookReadOf(widget.bookId),
        extra: _previewPage,
      );

  Future<void> _review() => _openRoute(
        AppRoutes.textbookReviewOf(widget.bookId),
        suspendPreview: false,
      );

  Future<void> _showContent(TextbookContentSection section, List<int> pages) =>
      _openRoute(
        AppRoutes.textbookContentOf(widget.bookId, section.name, pages),
        suspendPreview: false,
      );

  Future<void> _openRoute(
    String route, {
    Object? extra,
    bool suspendPreview = true,
  }) async {
    if (suspendPreview) {
      setState(() {
        _previewVisible = false;
        _goToPage = null;
        _search = null;
        _toc = null;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    try {
      await context.push(route, extra: extra);
    } finally {
      if (suspendPreview && mounted) {
        setState(() {
          _previewVisible = true;
          _previewRevision++;
        });
      }
    }
  }

  Future<void> _turnPage(int page, int pageCount) async {
    final goToPage = _goToPage;
    if (_turning || goToPage == null || page < 1 || page > pageCount) return;
    setState(() => _turning = true);
    try {
      await goToPage(page);
    } on Object catch (error) {
      AppLogger.e('预览翻页失败', tag: 'Textbook', error: error);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('翻页失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _turning = false);
    }
  }

  Future<void> _jumpToPage(Textbook book) async {
    final page = await showDialog<int>(
      context: context,
      builder: (_) => TextbookPageDialog(
        page: _previewPage,
        pageCount: book.pageCount,
      ),
    );
    if (page != null && mounted) await _turnPage(page, book.pageCount);
  }

  Future<void> _searchBook(Textbook book) async {
    final search = _search;
    if (search == null) return;
    final page = await showDialog<int>(
      context: context,
      builder: (_) => TextbookSearchDialog(
        pageCount: book.pageCount,
        search: search,
      ),
    );
    if (page != null && mounted) await _turnPage(page, book.pageCount);
  }

  void _retryPreview() => setState(() {
        _goToPage = null;
        _search = null;
        _toc = null;
        _previewRevision++;
      });

  Future<void> _showToc(Textbook book) async {
    final toc = _toc;
    if (toc == null) return;
    final page = await showTextbookToc(context: context, load: toc);
    if (page != null && mounted) await _turnPage(page, book.pageCount);
  }

  Widget _detailScaffold({
    required Widget body,
    Widget? bottomNavigationBar,
    bool showRemove = false,
    VoidCallback? onRemove,
    VoidCallback? onToc,
    VoidCallback? onReview,
  }) {
    final colors = Theme.of(context).colorScheme;
    final buttonStyle = IconButton.styleFrom(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = TextbookPageLayout.forWidth(
          constraints.maxWidth - MediaQuery.paddingOf(context).horizontal,
        );
        Widget removeButton({ButtonStyle? style}) => IconButton(
              tooltip: '移除本地 PDF',
              style: style,
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
            );
        Widget tocButton({ButtonStyle? style}) => IconButton(
              tooltip: '目录',
              style: style,
              onPressed: onToc,
              icon: const Icon(Icons.toc_rounded),
            );
        Widget reviewButton({ButtonStyle? style}) => IconButton(
              tooltip: '内容审核',
              style: style,
              onPressed: onReview,
              icon: const Icon(Icons.fact_check_outlined),
            );
        return Scaffold(
          bottomNavigationBar: bottomNavigationBar,
          appBar: layout.doublePage
              ? null
              : AppBar(
                  leadingWidth:
                      showRemove ? SpacingTokens.minTapTarget * 2 : null,
                  leading: showRemove
                      ? Row(
                          children: [
                            const SizedBox(
                              width: SpacingTokens.minTapTarget,
                              child: Center(child: BackButton()),
                            ),
                            SizedBox(
                              width: SpacingTokens.minTapTarget,
                              child: Center(child: tocButton()),
                            ),
                          ],
                        )
                      : const BackButton(),
                  title: const Text('教材详情'),
                  actions: [
                    if (onReview != null) reviewButton(),
                    if (showRemove) removeButton(),
                  ],
                ),
          body: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                body,
                if (layout.doublePage)
                  PositionedDirectional(
                    top: 0,
                    start: 0,
                    end: 0,
                    height: kToolbarHeight,
                    child: Row(
                      children: [
                        SizedBox(
                          width: SpacingTokens.minTapTarget,
                          child: Center(child: BackButton(style: buttonStyle)),
                        ),
                        if (showRemove)
                          SizedBox(
                            width: SpacingTokens.minTapTarget,
                            child: Center(child: tocButton(style: buttonStyle)),
                          ),
                        const Spacer(),
                        if (onReview != null) reviewButton(style: buttonStyle),
                        if (showRemove) removeButton(style: buttonStyle),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _preview(String path, Textbook book, TextbookPageLayout layout) {
    final revision = _previewRevision;
    final options = TextbookViewerOptions(
      path: path,
      contentCache: ref.read(textbookFileServiceProvider).contentCache(book),
      initialPage: _previewPage.clamp(1, book.pageCount),
      onPageChanged: (page) {
        if (mounted && _previewVisible && revision == _previewRevision) {
          setState(() => _previewPage = page.clamp(1, book.pageCount));
        }
      },
      onReady: (goToPage) {
        if (mounted && _previewVisible && revision == _previewRevision) {
          setState(() => _goToPage = goToPage);
        }
      },
      onSearchReady: (search) {
        if (mounted && _previewVisible && revision == _previewRevision) {
          setState(() => _search = search);
        }
      },
      onTocReady: (toc) {
        if (mounted && _previewVisible && revision == _previewRevision) {
          setState(() => _toc = toc);
        }
      },
      onRetry: _retryPreview,
      doublePage: layout.doublePage,
    );
    return KeyedSubtree(
      key: ValueKey('$path:$revision'),
      child: widget.previewBuilder?.call(context, options) ??
          ref.watch(textbookPreviewBuilderProvider)(context, options),
    );
  }

  Widget _pageControls(
    Textbook book, {
    required bool available,
  }) =>
      SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final layout = TextbookPageLayout.forWidth(constraints.maxWidth);
            final previous = layout.previous(_previewPage, book.pageCount);
            final next = layout.next(_previewPage, book.pageCount);
            final pages = layout.pages(
              layout.spreadIndex(_previewPage),
              book.pageCount,
            );
            final pageLabel = pages.length == 2
                ? '${pages.first}–${pages.last} / ${book.pageCount}'
                : '$_previewPage / ${book.pageCount}';
            final canNavigate = available &&
                !_busy &&
                !_turning &&
                _previewVisible &&
                _goToPage != null;
            final maxWidth = layout.doublePage
                ? ResponsiveLayout.wideBreakpoint
                : ResponsiveLayout.mediumBreakpoint;
            final padding = const EdgeInsets.symmetric(
              horizontal: SpacingTokens.xs,
              vertical: SpacingTokens.sm,
            );
            final previousButton = TextButton.icon(
              onPressed: canNavigate && previous != null
                  ? () => _turnPage(previous, book.pageCount)
                  : null,
              style: TextButton.styleFrom(padding: padding),
              icon: const Icon(Icons.chevron_left),
              label: const Text('上一页', textAlign: TextAlign.center),
            );
            final pageButton = Tooltip(
              message: '输入页码跳转',
              child: TextButton(
                key: const ValueKey('textbook-detail-page-number'),
                onPressed: canNavigate ? () => _jumpToPage(book) : null,
                style: TextButton.styleFrom(padding: padding),
                child: Text(pageLabel, textAlign: TextAlign.center),
              ),
            );
            final searchButton = SizedBox(
              width: SpacingTokens.minTapTarget,
              child: IconButton(
                tooltip: '搜索本书',
                onPressed: canNavigate && _search != null
                    ? () => _searchBook(book)
                    : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: SpacingTokens.minTapTarget,
                  minHeight: SpacingTokens.minTapTarget,
                ),
                icon: const Icon(Icons.search),
              ),
            );
            final nextButton = TextButton.icon(
              onPressed: canNavigate && next != null
                  ? () => _turnPage(next, book.pageCount)
                  : null,
              style: TextButton.styleFrom(padding: padding),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.chevron_right),
              label: const Text('下一页', textAlign: TextAlign.center),
            );
            final onRead = available && !_busy && !_turning && _previewVisible
                ? _read
                : null;
            final readButton = layout.doublePage
                ? FilledButton.icon(
                    key: const ValueKey('textbook-detail-read'),
                    onPressed: onRead,
                    style: FilledButton.styleFrom(padding: padding),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('原书阅读', textAlign: TextAlign.center),
                  )
                : SizedBox(
                    width: SpacingTokens.minTapTarget,
                    child: IconButton(
                      key: const ValueKey('textbook-detail-read'),
                      tooltip: '原书阅读',
                      onPressed: onRead,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: SpacingTokens.minTapTarget,
                        minHeight: SpacingTokens.minTapTarget,
                      ),
                      icon: const Icon(Icons.menu_book_outlined),
                    ),
                  );
            final glyph = TextPainter(
              text: TextSpan(
                text: '页',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final minCell = glyph.width +
                (IconTheme.of(context).size ?? SpacingTokens.lg) +
                SpacingTokens.sm +
                SpacingTokens.xs * 2;
            glyph.dispose();
            final controlsWidth = math.min(
              constraints.maxWidth - SpacingTokens.md * 2,
              maxWidth,
            );
            final wrapRead = controlsWidth <
                minCell * (layout.doublePage ? 4 : 3) +
                    SpacingTokens.minTapTarget * (layout.doublePage ? 1 : 2) +
                    SpacingTokens.xs * 4;
            final controls = IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: previousButton),
                  const SizedBox(width: SpacingTokens.xs),
                  Expanded(child: pageButton),
                  const SizedBox(width: SpacingTokens.xs),
                  searchButton,
                  const SizedBox(width: SpacingTokens.xs),
                  Expanded(child: nextButton),
                  if (!wrapRead) ...[
                    const SizedBox(width: SpacingTokens.xs),
                    if (layout.doublePage)
                      Expanded(child: readButton)
                    else
                      readButton,
                  ],
                ],
              ),
            );
            return Padding(
              padding: const EdgeInsets.only(
                left: SpacingTokens.md,
                top: SpacingTokens.md,
                right: SpacingTokens.md,
              ),
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  key: const ValueKey('textbook-detail-controls'),
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      controls,
                      if (wrapRead) ...[
                        const SizedBox(height: SpacingTokens.xs),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: readButton,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );

  Widget _contentActions(
    List<int> pages,
    AsyncValue<TextbookCoursePack?> course,
  ) {
    final pack = course.valueOrNull;
    final lessons = pack == null
        ? const <TextbookCourseLesson>[]
        : textbookLessonsForPages(pack, pages);
    final sections = [
      for (final section in TextbookContentSection.values)
        if (lessons.any((lesson) => section.targets(lesson).isNotEmpty))
          section,
    ];
    final enabled = !_busy && !_turning && _previewVisible;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (course.hasError)
          TextButton(
            onPressed: () =>
                ref.invalidate(textbookCourseProvider(widget.bookId)),
            child: const Text('课文内容加载失败，点击重试'),
          )
        else if (lessons.isEmpty && (course.isLoading || pack == null))
          Text(
            course.isLoading ? '正在加载课文内容…' : '本书尚未整理课文内容',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        if (sections.isNotEmpty)
          Wrap(
            key: const ValueKey('textbook-content-actions'),
            alignment: WrapAlignment.center,
            spacing: SpacingTokens.xs,
            runSpacing: SpacingTokens.xs,
            children: [
              for (final section in sections)
                TextButton(
                  onPressed:
                      enabled ? () => _showContent(section, pages) : null,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(
                      SpacingTokens.minTapTarget,
                      SpacingTokens.minTapTarget,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpacingTokens.sm,
                      vertical: SpacingTokens.sm,
                    ),
                  ),
                  child: Text(section.label, textAlign: TextAlign.center),
                ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = ref
        .watch(textbookListProvider)
        .where((b) => b.pdfSha256 == widget.bookId)
        .firstOrNull;
    final catalog = ref.watch(textbookCatalogProvider);
    final entry = catalog.valueOrNull
        ?.where((value) => value.book.pdfSha256 == widget.bookId)
        .firstOrNull;
    if (book == null) {
      return _detailScaffold(
        body: catalog.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const Center(child: Text('找不到这本教材，请返回书架重新选择。')),
      );
    }
    final path = ref.watch(textbookPathProvider(book.pdfSha256));
    final available = path.valueOrNull != null;
    final course = ref.watch(textbookCourseProvider(book.pdfSha256));
    final download = ref.watch(textbookDownloadsProvider)[book.pdfSha256];
    final downloading = download?.active == true;
    return _detailScaffold(
      bottomNavigationBar: _pageControls(book, available: available),
      showRemove: available,
      onReview: !_busy && !_turning && _previewVisible ? _review : null,
      onRemove: _busy || downloading ? null : () => _remove(book),
      onToc: available &&
              !_busy &&
              !_turning &&
              _previewVisible &&
              _goToPage != null &&
              _toc != null
          ? () => _showToc(book)
          : null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layout = TextbookPageLayout.forWidth(constraints.maxWidth);
          final pages = layout.pages(
            layout.spreadIndex(_previewPage),
            book.pageCount,
          );
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: LayoutBuilder(
                  key: const ValueKey('textbook-detail-preview-area'),
                  builder: (context, constraints) {
                    final maxWidth = layout.doublePage
                        ? ResponsiveLayout.wideBreakpoint
                        : ResponsiveLayout.mediumBreakpoint;
                    final innerHeight = math.max(
                      0.0,
                      constraints.maxHeight - SpacingTokens.md * 2,
                    );
                    final cardWidth = math.min(
                      constraints.maxWidth - SpacingTokens.md * 2,
                      math.min(
                        maxWidth,
                        // 缺文件时卡片随正文滚动，保留占位图和提示的可用高度。
                        (available
                                ? innerHeight
                                : math.max(
                                    innerHeight,
                                    SpacingTokens.minTapTarget * 3,
                                  )) *
                            layout.aspectRatio,
                      ),
                    );
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(SpacingTokens.md),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Center(
                            child: SizedBox(
                              width: cardWidth,
                              child: AspectRatio(
                                aspectRatio: layout.aspectRatio,
                                child: ColoredCard(
                                  key: const ValueKey(
                                    'textbook-detail-preview-card',
                                  ),
                                  color: theme.colorScheme.primary,
                                  padding: EdgeInsets.zero,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      SpacingTokens.radiusMedium,
                                    ),
                                    child: available
                                        ? _previewVisible
                                            ? _preview(
                                                path.requireValue!,
                                                book,
                                                layout,
                                              )
                                            : const SizedBox.shrink()
                                        : entry?.coverAsset != null
                                            ? Image.asset(
                                                entry!.coverAsset!,
                                                fit: BoxFit.contain,
                                                errorBuilder: (_, __, ___) =>
                                                    TextbookCoverPlaceholder(
                                                  title: book.title,
                                                  status: '下载后可翻页查看',
                                                ),
                                              )
                                            : TextbookCoverPlaceholder(
                                                title: book.title,
                                                status: path.isLoading
                                                    ? '正在检查本地文件'
                                                    : '本地 PDF 暂不可用',
                                              ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (!available)
                            const SizedBox(height: SpacingTokens.md),
                          if (!available && download != null) ...[
                            Text(download.label),
                            if (downloading) ...[
                              const SizedBox(height: SpacingTokens.sm),
                              LinearProgressIndicator(value: download.progress),
                              TextButton(
                                onPressed: () => ref
                                    .read(textbookDownloadsProvider.notifier)
                                    .cancel(book.pdfSha256),
                                child: const Text('取消下载'),
                              ),
                            ],
                            const SizedBox(height: SpacingTokens.md),
                          ],
                          if (!available && entry != null && !path.isLoading)
                            FilledButton.icon(
                              onPressed: downloading
                                  ? null
                                  : () => ref
                                      .read(textbookDownloadsProvider.notifier)
                                      .download(entry),
                              icon: const Icon(Icons.download_outlined),
                              label: Text(download != null ? '重新下载教材' : '下载教材'),
                            ),
                          if (!available)
                            path.when(
                              data: (_) => entry != null
                                  ? const Text('下载完成后可离线阅读，同版重新下载会恢复阅读位置。')
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '本地 PDF 已移除或丢失。请到书籍管理重新导入同一文件，恢复阅读。',
                                        ),
                                        TextButton(
                                          onPressed: () => context.push(
                                            AppRoutes.textbookManagement,
                                          ),
                                          child: const Text('打开书籍管理'),
                                        ),
                                      ],
                                    ),
                              loading: () => const LinearProgressIndicator(),
                              error: (_, __) => Column(
                                children: [
                                  const Text('无法检查本地文件'),
                                  TextButton(
                                    onPressed: () => ref.invalidate(
                                      textbookPathProvider(book.pdfSha256),
                                    ),
                                    child: const Text('重新检查'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SpacingTokens.md,
                ),
                child: _contentActions(pages, course),
              ),
            ],
          );
        },
      ),
    );
  }
}
