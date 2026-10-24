/// 原书文字及布局的共享表示；PDF 类型只留在原生适配器。
class TextbookPageGlyph {
  const TextbookPageGlyph({
    required this.text,
    required this.index,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });
  final String text;

  /// 原始文字中的 Unicode 码点位置，不是 UTF-16 下标。
  final int index;
  final double left;
  final double top;
  final double right;
  final double bottom;
  double get height => bottom - top;
  double get width => right - left;
  double get centerX => (left + right) / 2;
  Map<String, Object?> toJson() => {
        'text': text,
        'index': index,
        'left': left,
        'top': top,
        'right': right,
        'bottom': bottom,
      };
  factory TextbookPageGlyph.fromJson(Map<String, dynamic> raw) {
    final text = raw['text'] as String;
    final index = raw['index'] as int;
    final coords = ['left', 'top', 'right', 'bottom']
        .map((key) => (raw[key] as num).toDouble())
        .toList();
    if (text.runes.length != 1 ||
        index < 0 ||
        coords.any((value) => !value.isFinite) ||
        coords[2] < coords[0] ||
        coords[3] < coords[1]) {
      throw const FormatException('原书字符位置无效');
    }
    return TextbookPageGlyph(
      text: text,
      index: index,
      left: coords[0],
      top: coords[1],
      right: coords[2],
      bottom: coords[3],
    );
  }
}

class TextbookPageText {
  const TextbookPageText({
    required this.page,
    required this.text,
    required this.width,
    required this.height,
    this.glyphs = const [],
    this.status = 'text_extracted',
  });
  final int page;
  final String text;
  final double width;
  final double height;
  final List<TextbookPageGlyph> glyphs;
  final String status;
  Map<String, Object?> toJson() => {
        'page': page,
        'text': text,
        'width': width,
        'height': height,
        'status': status,
        'glyphs': glyphs.map((g) => g.toJson()).toList(),
      };
  factory TextbookPageText.fromJson(Map<String, dynamic> raw) {
    final page = raw['page'] as int;
    final text = raw['text'] as String;
    final width = (raw['width'] as num).toDouble();
    final height = (raw['height'] as num).toDouble();
    final glyphs = (raw['glyphs'] as List<dynamic>)
        .map(
          (value) => TextbookPageGlyph.fromJson(value as Map<String, dynamic>),
        )
        .toList();
    final runes = text.runes.toList();
    if (page < 1 ||
        width <= 0 ||
        height <= 0 ||
        !width.isFinite ||
        !height.isFinite ||
        glyphs.any(
          (g) =>
              g.index >= runes.length ||
              String.fromCharCode(runes[g.index]) != g.text,
        )) {
      throw const FormatException('原书页布局无效');
    }
    return TextbookPageText(
      page: page,
      text: text,
      width: width,
      height: height,
      glyphs: List.unmodifiable(glyphs),
      status: raw['status'] as String,
    );
  }
}
