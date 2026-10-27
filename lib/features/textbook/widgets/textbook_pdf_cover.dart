import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/textbook_cover_cache.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/logger.dart';

/// 取消仅终止当前封面渲染；不影响原书或阅读记录。
class TextbookCoverToken {
  bool _cancelled = false;
  PdfPageRenderCancellationToken? _renderToken;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _renderToken?.cancel();
  }
}

typedef TextbookCoverRenderer = Future<ui.Image?> Function(
  String path,
  TextbookCoverToken token,
);

final textbookCoverRendererProvider = Provider<TextbookCoverRenderer>(
  (ref) => _renderFirstPage,
);

const _coverCache = TextbookCoverCache();

/// 先读磁盘缓存（PNG），未命中才打开 PDF 渲染首页并回写。
///
/// 早先每次挂载都重新打开原书渲染：大 PDF 要几百毫秒甚至更久，
/// 用户看到的是「每次进入书籍管理页封面都没图」。现在同一本书只渲染一次。
Future<ui.Image?> _renderFirstPage(
  String path,
  TextbookCoverToken token,
) async {
  final cached = await _coverCache.read(path);
  if (cached != null) {
    // 命中缓存：只做一次 PNG 解码，不再打开原书。
    if (token.isCancelled) {
      cached.dispose();
      return null;
    }
    _coverCache.remember(path, cached);
    return cached;
  }
  await pdfrxFlutterInitialize();
  if (token.isCancelled) return null;
  final document = await PdfDocument.openFile(
    path,
    useProgressiveLoading: true,
  );
  PdfImage? rendered;
  try {
    if (token.isCancelled || document.pages.isEmpty) return null;
    final page = document.pages.first;
    const maxPixelSize = 768.0;
    final scale = maxPixelSize / math.max(page.width, page.height);
    final renderToken = page.createCancellationToken();
    token._renderToken = renderToken;
    rendered = await page.render(
      fullWidth: math.max(1, page.width * scale),
      fullHeight: math.max(1, page.height * scale),
      cancellationToken: renderToken,
    );
    if (token.isCancelled || rendered == null) return null;
    final image = await rendered.createImage();
    // 落盘后再返回：即使组件随即销毁，下一次进入也能直接命中。
    await _coverCache.write(path, image);
    _coverCache.remember(path, image);
    return image;
  } finally {
    token._renderToken = null;
    rendered?.dispose();
    await document.dispose();
  }
}

class TextbookCoverPlaceholder extends StatelessWidget {
  const TextbookCoverPlaceholder({
    super.key,
    required this.title,
    required this.status,
  });

  final String title;
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.sm),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: SpacingTokens.xl,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: SpacingTokens.sm),
          Flexible(
            child: Text(
              title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          Flexible(
            child: Text(
              status,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// PDF 库和位图生命周期仅在适配层出现，页面只提供本机路径。
class TextbookPdfCover extends ConsumerStatefulWidget {
  const TextbookPdfCover({
    super.key,
    required this.path,
    required this.title,
  });

  final String path;
  final String title;

  @override
  ConsumerState<TextbookPdfCover> createState() => _TextbookPdfCoverState();
}

class _TextbookPdfCoverState extends ConsumerState<TextbookPdfCover> {
  ui.Image? _image;
  TextbookCoverToken? _token;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(TextbookPdfCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _start();
  }

  void _start() {
    _token?.cancel();
    _image?.dispose();
    _image = null;
    _failed = false;
    // 同一会话内再次进入：直接复用上次解码的位图，首帧就有封面，
    // 不再先闪一下「正在生成封面」。
    final memory = const TextbookCoverCache().take(widget.path);
    if (memory != null) {
      _image = memory;
      return;
    }
    final token = TextbookCoverToken();
    _token = token;
    final renderer = ref.read(textbookCoverRendererProvider);
    unawaited(_load(widget.path, token, renderer));
  }

  Future<void> _load(
    String path,
    TextbookCoverToken token,
    TextbookCoverRenderer renderer,
  ) async {
    try {
      final image = await renderer(path, token);
      if (!mounted || token != _token || token.isCancelled) {
        image?.dispose();
        return;
      }
      setState(() {
        _image = image;
        _failed = image == null;
      });
    } on Object catch (error, stackTrace) {
      if (!mounted || token != _token || token.isCancelled) return;
      AppLogger.e(
        '书籍封面无法生成',
        tag: 'Textbook',
        error: error,
        stackTrace: stackTrace,
      );
      setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _token?.cancel();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _image == null
      ? TextbookCoverPlaceholder(
          title: widget.title,
          status: _failed ? '封面暂不可用' : '正在生成封面',
        )
      : RawImage(image: _image, fit: BoxFit.contain);
}
