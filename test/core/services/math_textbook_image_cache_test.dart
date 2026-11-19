import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/math_textbook_image_cache.dart';
import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/data/models/math_textbook_course.dart';

import '../../helpers/math_textbook_learning_fixture.dart';
import '../../helpers/textbook_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final book = textbookFixture();
  final lesson = mathLearningFixture();
  final point = lesson.learning!.knowledgePoints.single;
  final key = mathTextbookKnowledgeCacheKey(point, lesson.blocks);
  const region = MathTextbookRegion(
    page: 1,
    left: .2,
    top: .2,
    right: .8,
    bottom: .5,
  );
  late Directory root;
  TextbookContentCache reopen() =>
      TextbookContentCache(book: book, directoryProvider: () async => root);
  Future<List<File>> cachedFiles() async =>
      root.list(recursive: true).where((f) => f is File).cast<File>().toList();
  Future<ui.Image> render({int width = 12}) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), 16),
      ui.Paint()..color = const ui.Color(0xFF204080),
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, 16);
    } finally {
      picture.dispose();
    }
  }

  Future<ui.Image> loadImage(
    TextbookContentCache cache,
    Future<ui.Image> Function() load, {
    bool example = false,
  }) => cachedMathTextbookImage(
    cache: cache,
    source: region,
    workedExample: example,
    checkAvailable: () {},
    render: load,
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('math-image-cache-');
  });
  tearDown(() => root.delete(recursive: true));

  test('定位和PNG落在本书目录，重建缓存实例后不再提取或渲染，像素保持一致', () async {
    var extractions = 0, renders = 0;
    final first = reopen();
    final regions = await first.mathKnowledgeRegions(key, () async {
      extractions++;
      return [region];
    });
    expect(regions.single, region);
    final original = await loadImage(first, () {
      renders++;
      return render();
    });
    final pixels = (await original.toByteData())!.buffer.asUint8List();
    original.dispose();
    final second = reopen();
    expect(
      (await second.mathKnowledgeRegions(key, () async {
        extractions++;
        return [];
      })).single.toJson(),
      region.toJson(),
    );
    final cached = await loadImage(second, () {
      renders++;
      return render(width: 20);
    });
    expect((cached.width, cached.height), (12, 16));
    expect((await cached.toByteData())!.buffer.asUint8List(), pixels);
    cached.dispose();
    expect((extractions, renders), (1, 1));
    final files = await cachedFiles();
    expect(files.length, 2);
    expect(
      files.every(
        (f) =>
            f.parent.path == '${root.path}/textbooks/cache/${book.pdfSha256}',
      ),
      isTrue,
    );
    expect(files.any((f) => f.path.endsWith('.pending')), isFalse);
  });

  test('做一做的例题裁切与普通原题图分别缓存，第二次均直接命中', () async {
    var renders = 0;
    for (final example in [true, false]) {
      final first = await loadImage(reopen(), () {
        renders++;
        return render(width: example ? 20 : 12);
      }, example: example);
      first.dispose();
    }
    for (final example in [true, false]) {
      final hit = await loadImage(
        reopen(),
        () => throw StateError('不应重渲染'),
        example: example,
      );
      expect(hit.width, example ? 20 : 12);
      hit.dispose();
    }
    expect(renders, 2);
  });

  test('手动清理本书内容缓存后才重处理，原书和封面保留', () async {
    final files = TextbookFileService(directoryProvider: () async => root);
    final cache = files.contentCache(book);
    var extractions = 0, renders = 0;
    Future<void> visit() async {
      await cache.mathKnowledgeRegions(key, () async {
        extractions++;
        return [region];
      });
      final image = await loadImage(cache, () {
        renders++;
        return render();
      });
      image.dispose();
    }

    await visit();
    final cover = await File(
      '${root.path}/textbooks/cache/${book.pdfSha256}/cover-v1.png',
    ).writeAsBytes([1, 2, 3]);
    final pdf = await File('${root.path}/textbooks/${book.pdfSha256}.pdf')
        .writeAsBytes([4, 5, 6]);
    await visit();
    expect((extractions, renders), (1, 1));
    await files.clearExtractedContent(book);
    expect((await files.storageUsage(book)).contentFiles, 0);
    expect(await cover.readAsBytes(), [1, 2, 3]);
    expect(await pdf.readAsBytes(), [4, 5, 6]);
    await visit();
    expect((extractions, renders), (2, 2));
    expect((await files.storageUsage(book)).contentFiles, 2);
  });

  test('清理期间晚到的定位和图像不能写回旧缓存，旧位图被释放', () async {
    final cache = reopen();
    final extracting = Completer<List<MathTextbookRegion>>();
    final started = Completer<void>();
    final task = cache.mathKnowledgeRegions(key, () {
      started.complete();
      return extracting.future;
    });
    final failure = expectLater(task, throwsStateError);
    await started.future;
    await cache.clearExtracted();
    extracting.complete([region]);
    await failure;
    final rendering = Completer<ui.Image>();
    final renderStarted = Completer<void>();
    final imageTask = loadImage(cache, () {
      renderStarted.complete();
      return rendering.future;
    });
    final imageFailure = expectLater(imageTask, throwsStateError);
    await renderStarted.future;
    await cache.clearExtracted();
    final lateImage = await render();
    rendering.complete(lateImage);
    await imageFailure;
    expect(lateImage.debugDisposed, isTrue);
    expect(await cachedFiles(), isEmpty);
    final fresh = await loadImage(cache, render);
    fresh.dispose();
    expect((await cachedFiles()).single.path, endsWith('.png'));
  });

  test('空配图结果可缓存，提取失败不缓存；损坏文件允许重建', () async {
    await expectLater(
      reopen().mathKnowledgeRegions(key, () => throw StateError('提取失败')),
      throwsStateError,
    );
    expect(await cachedFiles(), isEmpty);
    await reopen().mathKnowledgeRegions(key, () async => []);
    expect(
      await reopen().mathKnowledgeRegions(
        key,
        () => throw StateError('不应重读空结果'),
      ),
      isEmpty,
    );
    final index = (await cachedFiles()).single;
    await index.writeAsString('{broken');
    expect(await reopen().mathKnowledgeRegions(key, () async => [region]), [
      region,
    ]);
    final first = await loadImage(reopen(), render);
    first.dispose();
    final png = (await cachedFiles()).singleWhere(
      (file) => file.path.endsWith('.png'),
    );
    await png.writeAsBytes([1, 2, 3]);
    final repaired = await loadImage(reopen(), () => render(width: 20));
    expect(repaired.width, 20);
    repaired.dispose();
  });

  test('不同书籍和修改后的知识内容不复用旧图，写入失败仍可显示', () async {
    await reopen().mathKnowledgeRegions(key, () async => [region]);
    final other = TextbookContentCache(
      book: textbookFixture(id: 'b' * 64),
      directoryProvider: () async => root,
    );
    expect(await other.mathKnowledgeRegions(key, () async => []), isEmpty);
    final changed = MathTextbookKnowledgePoint(
      id: point.id,
      title: point.title,
      summary: '修改后的方法。',
      blockIds: point.blockIds,
    );
    expect(
      await reopen().mathKnowledgeRegions(
        mathTextbookKnowledgeCacheKey(changed, lesson.blocks),
        () async => [],
      ),
      isEmpty,
    );
    final blocker = await File('${root.path}/blocker').writeAsString('file');
    final unavailable = TextbookContentCache(
      book: book,
      directoryProvider: () async => Directory(blocker.path),
    );
    expect(await unavailable.mathKnowledgeRegions(key, () async => [region]), [
      region,
    ]);
    final image = await loadImage(unavailable, render);
    expect((image.width, image.height), (12, 16));
    image.dispose();
  });
}
