import 'package:poemath/data/models/textbook.dart';

Textbook textbookFixture({
  String? id,
  String title = '语文测试教材',
  int pageCount = 3,
  int fileSize = 25,
}) =>
    Textbook(
      pdfSha256: id ?? List.filled(64, 'a').join(),
      title: title,
      grade: 3,
      semester: '上',
      publisher: '测试出版社',
      editionNote: '合成样本',
      originalFileName: 'sample.pdf',
      pageCount: pageCount,
      fileSize: fileSize,
      importedAt: DateTime.utc(2026, 10, 22),
    );

/// 自有三页 PDF，用于真实 PDFium 打开/渲染测试；不含教材内容。
List<int> syntheticPdf({bool bookmarks = false}) {
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R ${bookmarks ? '/Outlines 10 0 R' : ''} >>',
    '<< /Type /Pages /Kids [3 0 R 5 0 R 7 0 R] /Count 3 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Resources << /Font << /F1 9 0 R >> >> /Contents 4 0 R >>',
    '<< /Length 55 >>\nstream\nBT /F1 18 Tf 30 340 Td (PoeMath PDF sample - 1) Tj ET\nendstream',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Resources << /Font << /F1 9 0 R >> >> /Contents 6 0 R >>',
    '<< /Length 55 >>\nstream\nBT /F1 18 Tf 30 340 Td (PoeMath PDF sample - 2) Tj ET\nendstream',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Resources << /Font << /F1 9 0 R >> >> /Contents 8 0 R >>',
    '<< /Length 55 >>\nstream\nBT /F1 18 Tf 30 340 Td (PoeMath PDF sample - 3) Tj ET\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  if (bookmarks) {
    objects.addAll([
      '<< /Type /Outlines /First 11 0 R /Last 11 0 R /Count 2 >>',
      '<< /Title (Chapter) /Parent 10 0 R /Dest [5 0 R /Fit] /First 12 0 R /Last 12 0 R /Count 1 >>',
      '<< /Title (Section) /Parent 11 0 R /Dest [7 0 R /Fit] >>',
    ]);
  }
  var pdf = '%PDF-1.4\n';
  final offsets = <int>[0];
  for (var index = 0; index < objects.length; index++) {
    offsets.add(pdf.length);
    pdf += '${index + 1} 0 obj\n${objects[index]}\nendobj\n';
  }
  final xref = pdf.length;
  pdf += 'xref\n0 ${objects.length + 1}\n0000000000 65535 f \n';
  for (final offset in offsets.skip(1)) {
    pdf += '${offset.toString().padLeft(10, '0')} 00000 n \n';
  }
  pdf +=
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n';
  return pdf.codeUnits;
}
