import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_toc.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_dialog.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_layout.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_view.dart';
import 'package:poemath/features/textbook/widgets/textbook_toc_dialog.dart';

class TextbookReaderPage extends ConsumerStatefulWidget {
  const TextbookReaderPage({
    super.key,
    required this.bookId,
    this.firstPage = false,
    this.initialPage,
    this.viewerBuilder,
  });
  final String bookId;
  final bool firstPage;
  final int? initialPage;
  final TextbookViewerBuilder? viewerBuilder;
  @override
  ConsumerState<TextbookReaderPage> createState() => _TextbookReaderPageState();
}

class _TextbookReaderPageState extends ConsumerState<TextbookReaderPage>
    with WidgetsBindingObserver {
  late final TextbookRepository _repo;
  late final String _profileId;
  Textbook? _book;
  int _page = 1;
  int _initialPage = 1;
  int _viewerRevision = 0;
  Timer? _saveTimer;
  bool _dirty = false;
  bool _saveFailed = false;
  TextbookGoToPage? _goToPage;
  TextbookTocLoader? _toc;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(textbookRepositoryProvider);
    _profileId = ProfileScope.currentId;
    _book = _repo.find(widget.bookId);
    if (_book != null) {
      _page = widget.firstPage
          ? 1
          : (widget.initialPage ??
                  _repo.reading(_profileId, widget.bookId).page)
              .clamp(1, _book!.pageCount);
    }
    _initialPage = _page;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _saveTimer?.cancel();
      unawaited(_save());
    }
  }

  Future<void> _save() async {
    final book = _book;
    if (!_dirty || book == null) return;
    final page = _page;
    _dirty = false;
    try {
      await _repo.savePage(_profileId, book, page);
      if (mounted) setState(() => _saveFailed = false);
    } on Object catch (error, stackTrace) {
      _dirty = true;
      AppLogger.e(
        '阅读位置保存失败',
        tag: 'Textbook',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _saveFailed = true);
    }
  }

  void _pageChanged(int page) {
    if (!mounted || _book == null) return;
    setState(() => _page = page.clamp(1, _book!.pageCount));
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer =
        Timer(const Duration(milliseconds: 350), () => unawaited(_save()));
  }

  Future<void> _jump() async {
    final page = await showDialog<int>(
      context: context,
      builder: (context) =>
          TextbookPageDialog(page: _page, pageCount: _book!.pageCount),
    );
    if (page != null && mounted) await _navigate(page);
  }

  Future<void> _navigate(int page) async {
    try {
      await _goToPage?.call(page);
    } on Object catch (error) {
      AppLogger.e('PDF 跳页失败', tag: 'Textbook', error: error);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('跳页失败，请重试')));
      }
    }
  }

  Future<void> _showToc() async {
    final toc = _toc;
    if (toc == null) return;
    final page = await showTextbookToc(context: context, load: toc);
    if (page != null && mounted) await _navigate(page);
  }

  void _retry() => setState(() {
        _initialPage = _page;
        _viewerRevision++;
        _goToPage = null;
        _toc = null;
      });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    unawaited(_save());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    if (book == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('原书阅读')),
        body: const Center(child: Text('找不到这本教材，请回书架重新选择。')),
      );
    }
    final layout =
        TextbookPageLayout.forWidth(MediaQuery.sizeOf(context).width);
    final previous = layout.previous(_page, book.pageCount);
    final next = layout.next(_page, book.pageCount);
    final visiblePages =
        layout.pages(layout.spreadIndex(_page), book.pageCount);
    final pageLabel = visiblePages.length == 2
        ? 'PDF 第 ${visiblePages.first}–${visiblePages.last} / ${book.pageCount} 页'
        : 'PDF 第 $_page / ${book.pageCount} 页';
    final pathState = ref.watch(textbookPathProvider(book.pdfSha256));
    final revision = _viewerRevision;
    return Scaffold(
      appBar: AppBar(
        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        leadingWidth: SpacingTokens.minTapTarget * 2,
        leading: Row(
          children: [
            const SizedBox(
              width: SpacingTokens.minTapTarget,
              child: Center(child: BackButton()),
            ),
            SizedBox(
              width: SpacingTokens.minTapTarget,
              child: Center(
                child: IconButton(
                  tooltip: '目录',
                  onPressed: pathState.valueOrNull != null &&
                          _goToPage != null &&
                          _toc != null
                      ? _showToc
                      : null,
                  icon: const Icon(Icons.toc_rounded),
                ),
              ),
            ),
          ],
        ),
      ),
      body: pathState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: TextButton(
            onPressed: () =>
                ref.invalidate(textbookPathProvider(book.pdfSha256)),
            child: const Text('文件检查失败，点击重试'),
          ),
        ),
        data: (path) {
          if (path == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(SpacingTokens.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '本地 PDF 已移除或丢失，请重新下载或导入。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: SpacingTokens.sm),
                    TextButton(
                      onPressed: () => context
                          .push(AppRoutes.textbookDetailOf(book.pdfSha256)),
                      child: const Text('查看教材详情'),
                    ),
                  ],
                ),
              ),
            );
          }
          final options = TextbookViewerOptions(
            path: path,
            contentCache:
                ref.read(textbookFileServiceProvider).contentCache(book),
            initialPage: _initialPage,
            onPageChanged: _pageChanged,
            onReady: (goTo) {
              if (mounted && revision == _viewerRevision) {
                setState(() => _goToPage = goTo);
              }
            },
            onTocReady: (toc) {
              if (mounted && revision == _viewerRevision) {
                setState(() => _toc = toc);
              }
            },
            onRetry: _retry,
            doublePage: layout.doublePage,
          );
          return KeyedSubtree(
            key: ValueKey(_viewerRevision),
            child: widget.viewerBuilder?.call(context, options) ??
                TextbookPdfView(options: options),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SpacingTokens.sm,
            vertical: SpacingTokens.xs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_saveFailed)
                Row(
                  children: [
                    const Expanded(child: Text('阅读位置保存失败')),
                    TextButton(onPressed: _save, child: const Text('重试保存')),
                  ],
                ),
              Row(
                children: [
                  IconButton(
                    tooltip: '上一页',
                    onPressed: _goToPage != null && previous != null
                        ? () => _navigate(previous)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: _goToPage == null ? null : _jump,
                      child: Text(pageLabel),
                    ),
                  ),
                  IconButton(
                    tooltip: '下一页',
                    onPressed: _goToPage != null && next != null
                        ? () => _navigate(next)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
