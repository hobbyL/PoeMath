import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/cache_activity.dart';
import 'package:poemath/core/services/profile_avatar_image_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(
    () async => directory = await Directory.systemTemp.createTemp('avatar_'),
  );
  tearDown(() => directory.delete(recursive: true));

  test('系统选图后居中裁成 256px PNG，保留原图且不拉伸边缘', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..drawColor(const ui.Color(0xffff0000), ui.BlendMode.src)
      ..drawRect(
        const ui.Rect.fromLTWH(160, 0, 320, 320),
        ui.Paint()..color = const ui.Color(0xff00ff00),
      );
    final picture = recorder.endRecording();
    final source = await picture.toImage(640, 320);
    final png = (await source.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    source.dispose();
    picture.dispose();
    final file = await File('${directory.path}/photo.png').writeAsBytes(png);
    final service = ProfileAvatarImageService(pickPath: () async => file.path);
    final avatar = (await service.pick())!;
    final codec = await ui.instantiateImageCodec(avatar.bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 256);
    expect(frame.image.height, 256);
    final pixels = (await frame.image.toByteData())!;
    for (final x in [4, 128, 251]) {
      final offset = (128 * 256 + x) * 4;
      expect(pixels.getUint32(offset), 0x00ff00ff);
    }
    frame.image.dispose();
    codec.dispose();
    expect(await file.readAsBytes(), png);
    expect(avatar.bytes.length, lessThan(png.length + 4096));
  });

  test('取消选择返回空，错误图片和超大文件不生成头像', () async {
    expect(
      await ProfileAvatarImageService(pickPath: () async => null).pick(),
      isNull,
    );
    final file = await File('${directory.path}/bad.png')
        .writeAsString('not image');
    await expectLater(
      ProfileAvatarImageService(pickPath: () async => file.path).pick(),
      throwsA(anything),
    );
    final access = await file.open(mode: FileMode.write);
    await access.truncate(ProfileAvatarImageService.maxSourceBytes + 1);
    await access.close();
    await expectLater(
      ProfileAvatarImageService(pickPath: () async => file.path).pick(),
      throwsFormatException,
    );
    await expectLater(
      ProfileAvatarImageService.normalize(Uint8List(0)),
      throwsFormatException,
    );
  });

  test('选图期间阻止清理临时缓存，取消后释放租约', () async {
    final path = Completer<String?>();
    final picking = ProfileAvatarImageService(pickPath: () => path.future)
        .pick();
    await expectLater(
      CacheActivity.clear(TemporaryCacheKind.pickers, () async {}),
      throwsA(isA<CacheInUseException>()),
    );
    path.complete(null);
    await picking;
    var cleared = false;
    await CacheActivity.clear(
      TemporaryCacheKind.pickers,
      () async => cleared = true,
    );
    expect(cleared, isTrue);
  });
}
