// fvm flutter test integration_test/math_textbook_learning_test.dart
//   -d emulator-5554 --dart-define=POEMATH_INTEGRATION_TEST=true --no-uninstall
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/math_textbook_pdf_graphics.dart';
import 'package:poemath/core/utils/logger.dart';

import '../test/features/textbook/math_textbook_learning_test.dart' as learning;
import '../test/helpers/math_textbook_pdf_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    expect(
      (await PackageInfo.fromPlatform()).packageName,
      'com.poemath.app.integration',
      reason: '必须使用独立测试包，不能操作正常应用的数据',
    );
  });
  learning.defineMathTextbookLearningTests(capture: _capture);

  testWidgets('Android 原生 PDFium 的裁切、旋转和图形像素与来源一致', (tester) async {
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('math-pdf-native-');
      try {
        Pdfrx.cacheDirectoryPath = root.path;
        await pdfrxFlutterInitialize();
        final file = await File('${root.path}/own.pdf')
            .writeAsBytes(mathTextbookGeometryPdf());
        final document = await PdfDocument.openFile(file.path);
        try {
          const expected = [
            (0.275, 0.8),
            (0.2, 0.275),
            (0.725, 0.2),
            (0.8, 0.725),
          ];
          for (var index = 0; index < 4; index++) {
            final graphics = await document.useNativeDocumentHandle(
              (handle) => readMathTextbookGraphics(handle, index + 1),
            );
            expect(graphics.complete, isTrue);
            expect(graphics.lines, hasLength(2));
            final region = graphics.regions.single;
            expect(region.centerX, closeTo(expected[index].$1, .002));
            expect(region.centerY, closeTo(expected[index].$2, .002));
            final page = document.pages[index];
            final rendered = await page.render(
              fullWidth: page.width * 2,
              fullHeight: page.height * 2,
            );
            final image = await rendered!.createImage();
            try {
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
              );
            } finally {
              image.dispose();
              rendered.dispose();
            }
          }
        } finally {
          await document.dispose();
        }
      } finally {
        await root.delete(recursive: true);
      }
    });
  });
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 600));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('math-textbook-evidence')),
  );
  final image = await boundary.toImage();
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final support = await getApplicationSupportDirectory();
    final folder = await Directory('${support.path}/math-textbook-evidence')
        .create(recursive: true);
    final file = await File('${folder.path}/$name.png').writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    AppLogger.d('EVIDENCE=${file.path}', tag: 'MathTextbookNativeTest');
  } finally {
    image.dispose();
  }
}
