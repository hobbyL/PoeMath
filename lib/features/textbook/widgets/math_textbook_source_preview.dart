import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/core/services/math_textbook_image_cache.dart';
import 'package:poemath/core/services/textbook_pdf_page_loader.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/domain/math_textbook_study.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

class MathTextbookRenderToken extends TextbookDraftToken {
  PdfPageRenderCancellationToken? _render;
  @override
  void cancel() {
    _render?.cancel();
    super.cancel();
  }
}

typedef MathTextbookRegionRenderer = Future<ui.Image> Function(
  String path,
  MathTextbookRegion source,
  MathTextbookRenderToken token,
);

final mathTextbookRegionRendererProvider = Provider<MathTextbookRegionRenderer>(
  (ref) => renderMathTextbookRegion,
);

final mathTextbookExampleRendererProvider =
    Provider<MathTextbookRegionRenderer>(
      (ref) => renderMathTextbookExampleRegion,
    );

Future<ui.Image> renderMathTextbookExampleRegion(
  String path,
  MathTextbookRegion source,
  MathTextbookRenderToken token,
) async {
  token.check();
  await pdfrxFlutterInitialize();
  token.check();
  final document = await PdfDocument.openFile(path);
  late final MathTextbookRegion bounded;
  try {
    final page = await loadTextbookPdfPage(
      document: document,
      number: source.page,
      checkAvailable: token.check,
    );
    bounded = mathTextbookExampleRegion(source, page);
  } finally {
    await document.dispose();
  }
  return renderMathTextbookRegion(path, bounded, token);
}

/// 仅渲染正在对照的区域。多渲染 32 像素再裁回，避免边缘字形被 PDF 裁切改变。
Future<ui.Image> renderMathTextbookRegion(
  String path,
  MathTextbookRegion source,
  MathTextbookRenderToken token,
) async {
  MathTextbookRegion.fromJson(source.toJson());
  token.check();
  await pdfrxFlutterInitialize();
  token.check();
  final document = await PdfDocument.openFile(path);
  PdfImage? rendered;
  ui.Image? padded;
  ui.Image? result;
  try {
    token.check();
    RangeError.checkValueInInterval(source.page, 1, document.pages.length);
    final page = await document.pages[source.page - 1].waitForLoaded(
      timeout: const Duration(seconds: 15),
    );
    token.check();
    if (page == null) throw const FormatException('原书页面读取超时');
    final scale = math.min(2.0, 2000 / math.max(page.width, page.height));
    final fullWidth = math.max(1, (page.width * scale).round());
    final fullHeight = math.max(1, (page.height * scale).round());
    final left = (source.left * fullWidth).floor().clamp(0, fullWidth - 1);
    final top = (source.top * fullHeight).floor().clamp(0, fullHeight - 1);
    final right = (source.right * fullWidth).ceil().clamp(left + 1, fullWidth);
    final bottom = (source.bottom * fullHeight).ceil().clamp(
      top + 1,
      fullHeight,
    );
    final x = math.max(0, left - 32), y = math.max(0, top - 32);
    token._render = page.createCancellationToken();
    rendered = await page.render(
      x: x,
      y: y,
      width: math.min(fullWidth, right + 32) - x,
      height: math.min(fullHeight, bottom + 32) - y,
      fullWidth: fullWidth.toDouble(),
      fullHeight: fullHeight.toDouble(),
      cancellationToken: token._render,
    );
    token.check();
    if (rendered == null) throw const FormatException('原书区域暂时无法显示');
    padded = await rendered.createImage();
    token.check();
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      padded,
      ui.Rect.fromLTWH(
        (left - x).toDouble(),
        (top - y).toDouble(),
        (right - left).toDouble(),
        (bottom - top).toDouble(),
      ),
      ui.Rect.fromLTWH(
        0,
        0,
        (right - left).toDouble(),
        (bottom - top).toDouble(),
      ),
      ui.Paint()
        ..filterQuality = ui.FilterQuality.none
        ..isAntiAlias = false,
    );
    final picture = recorder.endRecording();
    try {
      result = await picture.toImage(right - left, bottom - top);
    } finally {
      picture.dispose();
    }
    token.check();
    return result;
  } on Object {
    result?.dispose();
    rethrow;
  } finally {
    token._render = null;
    padded?.dispose();
    rendered?.dispose();
    await document.dispose();
  }
}

class MathTextbookSourcePreview extends ConsumerStatefulWidget {
  const MathTextbookSourcePreview({
    super.key,
    required this.book,
    required this.source,
    this.expandToWidth = false,
    this.framed = true,
    this.workedExample = false,
  });
  final Textbook book;
  final MathTextbookRegion source;
  final bool expandToWidth;
  final bool framed;
  final bool workedExample;
  @override
  ConsumerState<MathTextbookSourcePreview> createState() =>
      _MathTextbookSourcePreviewState();
}

class _MathTextbookSourcePreviewState
    extends ConsumerState<MathTextbookSourcePreview> {
  MathTextbookRenderToken? _token;
  ui.Image? _image;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(MathTextbookSourcePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.pdfSha256 != widget.book.pdfSha256 ||
        oldWidget.workedExample != widget.workedExample ||
        oldWidget.source.toJson().toString() !=
            widget.source.toJson().toString()) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    _token?.cancel();
    final token = MathTextbookRenderToken();
    _token = token;
    final book = widget.book, source = widget.source;
    final workedExample = widget.workedExample;
    final files = ref.read(textbookFileServiceProvider);
    final cache = files.contentCache(book);
    final revision = cache.revision;
    final remembered = cache.takeMathImage(
      mathTextbookImageCacheKey(
        cache: cache,
        source: source,
        workedExample: workedExample,
      ),
    );
    _image?.dispose();
    setState(() {
      _image = remembered;
      _error = null;
    });
    final render = ref.read(
      workedExample
          ? mathTextbookExampleRendererProvider
          : mathTextbookRegionRendererProvider,
    );
    try {
      final path = await files.installedPath(book);
      token.check();
      if (revision != cache.revision) {
        throw const FormatException('原书缓存已变化，请重新加载');
      }
      if (path == null) throw const FormatException('本地原书已移除，请重新导入同一 PDF 后对照');
      // The warm preview is already on the first frame; this await only checks
      // that the source is still installed, without re-reading/decoding PNG.
      if (remembered != null) return;
      final image = await cachedMathTextbookImage(
        cache: cache,
        source: source,
        workedExample: workedExample,
        checkAvailable: token.check,
        render: () => render(path, source, token),
      );
      if (!mounted || token.cancelled || revision != cache.revision) {
        image.dispose();
        if (!token.cancelled) throw const FormatException('原书缓存已变化，请重新加载');
        return;
      }
      setState(() => _image = image);
    } on TextbookDraftCancelled {
      // 旧请求不能改写新区域的预览。
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '数学原书区域显示失败',
        tag: 'MathTextbook',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted && !token.cancelled) {
        setState(
          () => _error = error is FormatException
              ? error.message.toString()
              : '原书区域暂时无法显示',
        );
      }
    }
  }

  @override
  void dispose() {
    _token?.cancel();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = _error != null
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!),
              TextButton(onPressed: _load, child: const Text('重新加载原书区域')),
            ],
          )
        : _image == null
        ? const Padding(
            padding: EdgeInsets.all(SpacingTokens.lg),
            child: Center(child: CircularProgressIndicator()),
          )
        : Semantics(
            label: '原书 PDF 第 ${widget.source.page} 页所选区域，可放大查看',
            image: true,
            child: widget.expandToWidth
                ? AspectRatio(
                    aspectRatio: _image!.width / _image!.height,
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: RawImage(image: _image, fit: BoxFit.contain),
                    ),
                  )
                : ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .45,
                    ),
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: RawImage(image: _image, fit: BoxFit.contain),
                    ),
                  ),
          );
    return widget.framed
        ? ColoredCard(
            color: Theme.of(context).colorScheme.secondary,
            child: content,
          )
        : content;
  }
}
