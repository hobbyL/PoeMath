import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook_page_text.dart';

class MathTextbookLine {
  const MathTextbookLine({
    required this.left,
    required this.right,
    required this.y,
    required this.dark,
  });
  final double left;
  final double right;
  final double y;
  final bool dark;
}

class MathTextbookGraphics {
  MathTextbookGraphics({
    List<MathTextbookLine> lines = const [],
    List<MathTextbookRegion> regions = const [],
    this.complete = true,
  }) : lines = List.unmodifiable(lines),
       regions = List.unmodifiable(regions);
  final List<MathTextbookLine> lines;
  final List<MathTextbookRegion> regions;
  final bool complete;
}

/// 只在整理过程中使用；完整字符矩形不会内嵌到课程草稿。
class MathTextbookPageLayout {
  const MathTextbookPageLayout({required this.text, required this.graphics});
  final TextbookPageText text;
  final MathTextbookGraphics graphics;
}
