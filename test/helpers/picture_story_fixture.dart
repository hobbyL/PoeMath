import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:poemath/data/models/picture_story_prompt.dart';

PictureStoryPrompt pictureStoryFixture({
  String id = 'local-fixture',
  String title = '窗前的小猫',
  PictureStoryImage image = const PictureStoryImage.builtin('kite'),
}) =>
    PictureStoryPrompt(
      id: id,
      title: title,
      level: PictureStoryLevel.starter,
      theme: '观察与动作',
      sceneFacts: const ['小猫坐在窗前'],
      questions: const ['小猫在哪里？', '它在做什么？'],
      goals: const ['说清地点和动作'],
      reference: '一只小猫坐在窗前，看着外面的小鸟。',
      illustration: image.isLocal ? '' : image.value,
      imageId: image.isLocal ? image.value : null,
    );

Future<Uint8List> pictureStoryPng({int width = 4, int height = 3}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xff315c7a), ui.BlendMode.src);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width / 2, height.toDouble()),
    ui.Paint()..color = const ui.Color(0xffd7b87c),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// 固定随机种子的复杂 PNG，验证真实图像压缩和视觉请求的字节预算。
Future<Uint8List> pictureStoryNoisePng({
  int width = 1024,
  int height = 768,
}) async {
  final pixels = Uint8List(width * height * 4);
  final random = Random(42);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = random.nextInt(256);
    pixels[i + 1] = random.nextInt(256);
    pixels[i + 2] = random.nextInt(256);
    pixels[i + 3] = 255;
  }
  final ready = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    ready.complete,
  );
  final image = await ready.future;
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    image.dispose();
  }
}
