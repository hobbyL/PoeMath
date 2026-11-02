import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/data/models/picture_story_prompt.dart';

import '../../helpers/picture_story_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PictureStoryImageService service;
  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('picture_story_images_test_');
    service =
        PictureStoryImageService(directoryProvider: () async => directory);
  });
  tearDown(() => directory.delete(recursive: true));

  test('真实 PNG 导入、SHA 去重和新服务读取，原文件保持不变', () async {
    final bytes = await pictureStoryPng();
    final source = File('${directory.path}/source.png');
    await source.writeAsBytes(bytes);
    final image = await service.importPath(source.path);
    expect(image.kind, PictureStoryImageKind.local);
    final stored = await service.readImage(image.value);
    expect(image.value, sha256.convert(stored).toString());
    expect(ByteData.sublistView(stored).getUint32(16), 4);
    expect(ByteData.sublistView(stored).getUint32(20), 3);
    expect(await source.readAsBytes(), bytes);
    final duplicate = await service.importPath(source.path);
    expect(duplicate, image);
    final files = await Directory('${directory.path}/picture_story/images')
        .list()
        .toList();
    expect(
      files.map((file) => file.path),
      ['${directory.path}/picture_story/images/${image.value}.png'],
    );
    final reopened =
        PictureStoryImageService(directoryProvider: () async => directory);
    expect(await reopened.readImage(image.value), stored);
    await reopened.ensureStored(image);
  });

  test('大图按完整宽高比缩小到 1600px，未裁切为缩略图', () async {
    final source = File('${directory.path}/large.png');
    await source.writeAsBytes(await pictureStoryPng(width: 2100, height: 1200));
    final image = await service.importPath(source.path);
    final bytes = await service.readImage(image.value);
    expect(ByteData.sublistView(bytes).getUint32(16), 1600);
    expect(ByteData.sublistView(bytes).getUint32(20), 914);
    expect(
      bytes.length,
      lessThanOrEqualTo(PictureStoryImageService.maxStoredBytes),
    );
  });

  test('复杂题图的视觉上传副本不超过 512 KiB，保持比例且不修改永久题图', () async {
    final source = await pictureStoryNoisePng();
    final storedImage = await service.importBytes(source);
    final stored = await service.readImage(storedImage.value);
    expect(stored.length, greaterThan(PictureStoryImageService.maxUploadBytes));
    final upload = await service.readForVision(storedImage.value);
    expect(
      upload.length,
      lessThanOrEqualTo(PictureStoryImageService.maxUploadBytes),
    );
    final header = ByteData.sublistView(upload);
    expect(header.getUint32(16) / header.getUint32(20), closeTo(4 / 3, .01));
    expect(await service.readImage(storedImage.value), stored);
    final codec = await ui.instantiateImageCodec(upload);
    final frame = await codec.getNextFrame();
    frame.image.dispose();
    codec.dispose();
  });

  test('超限来源在规范化之前拒绝，不发布图片', () async {
    final source = File('${directory.path}/oversized.png');
    final handle = await source.open(mode: FileMode.write);
    await handle.truncate(PictureStoryImageService.maxSourceBytes + 1);
    await handle.close();
    await expectLater(
      service.importPath(source.path),
      throwsA(isA<PictureStoryImageException>()),
    );
    expect(
      await Directory('${directory.path}/picture_story').exists(),
      isFalse,
    );
    expect(await source.length(), PictureStoryImageService.maxSourceBytes + 1);
  });

  test('有效头但损坏的 PNG 在完整解码时拒绝，所有文件尚未发布', () async {
    final valid = await pictureStoryPng();
    final broken = Uint8List.fromList(valid.sublist(0, 33));
    final validId = sha256.convert(valid).toString();
    final brokenId = sha256.convert(broken).toString();
    await expectLater(
      service.prepareImages({validId: valid, brokenId: broken}),
      throwsA(isA<Object>()),
    );
    expect(
      await Directory('${directory.path}/picture_story').exists(),
      isFalse,
    );
  });

  test('备份图片验证 SHA 和尺寸，缺失或损坏图片不会冒充内置插图', () async {
    final bytes = await pictureStoryPng();
    final id = sha256.convert(bytes).toString();
    expect(
      () => PictureStoryImageService.validateStoredBytes('0' * 64, bytes),
      throwsFormatException,
    );
    await expectLater(
      service.readImage(id),
      throwsA(isA<PictureStoryImageException>()),
    );
    final prepared = await service.prepareImages({id: bytes});
    await prepared.publish();
    await prepared.discard();
    final path = await service.imagePath(id);
    await File(path!).writeAsBytes([1, 2, 3]);
    await expectLater(
      service.ensureStored(PictureStoryImage.local(id)),
      throwsFormatException,
    );
    final repair = await service.prepareImages({id: bytes});
    await repair.publish();
    await repair.discard();
    expect(await service.readImage(id), bytes);
  });
}
