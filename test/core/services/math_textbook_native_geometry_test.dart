import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/math_textbook_pdf_graphics.dart';

import '../../helpers/math_textbook_pdf_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const library = String.fromEnvironment('TEXTBOOK_PDFIUM_LIBRARY');
  test('原生图形坐标与裁切、旋转后的实际像素一致，透明线不作为分数证据', () async {
    final root = await Directory.systemTemp.createTemp(
      'poemath-math-geometry-',
    );
    addTearDown(() => root.delete(recursive: true));
    Pdfrx.pdfiumModulePath = library;
    Pdfrx.cacheDirectoryPath = root.path;
    await pdfrxFlutterInitialize();
    final file = await File('${root.path}/own.pdf')
        .writeAsBytes(mathTextbookGeometryPdf());
    final document = await PdfDocument.openFile(file.path);
    try {
      const expected = [(0.275, 0.8), (0.2, 0.275), (0.725, 0.2), (0.8, 0.725)];
      for (var i = 0; i < 4; i++) {
        final graphics = await document.useNativeDocumentHandle(
          (handle) =>
              readMathTextbookGraphics(handle, i + 1, modulePath: library),
        );
        expect(graphics.complete, isTrue);
        expect(graphics.lines, hasLength(2), reason: '旋转 $i：只有矩形的两条水平边可见');
        final region = graphics.regions.single;
        expect(region.centerX, closeTo(expected[i].$1, .002));
        expect(region.centerY, closeTo(expected[i].$2, .002));
        final page = document.pages[i];
        final rendered = await page.render(
          fullWidth: page.width * 2,
          fullHeight: page.height * 2,
        );
        final image = await rendered!.createImage();
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final offset =
            ((region.centerY * image.height).floor() * image.width +
                (region.centerX * image.width).floor()) *
            4;
        expect(
          [
            pixels.getUint8(offset),
            pixels.getUint8(offset + 1),
            pixels.getUint8(offset + 2),
          ],
          [0, 0, 0],
          reason: '来源区域中心必须落在实际黑色图形内',
        );
        image.dispose();
        rendered.dispose();
      }
    } finally {
      await document.dispose();
    }
  }, skip: library.isEmpty);
}
