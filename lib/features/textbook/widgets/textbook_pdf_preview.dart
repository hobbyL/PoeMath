import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/textbook_toc_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_layout.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_turn.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_view.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_toc.dart';
import 'package:poemath/features/textbook/widgets/textbook_text_search.dart';

final textbookPreviewBuilderProvider = Provider<TextbookViewerBuilder>(
  (ref) => (context, options) => TextbookPdfPreview(options: options),
);

/// 单页/对开预览的 PDF 生命周期和页码转换只在此适配层处理。
class TextbookPdfPreview extends StatefulWidget {
  const TextbookPdfPreview({super.key, required this.options});

  final TextbookViewerOptions options;

  @override
  State<TextbookPdfPreview> createState() => _TextbookPdfPreviewState();
}

class _TextbookPdfPreviewState extends State<TextbookPdfPreview> {
  late final _documentRef = PdfDocumentRefFile(
    widget.options.path,
    autoDispose: true,
    useProgressiveLoading: true,
  );
  late int _page = widget.options.initialPage;
  int? _navigationTarget;
  TextbookPageLayout get _layout =>
      TextbookPageLayout(doublePage: widget.options.doublePage);
  late PageController _controller = PageController(
    initialPage: _layout.spreadIndex(_page),
  );
  PdfDocument? _readyDocument;
  PdfDocument? _tocDocument;
  TextbookTocService? _toc;

  @override
  void didUpdateWidget(covariant TextbookPdfPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.doublePage != widget.options.doublePage) {
      final oldController = _controller;
      // 动画中可能已上报展开页左页；切换模式仍须定位用户指定的右页。
      _page = _navigationTarget ?? _page;
      _controller = PageController(initialPage: _layout.spreadIndex(_page));
      _readyDocument = null;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => oldController.dispose());
    }
  }

  void _ready(PdfDocument document) {
    if (identical(_readyDocument, document)) return;
    _readyDocument = document;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(_readyDocument, document) ||
          !_controller.hasClients) {
        return;
      }
      final page = _page.clamp(1, document.pages.length);
      _page = page;
      _controller.jumpToPage(_layout.spreadIndex(page));
      widget.options.onPageChanged(page);
      if (!identical(_tocDocument, document)) {
        _tocDocument = document;
        _toc = textbookPdfTocService(
          document,
          isAvailable: () => mounted && identical(_tocDocument, document),
          cache: widget.options.contentCache,
        );
      }
      final toc = _toc!;
      widget.options.onTocReady?.call(
        (refresh) => toc.scan(refresh: refresh),
      );
      widget.options.onSearchReady?.call(
        (query) => searchTextbookPages(
          query: query,
          pageCount: document.pages.length,
          loadPageText: (number) {
            Future<String> load() async {
              if (!mounted || !identical(_readyDocument, document)) {
                throw StateError('Preview is no longer available');
              }
              final page = await document.pages[number - 1].waitForLoaded(
                timeout: const Duration(seconds: 15),
              );
              if (page == null) throw StateError('PDF page loading timed out');
              final text = (await page.loadText())?.fullText ?? '';
              if (!mounted || !identical(_readyDocument, document)) {
                throw StateError('Preview is no longer available');
              }
              return text;
            }

            return widget.options.contentCache?.pageText(number, load) ??
                load();
          },
        ),
      );
      widget.options.onReady((page) async {
        if (!mounted || !_controller.hasClients) return;
        final target = page.clamp(1, document.pages.length);
        final controller = _controller;
        final index = _layout.spreadIndex(target);
        _navigationTarget = target;
        try {
          if (MediaQuery.disableAnimationsOf(context)) {
            controller.jumpToPage(index);
          } else {
            await controller.animateToPage(
              index,
              duration: textbookPageTurnDuration,
              curve: Curves.easeInOutCubic,
            );
          }
          if (mounted && identical(controller, _controller)) {
            _page = target;
            widget.options.onPageChanged(_page);
          }
        } finally {
          _navigationTarget = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PdfDocumentViewBuilder(
        documentRef: _documentRef,
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (context, _, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('书籍暂时无法打开', textAlign: TextAlign.center),
                const SizedBox(height: SpacingTokens.sm),
                TextButton(
                  onPressed: widget.options.onRetry,
                  child: const Text('重新打开'),
                ),
              ],
            ),
          ),
        ),
        builder: (context, document) {
          if (document == null || document.pages.isEmpty) {
            return const SizedBox.shrink();
          }
          _ready(document);
          return PageView.builder(
            controller: _controller,
            key: ValueKey(widget.options.doublePage),
            // 保留并提前渲染前后两屏，避免开始翻页才创建下一页位图。
            allowImplicitScrolling: true,
            scrollCacheExtent: const ScrollCacheExtent.viewport(2),
            itemCount: _layout.spreadCount(document.pages.length),
            onPageChanged: (index) {
              if (index != _layout.spreadIndex(_page)) {
                _page = _layout.firstPage(index);
              }
              widget.options.onPageChanged(_page);
            },
            itemBuilder: (context, index) {
              final pages = _layout.pages(index, document.pages.length);
              return TextbookPageTurn(
                controller: _controller,
                index: index,
                doublePage: widget.options.doublePage,
                child: !widget.options.doublePage || pages.first == 1
                    ? _pageView(document, pages.first)
                    : Row(
                        children: [
                          Expanded(
                            child: _pageView(document, pages.first, end: 0.5),
                          ),
                          const SizedBox(width: SpacingTokens.xs),
                          Expanded(
                            child: pages.length == 2
                                ? _pageView(document, pages.last, start: 0.5)
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
              );
            },
          );
        },
      );

  Widget _pageView(
    PdfDocument document,
    int number, {
    double start = 0,
    double end = 1,
  }) =>
      Semantics(
        label: 'PDF 第 $number 页',
        image: true,
        child: PdfPageView(
          document: document,
          pageNumber: number,
          decorationBuilder: (context, _, __, pageImage) => Center(
            child: pageImage != null
                ? TextbookCurlPageImage(
                    image: pageImage,
                    start: start,
                    end: end,
                    gutter: end - start < 1 ? SpacingTokens.xs : 0,
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      );
}
