import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/textbook_cover_cache.dart';

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
    if (await root.exists()) await root.delete(recursive: true);
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

  test('非法路径不读不写', () async {
    final bad = '${root.path}${Platform.pathSeparator}cover.pdf';
    expect(await cache.read(bad), isNull);

    final image = await _renderImage(4, 4);
    await cache.write(bad, image);
    image.dispose();
    expect(await File('${root.path}/cache').exists(), isFalse);
  });
}
