/// 目录仅用于原书导航，不属于已审核的课程内容。
class TextbookTocEntry {
  const TextbookTocEntry({
    required this.title,
    this.page,
    this.printedPage,
    this.level = 0,
    this.lessonNumber,
    this.isGroup = false,
  });

  final String title;
  final int? page;
  final int? printedPage;
  final int level;
  final int? lessonNumber;

  /// 无页码的结构节点可展开，但不应被当成定位失败。
  final bool isGroup;
}

enum TextbookTocSource { bookmarks, text }

class TextbookTocResult {
  const TextbookTocResult({
    required this.entries,
    required this.source,
    this.directoryPages = const [],
    this.hasText = true,
  });

  final List<TextbookTocEntry> entries;
  final TextbookTocSource source;
  final List<int> directoryPages;
  final bool hasText;
}

enum TextbookTocPhase { locating, resolving, ready }

class TextbookTocProgress {
  const TextbookTocProgress({
    required this.phase,
    required this.scanned,
    required this.total,
    this.result,
  });

  final TextbookTocPhase phase;
  final int scanned;
  final int total;
  final TextbookTocResult? result;
}

typedef TextbookTocLoader = Stream<TextbookTocProgress> Function(bool refresh);

/// 归一化至页面左上原点的字符框，避免识别服务依赖具体 PDF 库。
class TextbookTocGlyph {
  const TextbookTocGlyph({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.height,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double height;
}

class TextbookTocPage {
  const TextbookTocPage(this.text, {this.glyphs = const []});

  final String text;
  final List<TextbookTocGlyph> glyphs;
}
