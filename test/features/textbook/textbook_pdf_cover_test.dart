import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_cover.dart';

Future<ui.Image> _image(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 12, 16),
      ui.Paint()..color = Colors.blue,
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(12, 16);
    } finally {
      picture.dispose();
    }
  }))!;
}

void main() {
  testWidgets('换路径取消旧封面，晚到图像不覆盖新书并释放，退出释放当前图像', (tester) async {
    final oldImage = await _image(tester);
    final newImage = await _image(tester);
    final oldResult = Completer<ui.Image?>();
    final newResult = Completer<ui.Image?>();
    final tokens = <String, TextbookCoverToken>{};
    Future<ui.Image?> render(String path, TextbookCoverToken token) {
      tokens[path] = token;
      return path == '/old.pdf' ? oldResult.future : newResult.future;
    }

    Future<void> mount(String path) => tester.pumpWidget(
          ProviderScope(
            overrides: [
              textbookCoverRendererProvider.overrideWithValue(render),
            ],
            child: MaterialApp(
              home: SizedBox(
                width: 150,
                height: 200,
                child: TextbookPdfCover(path: path, title: '测试书籍'),
              ),
            ),
          ),
        );
    await mount('/old.pdf');
    await mount('/new.pdf');
    expect(tokens['/old.pdf']!.isCancelled, isTrue);
    newResult.complete(newImage);
    await tester.pumpAndSettle();
    oldResult.complete(oldImage);
    await tester.pumpAndSettle();
    expect(
      tester.widget<RawImage>(find.byType(RawImage)).image,
      same(newImage),
    );
    expect(oldImage.debugDisposed, isTrue);
    expect(newImage.debugDisposed, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(tokens['/new.pdf']!.isCancelled, isTrue);
    expect(newImage.debugDisposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('封面加载中退出会取消，完成后的图像被释放', (tester) async {
    final image = await _image(tester);
    final result = Completer<ui.Image?>();
    TextbookCoverToken? token;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          textbookCoverRendererProvider.overrideWithValue((_, value) {
            token = value;
            return result.future;
          }),
        ],
        child: const MaterialApp(
          home: TextbookPdfCover(path: '/sample.pdf', title: '测试书籍'),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    expect(token!.isCancelled, isTrue);
    result.complete(image);
    await tester.pumpAndSettle();
    expect(image.debugDisposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('封面渲染失败保留书名和占位，不抛出页面异常', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          textbookCoverRendererProvider.overrideWithValue(
            (_, __) async => throw StateError('render failed'),
          ),
        ],
        child: const MaterialApp(
          home: TextbookPdfCover(path: '/sample.pdf', title: '测试书籍'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('测试书籍'), findsOneWidget);
    expect(find.text('封面暂不可用'), findsOneWidget);
    expect(find.byType(RawImage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
