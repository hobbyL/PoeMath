// test/features/profile/profile_page_chrome_test.dart
//
// 「我的」页顶部结构：无 AppBar、无「我的」大标题，设置入口是悬浮在
// 右上角、不随内容滚动的按钮。
//
// 背景：该页原先用 `AppBar(title: Text('我的')) + actions[设置]`。顶部这条
// 导航栏只放一个标题、不承载任何交互，却占掉一整条高度；作为 4 个 Tab
// 之一也不需要返回按钮，因此整条去掉，设置改悬浮。
//
// ── 写法约束（沿用 hive_key_recovery_notice_test 里踩出来的两条）──────
//
// ① 必须 override `dayKeyProvider` 为静态值：`ProfilePage` 经
//    `userStatsProvider` / `streakProvider` 依赖它，而 `DayKeyNotifier.build`
//    会起一个 30 秒 `Timer.periodic`，让 tearDown 的 `HiveBoxes.close()` 挂到
//    超时（用例体已跑完却报挂起）。
// ② 顶部持续流动，使用有界 pump 推进入场动画；仅跳转到静态页面后
//    才使用 pumpAndSettle，避免等待永不停止的顶部动效。

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/profile/profile_page.dart';
import 'package:poemath/features/profile/providers/profile_nickname_providers.dart';

import '../../helpers/day_key_override.dart';
import '../../helpers/hive_test_helper.dart';

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(411, 914),
  double textScale = 1,
  bool reduceMotion = false,
  bool accessibleNavigation = false,
  Brightness brightness = Brightness.light,
  AppSubject subject = AppSubject.poem,
  String nickname = '小小学习家',
  UserStats? stats,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        staticDayKeyOverride(),
        profileNicknameProvider.overrideWithValue(nickname),
        userStatsProvider.overrideWithValue(
          stats ?? UserStats(profileId: 'default', level: 7, totalStars: 12345),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.resolve(subject: subject, brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 32),
            viewPadding: const EdgeInsets.only(top: 32),
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
            accessibleNavigation: accessibleNavigation,
          ),
          child: PageAnimationScope(enabled: false, child: child!),
        ),
        home: const ProfilePage(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('顶部无 AppBar，「我的」不再作为标题显示', (tester) async {
    await _pump(tester);

    expect(find.byType(AppBar), findsNothing);
    // 本页正文里没有「我的」字样，因此整棵树上都不该出现。
    expect(find.text('我的'), findsNothing);
  });

  testWidgets('统计更新后等级配色与星芒一起更新，无需重进页面', (tester) async {
    await _pump(
      tester,
      reduceMotion: true,
      stats: UserStats(profileId: 'default', level: 0, totalStars: 49),
    );
    final pageState = tester.state(find.byType(ProfilePage));
    final levelFinder = find.byKey(const ValueKey('profile-level-tag'));
    final starsFinder = find.byKey(const ValueKey('profile-stars-tag'));
    final initialLevel = tester.widget<HeroStatusTag>(levelFinder).style;
    final initialStars = tester.widget<HeroStatusTag>(starsFinder).style;
    expect(find.text('童生'), findsOneWidget);
    expect(find.text('49 颗星星'), findsOneWidget);

    await _pump(
      tester,
      reduceMotion: true,
      stats: UserStats(profileId: 'default', level: 1, totalStars: 50),
    );
    expect(tester.state(find.byType(ProfilePage)), same(pageState));
    expect(find.text('秀才'), findsOneWidget);
    expect(find.text('50 颗星星'), findsOneWidget);
    expect(
      tester.widget<HeroStatusTag>(levelFinder).style.accent,
      isNot(initialLevel.accent),
    );
    expect(
      tester.widget<HeroStatusTag>(starsFinder).style.sparkleCount,
      greaterThan(initialStars.sparkleCount),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置按钮悬浮右上角且不随内容滚动', (tester) async {
    await _pump(tester, size: const Size(411, 400));

    final settingsButton = find.widgetWithIcon(
      IconButton,
      Icons.settings_rounded,
    );
    expect(settingsButton, findsOneWidget);
    final theme = Theme.of(tester.element(settingsButton));
    expect(
      tester
          .widget<IconButton>(settingsButton)
          .style!
          .backgroundColor!
          .resolve({}),
      Colors.transparent,
    );
    expect(
      tester
          .widget<IconButton>(settingsButton)
          .style!
          .foregroundColor!
          .resolve({}),
      AnimatedHeroColors(theme, style: AnimatedHeroStyle.starlight).foreground,
    );

    final before = tester.getTopRight(settingsButton);

    // 滚动到底：按钮在同一屏幕位置不动（不是 ListView 的一项）。
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -600),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(settingsButton, findsOneWidget);
    expect(tester.getTopRight(settingsButton), before);
    expect(
      tester
          .widget<IconButton>(settingsButton)
          .style!
          .foregroundColor!
          .resolve({}),
      theme.colorScheme.onSurface,
    );
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      greaterThan(0),
    );
  });

  for (final reduceMotion in [false, true]) {
    testWidgets('个人页星光与下拉放大遵循系统减少动态效果：$reduceMotion', (tester) async {
      await _pump(
        tester,
        reduceMotion: reduceMotion,
        accessibleNavigation: true,
      );
      final background = find.byKey(
        const ValueKey('profile-header-background'),
      );
      Future<Uint8List> pixels(Finder target) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(target);
        return (await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
          } finally {
            image.dispose();
          }
        }))!;
      }

      final orbits = find.byKey(const ValueKey('hero-avatar-orbits'));
      final levelTag = find.byKey(const ValueKey('profile-level-tag'));
      final starsTag = find.byKey(const ValueKey('profile-stars-tag'));
      final first = await pixels(background);
      final firstOrbits = await pixels(orbits);
      final firstLevelTag = await pixels(levelTag);
      final firstStarsTag = await pixels(starsTag);
      final tagBounds = tester.getRect(starsTag);
      final avatarBounds = tester.getRect(find.byType(CircleAvatar));
      await tester.pump(const Duration(milliseconds: 1500));
      final second = await pixels(background);
      expect(listEquals(first, second), reduceMotion);
      if (!reduceMotion) {
        var visiblyChanged = 0;
        for (var offset = 0; offset < first.length; offset += 4) {
          if ((first[offset] - second[offset]).abs() >= 10 ||
              (first[offset + 1] - second[offset + 1]).abs() >= 10 ||
              (first[offset + 2] - second[offset + 2]).abs() >= 10) {
            visiblyChanged++;
          }
        }
        expect(
          visiblyChanged / (first.length / 4),
          greaterThan(.15),
          reason: '1.5 秒内至少 15% 背景像素有可辨识变化，不能仅凭少量像素变化认定动效可见',
        );
      }
      expect(listEquals(firstOrbits, await pixels(orbits)), reduceMotion);
      expect(listEquals(firstLevelTag, await pixels(levelTag)), reduceMotion);
      expect(listEquals(firstStarsTag, await pixels(starsTag)), reduceMotion);
      expect(tester.getRect(starsTag), tagBounds);
      expect(tester.getRect(find.byType(CircleAvatar)), avatarBounds);
      final before = tester.getRect(background);
      final gesture = await tester.startGesture(before.center);
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 100));
      await tester.pump();
      final pulled = tester.getRect(background);
      expect(pulled.top, closeTo(0, .01));
      expect(
        tester.getCenter(orbits),
        tester.getCenter(find.byType(CircleAvatar)),
      );
      if (reduceMotion) {
        expect(pulled, before);
      } else {
        expect(pulled.height, greaterThan(before.height));
        expect(
          tester
              .getCenter(find.byKey(const ValueKey('profile-header-content')))
              .dy,
          closeTo((pulled.top + 32 + pulled.bottom) / 2, .01),
        );
      }
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });
  }

  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      testWidgets('个人页星光完整周期保持文字对比度：$subject/$brightness', (tester) async {
        await _pump(tester, subject: subject, brightness: brightness);
        final foreground = tester
            .widget<Text>(find.text('12345 颗星星'))
            .style!
            .color!
            .computeLuminance();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('profile-header-background')),
        );
        final orbitBoundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('hero-avatar-orbits')),
        );
        final orbitOffset =
            orbitBoundary.localToGlobal(Offset.zero) -
            boundary.localToGlobal(Offset.zero);
        for (var step = 0; step < 9; step++) {
          final pixels = (await tester.runAsync(() async {
            final background = await boundary.toImage();
            final orbits = await orbitBoundary.toImage();
            final recorder = ui.PictureRecorder();
            Canvas(recorder)
              ..drawImage(background, Offset.zero, Paint())
              ..drawImage(orbits, orbitOffset, Paint());
            final picture = recorder.endRecording();
            final image = await picture.toImage(
              background.width,
              background.height,
            );
            try {
              return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
            } finally {
              image.dispose();
              picture.dispose();
              orbits.dispose();
              background.dispose();
            }
          }))!;
          var brightest = 0.0;
          for (var i = 0; i < pixels.lengthInBytes; i += 4) {
            final color = Color.fromARGB(
              pixels.getUint8(i + 3),
              pixels.getUint8(i),
              pixels.getUint8(i + 1),
              pixels.getUint8(i + 2),
            );
            final luminance = color.computeLuminance();
            if (luminance > brightest) brightest = luminance;
          }
          expect(
            (foreground + .05) / (brightest + .05),
            greaterThanOrEqualTo(4.5),
          );
          await tester.pump(const Duration(seconds: 2));
        }
      });
    }
  }

  testWidgets('头像下方等级和星星标签居中并排，窄屏大字号自动换行', (tester) async {
    for (final (size, scale, brightness) in [
      (const Size(411, 914), 1.0, Brightness.light),
      (const Size(320, 640), 2.0, Brightness.light),
      (const Size(914, 411), 2.0, Brightness.dark),
    ]) {
      await _pump(
        tester,
        size: size,
        textScale: scale,
        brightness: brightness,
        nickname: '喜欢看星星也喜欢读诗的小小学习家呀',
      );
      final background = tester.getRect(
        find.byKey(const ValueKey('profile-header-background')),
      );
      expect(background.left, 0);
      expect(background.right, size.width);
      final identity = tester.getRect(
        find.byKey(const ValueKey('profile-user-info')),
      );
      expect(identity.center.dx, closeTo(background.center.dx, .01));
      final avatar = tester.getRect(find.byType(CircleAvatar));
      expect(avatar.center.dx, closeTo(background.center.dx, .01));
      final nickname = tester.getRect(
        find.byKey(const ValueKey('profile-nickname-label')),
      );
      expect(nickname.center.dx, closeTo(avatar.center.dx, .01));
      expect(nickname.top, greaterThan(avatar.bottom));
      expect(background.contains(nickname.topLeft), isTrue);
      expect(background.contains(nickname.bottomRight), isTrue);
      final tags = tester.getRect(
        find.byKey(const ValueKey('profile-user-tags')),
      );
      expect(tags.center.dx, closeTo(avatar.center.dx, .01));
      expect(tags.top, greaterThan(nickname.bottom));
      final level = tester.getRect(
        find.byKey(const ValueKey('profile-level-tag')),
      );
      final stars = tester.getRect(
        find.byKey(const ValueKey('profile-stars-tag')),
      );
      if (size.width == 320) {
        expect(stars.top, greaterThan(level.bottom));
        expect(level.center.dx, closeTo(avatar.center.dx, .01));
        expect(stars.center.dx, closeTo(avatar.center.dx, .01));
      } else {
        expect(level.center.dy, closeTo(stars.center.dy, .01));
        expect(stars.left, greaterThan(level.right));
      }
      for (final label in ['诗仙', '12345 颗星星']) {
        final bounds = tester.getRect(find.text(label));
        expect(bounds.top, greaterThan(avatar.bottom));
        expect(background.contains(bounds.topLeft), isTrue);
        expect(background.contains(bounds.bottomRight), isTrue);
        expect(tags.contains(bounds.topLeft), isTrue);
        expect(tags.contains(bounds.bottomRight), isTrue);
      }
      expect(find.byTooltip('设置').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('设置按钮点击导航到设置页', (tester) async {
    // 真实挂一个只含设置路由的 router，断言 push 的目标路径，
    // 而不是断言 `AppRoutes.settings` 常量等于自己。
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const ProfilePage()),
        GoRoute(
          path: AppRoutes.settings,
          builder: (_, __) => const Scaffold(body: Text('设置页占位')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [staticDayKeyOverride()],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.widgetWithIcon(IconButton, Icons.settings_rounded));
    await tester.pumpAndSettle();

    expect(find.text('设置页占位'), findsOneWidget);
  });
}
