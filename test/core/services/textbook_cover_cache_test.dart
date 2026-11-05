import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/textbook_cover_cache.dart';

/// Profile / Release 禁止访问 debugDisposed，即使真实测试图像开启了断言。
class _ProductionImage implements ui.Image {
  _ProductionImage(this.image);

  final ui.Image image;

  @override
  bool get debugDisposed => throw StateError('生产模式不提供 debugDisposed');

  @override
  int get width => image.width;

  @override
  int get height => image.height;

  @override
  ui.Image clone() => _ProductionImage(image.clone());

  @override
  void dispose() => image.dispose();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ui.Image> _renderImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = Colors.blue,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cache = TextbookCoverCache();
  final id = 'a' * 64;

  late Directory root;
  late String pdfPath;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('poemath-cover-cache');
    pdfPath = '${root.path}${Platform.pathSeparator}$id.pdf';
  });

  tearDown(() async {
    TextbookCoverCache.clearMemory();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('生产模式反复读取封面和统计内存不依赖调试属性，释放副本不影响缓存', () async {
    final original = _ProductionImage(await _renderImage(12, 16));
    cache.remember(pdfPath, original);
    original.dispose();

    expect(TextbookCoverCache.memoryUsage.bytes, 12 * 16 * 4);
    expect(TextbookCoverCache.memoryUsage.entries, 1);
    final first = cache.take(pdfPath)!;
    expect((first.width, first.height), (12, 16));
    first.dispose();
    final second = cache.take(pdfPath)!;
    expect((second.width, second.height), (12, 16));
    second.dispose();

    cache.forget(pdfPath);
    expect(cache.take(pdfPath), isNull);
    expect(TextbookCoverCache.memoryUsage.bytes, 0);
    expect(TextbookCoverCache.memoryUsage.entries, 0);
  });

  test('只认 <sha256>.pdf，缓存落在派生缓存目录', () {
    expect(
      cache.fileFor(pdfPath)!.path,
      '${root.path}${Platform.pathSeparator}cache'
      '${Platform.pathSeparator}$id'
      '${Platform.pathSeparator}cover-v1.png',
    );
    expect(cache.fileFor('${root.path}/not-a-sha.pdf'), isNull);
    expect(cache.fileFor('${root.path}/$id.txt'), isNull);
  });

  test('写一次后能读回，重复写覆盖旧文件', () async {
    expect(await cache.read(pdfPath), isNull);

    final first = await _renderImage(12, 16);
    await cache.write(pdfPath, first);
    first.dispose();

    final file = cache.fileFor(pdfPath)!;
    expect(await file.exists(), isTrue);

    final loaded = await cache.read(pdfPath);
    expect(loaded, isNotNull);
    expect(loaded!.width, 12);
    expect(loaded.height, 16);
    loaded.dispose();

    final second = await _renderImage(24, 32);
    await cache.write(pdfPath, second);
    second.dispose();

    final reloaded = await cache.read(pdfPath);
    expect(reloaded!.width, 24, reason: '新写入覆盖旧封面');
    reloaded.dispose();
    expect(
      await file.parent.list().where((e) => e.path.endsWith('.pending')).length,
      0,
      reason: '不残留临时文件',
    );
  });

  test('缓存损坏时删除并回退为未命中', () async {
    final file = cache.fileFor(pdfPath)!;
    await file.parent.create(recursive: true);
    await file.writeAsBytes(const [1, 2, 3]);

    expect(await cache.read(pdfPath), isNull);
    expect(await file.exists(), isFalse, reason: '坏文件要清掉才能重新生成');
  });

  test('清理会等待在途写入，旧渲染不能重新写回磁盘或内存', () async {
    final image = await _renderImage(12, 16);
    addTearDown(image.dispose);
    final generation = cache.revision(pdfPath);
    final writing = cache.write(pdfPath, image, generation: generation);
    final clearing = cache.clear(pdfPath, authorize: () {});
    await Future.wait([writing, clearing]);
    await cache.write(pdfPath, image, generation: generation);
    cache.remember(pdfPath, image, generation: generation);
    expect(await cache.fileFor(pdfPath)!.exists(), isFalse);
    expect(cache.take(pdfPath), isNull);
    await cache.write(pdfPath, image);
    expect(await cache.fileFor(pdfPath)!.exists(), isTrue);
  });

  test('非法路径不读不写', () async {
    final bad = '${root.path}${Platform.pathSeparator}cover.pdf';
    expect(await cache.read(bad), isNull);

    final image = await _renderImage(4, 4);
    await cache.write(bad, image);
    image.dispose();
    expect(await File('${root.path}/cache').exists(), isFalse);
  });
}
