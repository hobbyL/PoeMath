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
