import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/math_textbook_knowledge_illustrations.dart';
import 'package:poemath/core/services/math_textbook_image_cache.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_source_preview.dart';

typedef MathTextbookKnowledgeImageLoader =
    Future<List<MathTextbookRegion>> Function(
      String path,
      MathTextbookKnowledgePoint point,
      List<MathTextbookBlock> blocks,
      TextbookDraftToken token,
    );

final mathTextbookKnowledgeImageLoaderProvider =
    Provider<MathTextbookKnowledgeImageLoader>(
      (ref) => loadMathTextbookKnowledgeIllustrations,
    );

class MathTextbookKnowledgeImages extends ConsumerStatefulWidget {
  const MathTextbookKnowledgeImages({
    super.key,
    required this.book,
    required this.point,
    required this.blocks,
  });
  final Textbook book;
  final MathTextbookKnowledgePoint point;
  final List<MathTextbookBlock> blocks;

  @override
  ConsumerState<MathTextbookKnowledgeImages> createState() =>
      _MathTextbookKnowledgeImagesState();
}

class _MathTextbookKnowledgeImagesState
    extends ConsumerState<MathTextbookKnowledgeImages> {
  TextbookDraftToken? _token;
  List<MathTextbookRegion>? _regions;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(MathTextbookKnowledgeImages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.pdfSha256 != widget.book.pdfSha256 ||
        oldWidget.point.toJson().toString() !=
            widget.point.toJson().toString() ||
        oldWidget.blocks.map((b) => b.toJson()).toString() !=
            widget.blocks.map((b) => b.toJson()).toString()) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    _token?.cancel();
    final token = _token = TextbookDraftToken();
    final book = widget.book, point = widget.point;
    final blocks = widget.blocks;
    final files = ref.read(textbookFileServiceProvider);
    final cache = files.contentCache(book);
    final revision = cache.revision;
    final key = mathTextbookKnowledgeCacheKey(point, blocks);
    final remembered = cache.cachedMathKnowledgeRegions(key);
    setState(() {
      _regions = remembered;
      _error = null;
    });
    final loader = ref.read(mathTextbookKnowledgeImageLoaderProvider);
    try {
      final path = await files.installedPath(book);
      token.check();
      if (cache.revision != revision) {
        throw const FormatException('原书已变化，请重新加载配图');
      }
      if (path == null) throw const FormatException('本地原书已移除，请重新导入后查看配图');
      if (remembered != null) return;
      final regions = await cache.mathKnowledgeRegions(key, () async {
        token.check();
        final regions = await loader(path, point, blocks, token);
        token.check();
        return regions;
      });
      token.check();
      if (cache.revision != revision) {
        throw const FormatException('原书已变化，请重新加载配图');
      }
      if (mounted) setState(() => _regions = regions);
    } on TextbookDraftCancelled {
      // Closing or switching the note cancels the previous source lookup.
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '知识配图读取失败',
        tag: 'MathTextbook',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted && !token.cancelled) {
        setState(
          () => _error = error is FormatException
              ? error.message.toString()
              : '配图暂时无法显示',
        );
      }
    }
  }

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Column(
        children: [
          Text(_error!),
          TextButton(onPressed: _load, child: const Text('重新加载配图')),
        ],
      );
    }
    if (_regions == null) {
      return const Padding(
        padding: EdgeInsets.all(SpacingTokens.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final region in _regions!)
          Padding(
            padding: const EdgeInsets.only(top: SpacingTokens.md),
            child: MathTextbookSourcePreview(
              book: widget.book,
              source: region,
              expandToWidth: true,
              framed: false,
            ),
          ),
      ],
    );
  }
}
