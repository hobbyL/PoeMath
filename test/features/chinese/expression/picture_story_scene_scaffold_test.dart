import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/widgets/page_animation_scope.dart';
import 'package:poemath/data/models/picture_story_prompt.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_view.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_scene_scaffold.dart';

import '../../../helpers/picture_story_fixture.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(400, 900),
    double textScale = 1,
    bool disableAnimations = false,
    bool pageAnimations = true,
    Brightness brightness = Brightness.light,
    VoidCallback? onComplete,
    Uint8List? imageBytes,
    Future<Uint8List> Function()? loadImage,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (imageBytes != null || loadImage != null)
            pictureStoryImageBytesProvider.overrideWith(
              (ref, id) async => loadImage == null ? imageBytes! : loadImage(),
            ),
        ],
        child: PageAnimationScope(
          enabled: pageAnimations,
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                disableAnimations: disableAnimations,
              ),
              child: child!,
            ),
            home: PictureStorySceneScaffold(
              image: imageBytes == null && loadImage == null
                  ? const PictureStoryImage.builtin('kite')
                  : const PictureStoryImage.local('fixture-image'),
              semanticLabel: '题目练习记录',
              actions: [
                IconButton(
                  tooltip: '完成练习',
                  onPressed: onComplete,
                  icon: const Icon(Icons.check_outlined),
                ),
              ],
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('题目内容'),
                  SizedBox(height: 700),
                  TextField(decoration: InputDecoration(labelText: '我的表达')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('内容上移覆盖题图，题图慢速上移，返回和完成按钮固定可点', (tester) async {
    var completions = 0;
    await mount(tester, onComplete: () => completions++);
    final backBefore = tester.getRect(find.byType(BackButton));
    final actionBefore = tester.getRect(find.byTooltip('完成练习'));
    final imageBefore = tester.getRect(find.byType(PictureStoryImageView));
    final contentBefore = tester.getRect(find.text('题目内容'));
    expect(find.byType(AppBar), findsNothing);
    expect(backBefore.center, const Offset(28, 52));
    expect(imageBefore.left, 0);
    expect(imageBefore.top, 0);
    expect(imageBefore.right, 400);

    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(160);
    await tester.pump();
    final imageAfter = tester.getRect(find.byType(PictureStoryImageView));
    final contentAfter = tester.getRect(find.text('题目内容'));
    expect(contentBefore.top - contentAfter.top, closeTo(160, .01));
    expect(imageBefore.top - imageAfter.top, greaterThan(0));
    expect(imageBefore.top - imageAfter.top, lessThan(160));
    expect(tester.getRect(find.byType(BackButton)), backBefore);
    expect(tester.getRect(find.byTooltip('完成练习')), actionBefore);
    await tester.tap(find.byTooltip('完成练习'));
    expect(completions, 1);
    expect(tester.takeException(), isNull);
  });

  for (final systemPreference in [true, false]) {
    testWidgets('关闭动画后题图随内容正常滚动（系统设置：$systemPreference）', (tester) async {
      await mount(
        tester,
        disableAnimations: systemPreference,
        pageAnimations: systemPreference,
      );
      final imageBefore = tester.getRect(find.byType(PictureStoryImageView));
      final contentBefore = tester.getRect(find.text('题目内容'));
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(160);
      await tester.pump();
      final imageAfter = tester.getRect(find.byType(PictureStoryImageView));
      final contentAfter = tester.getRect(find.text('题目内容'));
      expect(imageBefore.top - imageAfter.top, closeTo(160, .01));
      expect(contentBefore.top - contentAfter.top, closeTo(160, .01));
      expect(find.byType(BackButton).hitTestable(), findsOneWidget);
    });
  }

  for (final size in [const Size(320, 900), const Size(1100, 600)]) {
    testWidgets('窄屏大字与横屏背景铺满宽度，插图不变形且返回固定：$size', (tester) async {
      await mount(
        tester,
        size: size,
        textScale: 2,
        brightness: Brightness.dark,
      );
      final image = tester.getRect(find.byType(PictureStoryImageView));
      expect(image.left, 0);
      expect(image.right, size.width);
      expect(image.bottom, lessThanOrEqualTo(size.height * .55));
      final scene = tester.getRect(
        find.descendant(
          of: find.byType(PictureStoryImageView),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(scene.width / scene.height, closeTo(4 / 3, .01));
      expect(scene.left, lessThanOrEqualTo(image.left));
      expect(scene.right, greaterThanOrEqualTo(image.right));
      final back = tester.getRect(find.byType(BackButton));
      expect(back.top, greaterThanOrEqualTo(24));
      expect(back.width, greaterThanOrEqualTo(44));
      expect(back.height, greaterThanOrEqualTo(44));
      await tester.scrollUntilVisible(
        find.byType(TextField),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      expect(tester.getRect(find.byType(BackButton)), back);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('键盘出现不会改变题图高度或浮动按钮位置', (tester) async {
    await mount(tester);
    final image = tester.getRect(find.byType(PictureStoryImageView));
    final back = tester.getRect(find.byType(BackButton));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(tester.getRect(find.byType(PictureStoryImageView)), image);
    expect(tester.getRect(find.byType(BackButton)), back);
    await tester.scrollUntilVisible(
      find.byType(TextField),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextField), '我的表达');
    expect(find.text('我的表达'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final dimensions in [(16, 9), (1, 1), (3, 4)]) {
    testWidgets('本地题图等比铺满宽度，背景高度跟随原图：$dimensions', (tester) async {
      final bytes = (await tester.runAsync(
        () => pictureStoryPng(width: dimensions.$1, height: dimensions.$2),
      ))!;
      await mount(tester, imageBytes: bytes);
      final image = tester.getRect(find.byType(Image));
      final naturalHeight = 400 * dimensions.$2 / dimensions.$1;
      expect(image.height, closeTo(naturalHeight.clamp(0, 900 * .55), .01));
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
      expect(image.left, 0);
      expect(image.right, 400);
      expect(
        image.bottom,
        lessThanOrEqualTo(tester.getRect(find.text('题目内容')).top),
      );
      expect(find.byType(BackButton).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('宽屏本地题图等比铺满背景，两侧无留白', (tester) async {
    final bytes = (await tester.runAsync(
      () => pictureStoryPng(width: 1, height: 1),
    ))!;
    await mount(tester, size: const Size(1100, 600), imageBytes: bytes);
    final image = tester.getRect(find.byType(Image));
    expect(image.left, 0);
    expect(image.right, 1100);
    expect(image.height, 330);
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
    expect(tester.takeException(), isNull);
  });

  testWidgets('背景题图读取失败时重新加载入口仍可点击', (tester) async {
    final bytes = (await tester.runAsync(pictureStoryPng))!;
    var attempts = 0;
    await mount(
      tester,
      loadImage: () async {
        if (++attempts == 1) throw StateError('synthetic image failure');
        return bytes;
      },
    );
    expect(find.text('图片暂时无法显示'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('图片暂时无法显示'), findsNothing);
  });
}
