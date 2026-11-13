import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/core/services/textbook_page_number_service.dart';
import 'package:poemath/core/services/textbook_pdf_page_loader.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/models/textbook_toc.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_corner.dart';
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
    this.onPageNumbersReady,
    this.contentCache,
    this.onPreviousPage,
    this.onNextPage,
  });
  final String path;
  final int initialPage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<TextbookGoToPage> onReady;
  final VoidCallback onRetry;
  final bool doublePage;
  final ValueChanged<TextbookSearch>? onSearchReady;
  final ValueChanged<TextbookTocLoader>? onTocReady;
  final ValueChanged<TextbookPageNumberService>? onPageNumbersReady;
  final TextbookContentCache? contentCache;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
}

/// PDF 库只在此适配层出现，页面/测试可注入其他渲染器。
class TextbookPdfView extends StatefulWidget {
  const TextbookPdfView({
    super.key,
    required this.options,
    this.horizontalPaging = false,
  });
  final TextbookViewerOptions options;
  final bool horizontalPaging;
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
  int? _swipePage;
  Offset _swipeStart = Offset.zero;
  Offset _swipeDelta = Offset.zero;
  Matrix4? _swipeMatrix;
  bool _swipeEligible = false;
  int _interactionRevision = 0;

  TextbookPageLayout get _pageLayout =>
      TextbookPageLayout(doublePage: widget.options.doublePage);

  Rect _spreadRect(int page) {
    final rects = _controller.layout.pageLayouts;
    final numbers = _pageLayout.pages(
      _pageLayout.spreadIndex(page),
      rects.length,
    );
    return numbers
        .map((number) => rects[number - 1])
        .reduce((left, right) => left.expandToInclude(right));
  }

  double _readingZoom(int page) {
    final rect = _spreadRect(page);
    final widthZoom =
        _controller.viewSize.width / (rect.width + SpacingTokens.md);
    return widget.options.doublePage
        ? math.min(
            widthZoom,
            _controller.viewSize.height / (rect.height + SpacingTokens.md),
          )
        : widthZoom;
  }

  void _startSwipe(ScaleStartDetails details) {
    _interactionRevision++;
    _swipePage = null;
    if (!_viewerReady || _changingLayout || _navigating) return;
    _swipePage = _page;
    _swipeStart = details.localFocalPoint;
    _swipeDelta = Offset.zero;
    _swipeMatrix = _controller.value.clone();
    _swipeEligible =
        details.pointerCount == 1 &&
        _controller.currentZoom <= _readingZoom(_page) * 1.05;
  }

  void _updateSwipe(ScaleUpdateDetails details) {
    _swipeDelta = details.localFocalPoint - _swipeStart;
    if (details.pointerCount != 1 || details.scale != 1) {
      _swipeEligible = false;
    }
  }

  Future<void> _endSwipe(ScaleEndDetails details) async {
    final page = _swipePage;
    final delta = _swipeDelta;
    if (page == null) return;
    if (!_swipeEligible || delta.dx.abs() <= delta.dy.abs()) {
      _swipePage = null;
      return;
    }
    final velocity = details.velocity.pixelsPerSecond;
    final fling =
        velocity.dx.abs() >= 500 && velocity.dx.abs() > velocity.dy.abs();
    final turn = delta.dx.abs() >= _controller.viewSize.width * 0.2 || fling;
    final direction = fling ? velocity.dx : delta.dx;
    final target = !turn
        ? page
        : (direction < 0
                  ? _pageLayout.next(page, _controller.pageCount)
                  : _pageLayout.previous(page, _controller.pageCount)) ??
              page;
    final revision = _interactionRevision;
    final restore = _swipeMatrix;
    // pdfrx 在 onInteractionEnd 返回后启动惯性；下一轮再吸附才能停止它。
    await Future<void>.delayed(Duration.zero);
    if (!mounted || revision != _interactionRevision) return;
    try {
      await _goToPage(target, restore: target == page ? restore : null);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '手势翻页失败',
        tag: 'Textbook',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (revision == _interactionRevision) _swipePage = null;
    }
  }

  Future<void> _goToPage(
    int page, {
    bool animate = true,
    Matrix4? restore,
  }) async {
    if (!mounted || !_controller.isReady || _navigating) return;
    final target = page.clamp(1, _controller.pageCount);
    _page = target;
    _navigating = true;
    final duration = !animate || MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    try {
      if (restore != null) {
        await _controller.goTo(restore, duration: duration);
      } else if (widget.options.doublePage) {
        final rect = _spreadRect(target);
        await _controller.goToArea(
          rect: widget.horizontalPaging ? rect.inflate(SpacingTokens.sm) : rect,
          anchor: PdfPageAnchor.all,
          duration: duration,
        );
      } else {
        await _controller.goToPage(pageNumber: target, duration: duration);
      }
      if (mounted) {
        _page = target;
        if (restore == null) widget.options.onPageChanged(target);
      }
    } finally {
      _navigating = false;
    }
  }

  @override
  void didUpdateWidget(covariant TextbookPdfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.doublePage != widget.options.doublePage ||
        oldWidget.horizontalPaging != widget.horizontalPaging) {
      _interactionRevision++;
      _swipePage = null;
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
      layoutPages: widget.horizontalPaging
          ? (pages, params) => textbookHorizontalPages(
              pages,
              params,
              doublePage: widget.options.doublePage,
            )
          : widget.options.doublePage
          ? textbookFacingPages
          : null,
      panAxis: widget.horizontalPaging ? PanAxis.aligned : PanAxis.free,
      onInteractionStart: widget.horizontalPaging ? _startSwipe : null,
      onInteractionUpdate: widget.horizontalPaging ? _updateSwipe : null,
      onInteractionEnd: widget.horizontalPaging
          ? (details) => unawaited(_endSwipe(details))
          : null,
      horizontalCacheExtent: 1,
      verticalCacheExtent: 2,
      maxImageBytesCachedOnMemory: 64 * 1024 * 1024,
      onGeneralTap: (_, controller, details) {
        if (details.type != PdfViewerGeneralTapType.tap ||
            !_viewerReady ||
            _changingLayout ||
            _navigating) {
          return false;
        }
        final spread = _spreadRect(_page);
        final corner = textbookPageCornerAt(
          details.localPosition,
          Rect.fromPoints(
            controller.documentToLocal(spread.topLeft),
            controller.documentToLocal(spread.bottomRight),
          ),
        );
        final action = switch (corner) {
          TextbookPageCorner.previous => widget.options.onPreviousPage,
          TextbookPageCorner.next => widget.options.onNextPage,
          null => null,
        };
        if (action == null) return false;
        action();
        return true;
      },
      sizeDelegateProvider: widget.horizontalPaging
          ? _TextbookPagingSizeDelegateProvider(
              doublePage: widget.options.doublePage,
              calculateInitialZoom: (_, _, _, _) => _readingZoom(_page),
            )
          : PdfViewerSizeDelegateProviderLegacy(
              calculateInitialZoom: (_, controller, fitScale, coverScale) {
                if (!widget.options.doublePage) return coverScale;
                final rect = _spreadRect(_page);
                return math.min(
                  controller.viewSize.width / (rect.width + SpacingTokens.md),
                  controller.viewSize.height / (rect.height + SpacingTokens.md),
                );
              },
            ),
      calculateCurrentPageNumber:
          widget.options.doublePage || widget.horizontalPaging
          ? (visible, rects, _) {
              if (!_viewerReady ||
                  _changingLayout ||
                  _navigating ||
                  _swipePage != null) {
                return _page;
              }
              var bestPage = 1;
              var bestArea = 0.0;
              final layout = _pageLayout;
              for (
                var index = 0;
                index < layout.spreadCount(rects.length);
                index++
              ) {
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
              return layout.spreadIndex(bestPage) == layout.spreadIndex(_page)
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
          widget.options.onPageNumbersReady?.call(
            textbookPdfPageNumberService(
              document,
              cache: widget.options.contentCache,
              checkAvailable: () {
                if (!mounted) {
                  throw StateError('原书已关闭');
                }
              },
            ),
          );
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
            !_navigating &&
            _swipePage == null) {
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

class _TextbookPagingSizeDelegateProvider
    extends PdfViewerSizeDelegateProviderLegacy {
  const _TextbookPagingSizeDelegateProvider({
    required this.doublePage,
    super.calculateInitialZoom,
  });

  final bool doublePage;

  @override
  PdfViewerSizeDelegate create() => _TextbookPagingSizeDelegate(this);
}

class _TextbookPagingSizeDelegate extends PdfViewerSizeDelegateLegacy {
  _TextbookPagingSizeDelegate(_TextbookPagingSizeDelegateProvider provider)
    : _doublePage = provider.doublePage,
      super(
        maxScale: provider.maxScale,
        minScale: provider.minScale,
        useAlternativeFitScaleAsMinScale:
            provider.useAlternativeFitScaleAsMinScale,
        onePassRenderingScaleThreshold: provider.onePassRenderingScaleThreshold,
        calculateInitialZoom: provider.calculateInitialZoom,
      );

  final bool _doublePage;

  @override
  PdfViewerLayoutMetrics calculateMetrics({
    required Size viewSize,
    required PdfPageLayout? layout,
    required int? pageNumber,
    required double pageMargin,
    required EdgeInsets? boundaryMargin,
  }) {
    final metrics = super.calculateMetrics(
      viewSize: viewSize,
      layout: layout,
      pageNumber: pageNumber,
      pageMargin: pageMargin,
      boundaryMargin: boundaryMargin,
    );
    if (layout == null || layout.pageLayouts.isEmpty) return metrics;
    final width = layout.pageLayouts.fold(
      0.0,
      (value, rect) => math.max(value, rect.width),
    );
    final height = layout.pageLayouts.fold(
      0.0,
      (value, rect) => math.max(value, rect.height),
    );
    final spreadWidth = _doublePage ? width * 2 + pageMargin : width;
    // 横向整本宽度不能用于最小缩放；下限应能完整显示一页/一组对开页。
    final fit = math.min(
      viewSize.width / (spreadWidth + pageMargin * 2),
      viewSize.height / (height + pageMargin * 2),
    );
    return PdfViewerLayoutMetrics(
      minScale: math.min(fit, metrics.maxScale),
      maxScale: metrics.maxScale,
      coverScale: metrics.coverScale,
      alternativeFitScale: fit,
    );
  }
}

/// 每个单页/展开页占一个横向位置，封面独立居中。
PdfPageLayout textbookHorizontalPages(
  List<PdfPage> pages,
  PdfViewerParams params, {
  bool doublePage = false,
}) {
  final layout = TextbookPageLayout(doublePage: doublePage);
  final width = pages.fold(0.0, (value, page) => math.max(value, page.width));
  final height = pages.fold(0.0, (value, page) => math.max(value, page.height));
  final spreadWidth = doublePage ? width * 2 + params.margin : width;
  final rects = <Rect>[];
  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    final number = i + 1;
    final x =
        params.margin +
        layout.spreadIndex(number) * (spreadWidth + params.margin);
    final offset = !doublePage || number == 1
        ? (spreadWidth - page.width) / 2
        : number.isEven
        ? width - page.width
        : width + params.margin;
    rects.add(
      Rect.fromLTWH(
        x + offset,
        params.margin + (height - page.height) / 2,
        page.width,
        page.height,
      ),
    );
  }
  return PdfPageLayout(
    pageLayouts: rects,
    documentSize: Size(
      layout.spreadCount(pages.length) * (spreadWidth + params.margin) +
          params.margin,
      height + params.margin * 2,
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
      Rect.fromLTWH(x, y + (height - page.height) / 2, page.width, page.height),
    );
    if (number.isOdd || i == pages.length - 1) y += height + params.margin;
  }
  return PdfPageLayout(
    pageLayouts: rects,
    documentSize: Size(width * 2 + params.margin * 3, y),
  );
}
