import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/color_tokens.dart';
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
    bool accessibleNavigation = false,
    bool pageAnimations = true,
    Brightness brightness = Brightness.light,
    VoidCallback? onComplete,
    Uint8List? imageBytes,
    Future<Uint8List> Function()? loadImage,
    bool showHint = false,
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
                accessibleNavigation: accessibleNavigation,
              ),
              child: child!,
            ),
            home: PictureStorySceneScaffold(
              image: imageBytes == null && loadImage == null
                  ? const PictureStoryImage.builtin('kite')
                  : const PictureStoryImage.local('fixture-image'),
              semanticLabel: '题目练习记录',
              actions: [
                if (showHint)
                  IconButton(
                    tooltip: '隐藏提示',
                    isSelected: true,
                    onPressed: () {},
                    icon: const Icon(Icons.lightbulb_outline),
                    selectedIcon: const Icon(Icons.tips_and_updates_outlined),
                  ),
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

  for (final sample in [
    (size: const Size(400, 900), pageAnimations: true),
    (size: const Size(1100, 600), pageAnimations: true),
    (size: const Size(400, 900), pageAnimations: false),
  ]) {
    testWidgets('下拉等比放大图片且顶边无留白，按钮固定，松手回到原位：$sample', (tester) async {
      final bytes = (await tester.runAsync(pictureStoryContrastPng))!;
      var completions = 0;
      await mount(
        tester,
        size: sample.size,
        pageAnimations: sample.pageAnimations,
        imageBytes: bytes,
        onComplete: () => completions++,
      );
      final image = find.byType(PictureStoryImageView);
      final imageBefore = tester.getRect(image);
      final contentBefore = tester.getRect(find.text('题目内容'));
      final backBefore = tester.getRect(find.byType(BackButton));
      final actionBefore = tester.getRect(find.byTooltip('完成练习'));
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final gesture = await tester.startGesture(imageBefore.center);
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump(const Duration(milliseconds: 16));
      final enlarged = tester.getRect(image);
      expect(scroll.position.pixels, lessThan(0));
      expect(enlarged.top, closeTo(0, .01));
      expect(enlarged.width, greaterThan(imageBefore.width));
      expect(enlarged.height, greaterThan(imageBefore.height));
      expect(
        enlarged.width / enlarged.height,
        closeTo(imageBefore.width / imageBefore.height, .01),
      );
      expect(
        tester.getRect(find.text('题目内容')).top - contentBefore.top,
        closeTo(enlarged.bottom - imageBefore.bottom, .01),
      );
      expect(tester.getRect(find.byType(BackButton)), backBefore);
      expect(tester.getRect(find.byTooltip('完成练习')), actionBefore);
      // 停住再松手，验证回弹而非快速甩动产生的惯性滚动。
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, closeTo(0, .1));
      expect(tester.getRect(image).top, closeTo(imageBefore.top, .1));
      expect(tester.getRect(image).width, closeTo(imageBefore.width, .1));
      await tester.tap(find.byTooltip('完成练习'));
      expect(completions, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final systemPreference in [true, false]) {
    testWidgets('系统减少动态效果时保持普通滚动且不放大（禁用动画：$systemPreference）', (tester) async {
      await mount(
        tester,
        disableAnimations: systemPreference,
        accessibleNavigation: !systemPreference,
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
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pump();
      await tester.dragFrom(imageBefore.center, const Offset(0, 180));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(PictureStoryImageView)), imageBefore);
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

  testWidgets('三个按钮分别跟随局部明暗变色，滚出图片恢复主题色且保留点击', (tester) async {
    final bytes = (await tester.runAsync(pictureStoryContrastPng))!;
    var loads = 0;
    var completions = 0;
    await mount(
      tester,
      showHint: true,
      onComplete: () => completions++,
      loadImage: () async {
        loads++;
        return bytes;
      },
    );
    final back = find.descendant(
      of: find.byType(BackButton),
      matching: find.byType(Icon),
    );
    final hint = find.byIcon(Icons.tips_and_updates_outlined);
    final complete = find.byIcon(Icons.check_outlined);
    Color? color(Finder icon) => IconTheme.of(tester.element(icon)).color;
    for (var i = 0; i < 60 && color(back) != ColorTokens.mathSurface; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(color(back), ColorTokens.mathSurface);
    expect(color(hint), ColorTokens.hintAmber);
    expect(color(complete), ColorTokens.mathSurface);
    final backRect = tester.getRect(find.byType(BackButton));
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(220);
    await tester.pumpAndSettle();
    expect(color(back), ColorTokens.poemInk);
    expect(color(hint), ColorTokens.mathYellow);
    expect(color(complete), ColorTokens.poemInk);
    expect(tester.getRect(find.byType(BackButton)), backRect);
    await tester.tap(find.byTooltip('完成练习'));
    expect(completions, 1);
    expect(loads, 1);

    scroll.position.jumpTo(400);
    await tester.pumpAndSettle();
    final theme = Theme.of(tester.element(back));
    expect(color(back), theme.colorScheme.onSurface);
    expect(IconTheme.of(tester.element(back)).shadows, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('独立图片作用域使用对应图片取色，不读取父作用域图片', (tester) async {
    final bytes = (await tester.runAsync(pictureStoryContrastPng))!;
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: ProviderScope(
          overrides: [
            pictureStoryImageBytesProvider('scoped-image')
                .overrideWith((ref) async => bytes),
          ],
          child: const MaterialApp(
            home: PictureStorySceneScaffold(
              image: PictureStoryImage.local('scoped-image'),
              semanticLabel: '独立图片',
              child: Text('题目内容'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    final back = find.descendant(
      of: find.byType(BackButton),
      matching: find.byType(Icon),
    );
    for (
      var i = 0;
      i < 60 &&
          IconTheme.of(tester.element(back)).color != ColorTokens.mathSurface;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(IconTheme.of(tester.element(back)).color, ColorTokens.mathSurface);
    expect(tester.takeException(), isNull);
  });
}
