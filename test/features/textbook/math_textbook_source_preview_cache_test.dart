import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/math_textbook_image_cache.dart';
import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_knowledge_images.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_source_preview.dart';

import '../../helpers/math_textbook_fixture.dart';
import '../../helpers/math_textbook_learning_fixture.dart';

class _DelayedFiles extends TextbookFileService {
  _DelayedFiles(Directory root) : super(directoryProvider: () async => root);
  Completer<String?>? pending;
  @override
  Future<String?> installedPath(Textbook book) async =>
      pending == null ? '/self-owned.pdf' : await pending!.future;
}

void main() {
  final book = mathTextbookFixture();
  final lesson = mathLearningFixture();
  final point = lesson.learning!.knowledgePoints.single;
  const source = MathTextbookRegion(
    page: 1,
    left: .1,
    top: .2,
    right: .9,
    bottom: .4,
  );
  late Directory root;
  late _DelayedFiles files;
  late ui.Image retained;
  var renders = 0;

  Future<ui.Image> render() async {
    renders++;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
        .drawRect(const ui.Rect.fromLTWH(0, 0, 40, 20), ui.Paint());
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(40, 20);
    } finally {
      picture.dispose();
    }
  }

  Widget app(Widget child) => ProviderScope(
    overrides: [
      textbookFileServiceProvider.overrideWithValue(files),
      mathTextbookRegionRendererProvider.overrideWithValue((
        path,
        source,
        token,
      ) async {
        token.check();
        return render();
      }),
      mathTextbookKnowledgeImageLoaderProvider.overrideWithValue(
        (path, point, blocks, token) async => throw StateError('已定位配图不应重新提取'),
      ),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );

  setUp(() async {
    TextbookContentCache.clearMathImageMemory();
    root = await Directory.systemTemp.createTemp('math-preview-first-frame-');
    files = _DelayedFiles(root);
    renders = 0;
    final cache = files.contentCache(book);
    retained = await cachedMathTextbookImage(
      cache: cache,
      source: source,
      workedExample: false,
      checkAvailable: () {},
      render: render,
    );
    await cache.mathKnowledgeRegions(
      mathTextbookKnowledgeCacheKey(point, lesson.blocks),
      () async => [source],
    );
  });

  tearDown(() async {
    retained.dispose();
    TextbookContentCache.clearMathImageMemory();
    await root.delete(recursive: true);
  });

  for (final knowledge in [false, true]) {
    testWidgets('再次进入${knowledge ? '学一学' : '做一做'}，磁盘检查未完成时首帧已有图且没有转圈', (
      tester,
    ) async {
      files.pending = Completer<String?>();
      Widget content() => knowledge
          ? MathTextbookKnowledgeImages(
              book: book,
              point: point,
              blocks: lesson.blocks,
            )
          : MathTextbookSourcePreview(book: book, source: source);
      for (var visit = 0; visit < 2; visit++) {
        await tester.pumpWidget(app(content()));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        final preview = tester.widget<RawImage>(find.byType(RawImage));
        expect(preview.image!.isCloneOf(retained), isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      files.pending!.complete('/self-owned.pdf');
      await tester.pump();
      expect(renders, 1);
      expect(retained.debugDisposed, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('切换到未缓存题目或清理缓存后，不显示上一题的位图', (tester) async {
    files.pending = Completer<String?>();
    await tester.pumpWidget(
      app(MathTextbookSourcePreview(book: book, source: source)),
    );
    expect(find.byType(RawImage), findsOneWidget);
    await tester.pumpWidget(
      app(
        MathTextbookSourcePreview(
          book: book,
          source: const MathTextbookRegion(
            page: 2,
            left: .1,
            top: .2,
            right: .9,
            bottom: .4,
          ),
        ),
      ),
    );
    expect(find.byType(RawImage), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => files.clearExtractedContent(book));
    await tester.pumpWidget(
      app(
        MathTextbookKnowledgeImages(
          book: book,
          point: point,
          blocks: lesson.blocks,
        ),
      ),
    );
    expect(find.byType(RawImage), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    files.pending!.complete('/self-owned.pdf');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
