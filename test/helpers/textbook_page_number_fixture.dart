import 'package:poemath/core/services/textbook_page_number_service.dart';
import 'package:poemath/data/models/textbook_page_text.dart';

TextbookPageText printedPageFixture(
  int pdfPage,
  int? printedPage, {
  double left = 0.08,
  double top = 0.932,
  bool reverseGlyphs = false,
}) {
  final digits = printedPage?.toString() ?? '';
  final glyphs = [
    for (var i = 0; i < digits.length; i++)
      TextbookPageGlyph(
        text: digits[i],
        index: i,
        left: left + i * 0.013,
        right: left + i * 0.013 + 0.011,
        top: top,
        bottom: top + 0.012,
      ),
  ];
  return TextbookPageText(
    page: pdfPage,
    text: '$digits\n正文',
    width: 521.575,
    height: 737.008,
    glyphs: reverseGlyphs ? glyphs.reversed.toList() : glyphs,
  );
}

TextbookPageNumberService pageNumberFixture({
  required int pageCount,
  Map<int, int?>? pages,
}) => TextbookPageNumberService(
  pageCount: pageCount,
  loadPage: (page) => Future.value(
    printedPageFixture(page, pages == null ? page : pages[page]),
  ),
);

/// 自有 PDF：交替左右页脚，附加页面外数字以验证可见字框转换。
List<int> printedPagesPdf(List<int?> printedPages) {
  final count = printedPages.length;
  if (count == 0) throw ArgumentError.value(count, 'printedPages');
  final font = 3 + count * 2;
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${[for (var i = 0; i < count; i++) '${3 + i * 2} 0 R'].join(' ')}] /Count $count >>',
  ];
  for (var i = 0; i < count; i++) {
    final number = printedPages[i];
    final text = StringBuffer()
      ..writeln('BT /F1 18 Tf 30 340 Td (PoeMath sample - ${i + 1}) Tj ET')
      ..writeln('BT /F1 10 Tf -80 20 Td (999) Tj ET')
      ..writeln('BT /F1 10 Tf 800 20 Td (888) Tj ET');
    if (number != null) {
      text.writeln('BT /F1 10 Tf ${i.isEven ? 267 : 30} 20 Td ($number) Tj ET');
    }
    final content = text.toString();
    objects.addAll([
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Resources << /Font << /F1 $font 0 R >> >> /Contents ${4 + i * 2} 0 R >>',
      '<< /Length ${content.length} >>\nstream\n${content}endstream',
    ]);
  }
  objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  final pdf = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(pdf.length);
    pdf.writeln('${i + 1} 0 obj\n${objects[i]}\nendobj');
  }
  final xref = pdf.length;
  pdf.writeln('xref\n0 ${objects.length + 1}\n0000000000 65535 f ');
  for (final offset in offsets.skip(1)) {
    pdf.writeln('${offset.toString().padLeft(10, '0')} 00000 n ');
  }
  pdf.writeln(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF',
  );
  return pdf.toString().codeUnits;
}
