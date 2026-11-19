import 'dart:ui' as ui;

import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook_course.dart'
    show textbookContentDigest;

String mathTextbookKnowledgeCacheKey(
  MathTextbookKnowledgePoint point,
  List<MathTextbookBlock> blocks,
) => textbookContentDigest({
  'version': 1,
  'point': point.toJson(),
  'blocks': blocks.map((b) => b.toJson()).toList(),
});

/// Both learning illustrations and practice previews share the book's cache
/// owner/write queue. Return a separately owned image on every read.
Future<ui.Image> cachedMathTextbookImage({
  required TextbookContentCache cache,
  required MathTextbookRegion source,
  required bool workedExample,
  required void Function() checkAvailable,
  required Future<ui.Image> Function() render,
}) async {
  final generation = cache.revision;
  void check() {
    checkAvailable();
    if (cache.revision != generation) throw StateError('原书缓存已失效');
  }

  final key = textbookContentDigest({
    'version': 1,
    'source': source.toJson(),
    'workedExample': workedExample,
    'pageCount': cache.book.pageCount,
    'pdfSize': cache.book.fileSize,
  });
  check();
  final bytes = await cache.readMathImage(key);
  check();
  ui.Image? image;
  try {
    if (bytes != null) {
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          image = (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      } on Object {
        // A corrupt PNG is a cache miss, not an unavailable textbook.
      }
      check();
      if (image != null) return image;
    }
    image = await render();
    check();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    check();
    if (png != null) {
      await cache.writeMathImage(
        key,
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        generation: generation,
      );
    }
    check();
    return image;
  } on Object {
    image?.dispose();
    rethrow;
  }
}
