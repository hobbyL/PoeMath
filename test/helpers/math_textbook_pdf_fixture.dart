import 'dart:convert';

/// 自有 PDF：裁切框偏移、嵌套 Form 矩阵、四个旋转方向和透明线段。
List<int> mathTextbookGeometryPdf() {
  const commands = 'q /Shape Do Q\nq /Hide gs 0 G 30 300 m 100 300 l S Q\n';
  const form = '0 g 0 G 1 w 20 25 25 20 re B\n';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Count 4 /Kids [3 0 R 4 0 R 5 0 R 6 0 R] >>',
    for (var rotation = 0; rotation < 4; rotation++)
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /CropBox [20 30 220 330] /Rotate ${rotation * 90} /Resources << /XObject << /Shape 8 0 R >> /ExtGState << /Hide 9 0 R >> >> /Contents 7 0 R >>',
    '<< /Length ${commands.length} >>\nstream\n${commands}endstream',
    '<< /Type /XObject /Subtype /Form /BBox [0 0 100 100] /Matrix [2 0 0 2 10 20] /Resources << >> /Length ${form.length} >>\nstream\n${form}endstream',
    '<< /Type /ExtGState /CA 0 >>',
  ];
  var pdf = '%PDF-1.4\n';
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(pdf.length);
    pdf += '${i + 1} 0 obj\n${objects[i]}\nendobj\n';
  }
  final start = pdf.length;
  pdf += 'xref\n0 ${objects.length + 1}\n0000000000 65535 f \n';
  for (final offset in offsets.skip(1)) {
    pdf += '${offset.toString().padLeft(10, '0')} 00000 n \n';
  }
  pdf +=
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$start\n%%EOF\n';
  return ascii.encode(pdf);
}
