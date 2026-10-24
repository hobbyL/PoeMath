import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/data/models/textbook_toc.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_layout.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_toc.dart';
import 'package:poemath/features/textbook/widgets/textbook_text_search.dart';

typedef TextbookGoToPage = Future<void> Function(int page);
typedef TextbookViewerBuilder = Widget Function(
  BuildContext context,
  TextbookViewerOptions options,
);

class TextbookViewerOptions {
  const TextbookViewerOptions({
    required this.path,
    required this.initialPage,
    required this.onPageChanged,
    required this.onReady,
    required this.onRetry,
    this.doublePage = false,
    this.onSearchReady,
    this.onTocReady,
    this.contentCache,
  });
  final String path;
  final int initialPage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<TextbookGoToPage> onReady;
  final VoidCallback onRetry;
  final bool doublePage;
  final ValueChanged<TextbookSearch>? onSearchReady;
  final ValueChanged<TextbookTocLoader>? onTocReady;
  final TextbookContentCache? contentCache;
}

/// PDF 库只在此适配层出现，页面/测试可注入其他渲染器。
class TextbookPdfView extends StatefulWidget {
  const TextbookPdfView({super.key, required this.options});
  final TextbookViewerOptions options;
  @override
  State<TextbookPdfView> createState() => _TextbookPdfViewState();
}

class _TextbookPdfViewState extends State<TextbookPdfView> {
  final _controller = PdfViewerController();
  late final _documentRef = PdfDocumentRefFile(widget.options.path);
  late int _page = widget.options.initialPage;
  bool _changingLayout = false;
  bool _viewerReady = false;
  bool _navigating = false;

  Rect _spreadRect(int page) {
    final layout = TextbookPageLayout(doublePage: widget.options.doublePage);
    final rects = _controller.layout.pageLayouts;
    final numbers = layout.pages(layout.spreadIndex(page), rects.length);
    return numbers.map((number) => rects[number - 1]).reduce(
          (left, right) => left.expandToInclude(right),
        );
  }

  Future<void> _goToPage(int page, {bool animate = true}) async {
    if (!mounted || !_controller.isReady || _navigating) return;
    final target = page.clamp(1, _controller.pageCount);
    _page = target;
    _navigating = true;
    final duration = !animate || MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    try {
      if (widget.options.doublePage) {
        await _controller.goToArea(
          rect: _spreadRect(target),
          anchor: PdfPageAnchor.all,
          duration: duration,
        );
      } else {
        await _controller.goToPage(pageNumber: target, duration: duration);
      }
      if (mounted) {
        _page = target;
        widget.options.onPageChanged(target);
      }
    } finally {
      _navigating = false;
    }
  }

  @override
  void didUpdateWidget(covariant TextbookPdfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.doublePage != widget.options.doublePage) {
      final page = _page;
      _changingLayout = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || !_controller.isReady) return;
        _controller.invalidate();
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) {
          await _goToPage(page, animate: false);
          _changingLayout = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => PdfViewer(
        _documentRef,
        controller: _controller,
        initialPageNumber: widget.options.initialPage,
        params: PdfViewerParams(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          layoutPages: widget.options.doublePage ? textbookFacingPages : null,
          horizontalCacheExtent: 1,
          verticalCacheExtent: 2,
          maxImageBytesCachedOnMemory: 64 * 1024 * 1024,
          sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(
            calculateInitialZoom: (_, controller, fitScale, coverScale) {
              if (!widget.options.doublePage) return coverScale;
              final rect = _spreadRect(_page);
              return math.min(
                controller.viewSize.width / (rect.width + SpacingTokens.md),
                controller.viewSize.height / (rect.height + SpacingTokens.md),
              );
            },
          ),
          calculateCurrentPageNumber: widget.options.doublePage
              ? (visible, rects, _) {
                  if (!_viewerReady || _changingLayout || _navigating) {
                    return _page;
                  }
                  var bestPage = 1;
                  var bestArea = 0.0;
                  const layout = TextbookPageLayout(doublePage: true);
                  for (var index = 0;
                      index < layout.spreadCount(rects.length);
                      index++) {
                    var area = 0.0;
                    for (final number in layout.pages(index, rects.length)) {
                      final intersection = visible.intersect(rects[number - 1]);
                      if (!intersection.isEmpty) {
                        area += intersection.width * intersection.height;
                      }
                    }
                    if (area > bestArea) {
                      bestArea = area;
                      bestPage = layout.firstPage(index);
                    }
                  }
                  return layout.spreadIndex(bestPage) ==
                          layout.spreadIndex(_page)
                      ? _page
                      : layout.firstPage(layout.spreadIndex(bestPage));
                }
              : null,
          onViewerReady: (document, _) async {
            final page = widget.options.initialPage;
            if (widget.options.doublePage) {
              await _goToPage(page, animate: false);
            }
            _changingLayout = false;
            _viewerReady = true;
            if (mounted) {
              final toc = textbookPdfTocService(
                document,
                isAvailable: () => mounted,
                cache: widget.options.contentCache,
              );
              widget.options.onTocReady?.call(
                (refresh) => toc.scan(refresh: refresh),
              );
              widget.options.onReady(_goToPage);
            }
          },
          onPageChanged: (page) {
            if (page != null &&
                _viewerReady &&
                !_changingLayout &&
                !_navigating) {
              _page = page;
              widget.options.onPageChanged(page);
            }
          },
          loadingBannerBuilder: (context, _, __) => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: SpacingTokens.md),
                Text('正在打开原书…'),
              ],
            ),
          ),
          errorBannerBuilder: (context, _, __, ___) => Center(
            child: Padding(
              padding: const EdgeInsets.all(SpacingTokens.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '原书无法打开，请重新尝试或回书架导入完整的 PDF。',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  FilledButton(
                    onPressed: widget.options.onRetry,
                    child: const Text('重新打开'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// 标准从左到右的对开布局：封面居中，偶数页左侧、奇数页右侧。
PdfPageLayout textbookFacingPages(List<PdfPage> pages, PdfViewerParams params) {
  final width = pages.fold(0.0, (value, page) => math.max(value, page.width));
  final rects = <Rect>[];
  var y = params.margin;
  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    final number = i + 1;
    final other = number.isEven ? i + 1 : i - 1;
    final height = number > 1 && other < pages.length
        ? math.max(page.height, pages[other].height)
        : page.height;
    final x = number == 1
        ? (width * 2 + params.margin - page.width) / 2 + params.margin
        : number.isEven
            ? params.margin + width - page.width
            : params.margin * 2 + width;
    rects.add(
      Rect.fromLTWH(
        x,
        y + (height - page.height) / 2,
        page.width,
        page.height,
      ),
    );
    if (number.isOdd || i == pages.length - 1) y += height + params.margin;
  }
  return PdfPageLayout(
    pageLayouts: rects,
    documentSize: Size(width * 2 + params.margin * 3, y),
  );
}
