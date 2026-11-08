import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/color_tokens.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/models/picture_story_prompt.dart';
import 'package:poemath/features/chinese/expression/picture_story_page.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_scene_contrast.dart';

import '../../../helpers/picture_story_fixture.dart';

Future<Uint8List> _cornerImage({required bool darkCorner}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final corner = darkCorner ? Colors.black : Colors.white;
  canvas.drawColor(darkCorner ? Colors.white : Colors.black, BlendMode.src);
  canvas.drawRect(
    const Rect.fromLTWH(300, 0, 100, 100),
    Paint()..color = corner,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(400, 400);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('记录图标透明且按每张图右上角取色，旋转和换图后同步：$brightness', (tester) async {
      final darkCorner = (await tester.runAsync(
        () => _cornerImage(darkCorner: true),
      ))!;
      final lightCorner = (await tester.runAsync(
        () => _cornerImage(darkCorner: false),
      ))!;
      final images = {'dark-corner': darkCorner, 'light-corner': lightCorner};
      final loads = <String, int>{};
      final prompts = [
        pictureStoryFixture(
          id: 'dark-corner',
          image: const PictureStoryImage.local('dark-corner'),
        ),
        pictureStoryFixture(
          id: 'light-corner',
          image: const PictureStoryImage.local('light-corner'),
        ),
      ];
      final records = [
        for (var index = 0; index < prompts.length; index++)
          for (var count = 0; count <= index; count++)
            PictureStoryPracticeRecord(
              id: '$index-$count',
              profileId: 'default',
              promptId: prompts[index].id,
              promptVersion: 1,
              startedAt: DateTime(2026),
              status: 'completed',
              segmentsJson: '[]',
            ),
      ];
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 700);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pictureStoryPromptProvider.overrideWithValue(prompts),
            pictureStoryHistoryProvider.overrideWithValue(records),
            pictureStoryImageBytesProvider.overrideWith((ref, id) async {
              loads[id] = (loads[id] ?? 0) + 1;
              return images[id]!;
            }),
          ],
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: const PictureStoryPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PictureStoryPage)),
      );
      Future<void> waitForPixels() async {
        final providers = [
          for (final prompt in prompts)
            pictureStorySceneContrastProvider((
              image: prompt.image,
              imageBytes: images[prompt.id],
              builtinScheme: null,
            )),
        ];
        for (
          var i = 0;
          i < 60 &&
              providers.any(
                (provider) => container.read(provider).valueOrNull == null,
              );
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        for (final provider in providers) {
          expect(container.read(provider).valueOrNull, isNotNull);
        }
        await tester.pumpAndSettle();
      }

      await waitForPixels();
      final first = find.byTooltip('练习记录 · 1 次');
      final second = find.byTooltip('练习记录 · 2 次');
      Color? color(Finder button) => IconTheme.of(
        tester.element(
          find.descendant(of: button, matching: find.byType(Icon)),
        ),
      ).color;
      expect(color(first), ColorTokens.mathSurface);
      expect(color(second), ColorTokens.poemInk);
      expect(find.text('练习记录 · 1 次'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      for (final button in [first, second]) {
        final theme = IconButtonTheme.of(tester.element(button));
        expect(theme.style!.backgroundColor!.resolve({}), Colors.transparent);
        final rect = tester.getRect(button);
        expect(rect.width, greaterThanOrEqualTo(SpacingTokens.minTapTarget));
        expect(rect.height, greaterThanOrEqualTo(SpacingTokens.minTapTarget));
      }
      tester.view.physicalSize = const Size(400, 900);
      await tester.pumpAndSettle();
      expect(color(first), ColorTokens.mathSurface);
      await tester.scrollUntilVisible(second, 200);
      await tester.pumpAndSettle();
      expect(color(second), ColorTokens.poemInk);
      expect(loads, {'dark-corner': 1, 'light-corner': 1});

      images['light-corner'] = darkCorner;
      container.invalidate(pictureStoryImageBytesProvider('light-corner'));
      await tester.pumpAndSettle();
      await waitForPixels();
      expect(color(second), ColorTokens.mathSurface);
      expect(loads, {'dark-corner': 1, 'light-corner': 2});
      await tester.longPress(second);
      await tester.pumpAndSettle();
      expect(find.text('练习记录 · 2 次'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
