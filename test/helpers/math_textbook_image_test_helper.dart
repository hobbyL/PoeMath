import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_source_preview.dart';

/// PNG encoding, disk IO and decoding need real IO time, even with a fake PDF
/// renderer. Wait for actual preview images before settling route animations.
Future<void> settleMathTextbookImages(WidgetTester tester) async {
  final deadline = Stopwatch()..start();
  final previews = find.byType(MathTextbookSourcePreview);
  final images = find.descendant(of: previews, matching: find.byType(RawImage));
  do {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (images.evaluate().length == previews.evaluate().length) break;
  } while (deadline.elapsed < const Duration(seconds: 8));
  expect(images.evaluate().length, previews.evaluate().length);
  await tester.pumpAndSettle();
}
