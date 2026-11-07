import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_scene_contrast.dart';

import '../../../helpers/picture_story_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PictureStorySceneContrast pixels;

  setUpAll(() async {
    pixels = await PictureStorySceneContrast.decode(
      await pictureStoryContrastPng(),
    );
  });

  bool lightAt(
    Rect rect, {
    double offset = 0,
    double parallax = .7,
    Size viewport = const Size(400, 900),
    Size imageSize = const Size.square(400),
    Color background = Colors.white,
  }) => pixels.useLightForeground(
    iconRect: rect,
    viewport: viewport,
    imageSize: imageSize,
    scrollOffset: offset,
    parallaxFactor: parallax,
    background: background,
  );

  test('缩略图缓存不超过 96px，按每个按钮下方局部明暗选择颜色', () {
    expect(pixels.width, 96);
    expect(pixels.height, 96);
    expect(lightAt(const Rect.fromLTWH(16, 40, 24, 24)), isTrue);
    expect(lightAt(const Rect.fromLTWH(316, 40, 24, 24)), isFalse);
    expect(lightAt(const Rect.fromLTWH(368, 40, 24, 24)), isTrue);
  });

  test('滚动按视差实际位移取样，关闭动画后按普通位移取样', () {
    const icon = Rect.fromLTWH(16, 40, 24, 24);
    expect(lightAt(icon, offset: 90), isTrue);
    expect(lightAt(icon, offset: 90, parallax: 0), isFalse);
    expect(lightAt(icon, offset: 220), isFalse);
  });

  test('下拉放大后顶部仍从图片取色，并按等比放大后的横向位置取样', () {
    const left = Rect.fromLTWH(16, 40, 24, 24);
    const right = Rect.fromLTWH(368, 40, 24, 24);
    expect(lightAt(left, offset: -200), isTrue);
    expect(lightAt(right), isTrue);
    expect(lightAt(right, offset: -200), isFalse);
  });

  test('横屏完整题图按居中位置取色，两侧按铺满的模糊背景取色', () {
    const viewport = Size(800, 600);
    const imageSize = Size.square(220);
    expect(
      lightAt(
        const Rect.fromLTWH(16, 40, 24, 24),
        viewport: viewport,
        imageSize: imageSize,
      ),
      isFalse,
    );
    expect(
      lightAt(
        const Rect.fromLTWH(16, 40, 24, 24),
        viewport: viewport,
        imageSize: imageSize,
        background: Colors.black,
      ),
      isFalse,
    );
    expect(
      lightAt(
        const Rect.fromLTWH(306, 12, 24, 24),
        viewport: viewport,
        imageSize: imageSize,
      ),
      isTrue,
    );
    expect(
      lightAt(
        const Rect.fromLTWH(436, 12, 24, 24),
        viewport: viewport,
        imageSize: imageSize,
      ),
      isFalse,
    );
    expect(
      lightAt(
        const Rect.fromLTWH(620, 40, 24, 24),
        viewport: viewport,
        imageSize: imageSize,
      ),
      isTrue,
    );
  });

  test('横屏下拉放大覆盖到侧边后，从模糊背景取色切换为清晰图片取色', () {
    const icon = Rect.fromLTWH(220, 12, 24, 24);
    const viewport = Size(800, 600);
    const imageSize = Size.square(220);
    expect(lightAt(icon, viewport: viewport, imageSize: imageSize), isFalse);
    expect(
      lightAt(icon, viewport: viewport, imageSize: imageSize, offset: -200),
      isTrue,
    );
  });

  test('内容覆盖图片后使用页面背景明暗', () {
    const icon = Rect.fromLTWH(16, 40, 24, 24);
    expect(lightAt(icon, offset: 400), isFalse);
    expect(lightAt(icon, offset: 400, background: Colors.black), isTrue);
  });

  Future<PictureStorySceneContrast> solid(Color color) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(color, ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(4, 4);
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      return await PictureStorySceneContrast.decode(
        Uint8List.fromList(bytes.buffer.asUint8List()),
      );
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  test('临界灰度保留上一种颜色，避免滚动时频繁闪变', () async {
    final grey = await solid(const Color(0xff848484));
    for (final previous in [false, true]) {
      expect(
        grey.useLightForeground(
          iconRect: const Rect.fromLTWH(16, 40, 24, 24),
          viewport: const Size(400, 900),
          imageSize: const Size.square(400),
          scrollOffset: 0,
          parallaxFactor: .7,
          background: Colors.white,
          previous: previous,
        ),
        previous,
      );
    }
  });

  test('透明图片取样时与实际页面背景合成', () async {
    final transparent = await solid(Colors.transparent);
    for (final background in [Colors.white, Colors.black]) {
      expect(
        transparent.useLightForeground(
          iconRect: const Rect.fromLTWH(16, 40, 24, 24),
          viewport: const Size(400, 900),
          imageSize: const Size.square(400),
          scrollOffset: 0,
          parallaxFactor: .7,
          background: background,
        ),
        background == Colors.black,
      );
    }
  });
}
