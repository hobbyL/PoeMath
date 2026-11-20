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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/app_appearance.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/profile/profile_page.dart';
import 'package:poemath/features/profile/providers/profile_nickname_providers.dart';

import '../../helpers/day_key_override.dart';
import '../../helpers/hive_test_helper.dart';
import '../../helpers/theme_contrast.dart';

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
  EdgeInsets safeInsets = const EdgeInsets.only(top: 32),
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
            padding: safeInsets,
            viewPadding: safeInsets,
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
  final pageContext = tester.element(find.byType(ProfilePage));
  await tester.runAsync(
    () => precacheImage(
      AssetImage(Theme.of(pageContext).appearance.heroImage),
      pageContext,
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  for (final (size, scale) in [
    (const Size(411, 914), 1.0),
    (const Size(320, 640), 1.0),
    (const Size(320, 640), 2.0),
    (const Size(914, 411), 1.0),
    (const Size(640, 320), 2.0),
  ]) {
    testWidgets('奶糖三个学习入口始终同一行：$size/$scale', (tester) async {
      await _pump(
        tester,
        subject: AppSubject.candy,
        size: size,
        textScale: scale,
      );
      await drainHiveWritesForTesting(tester);
      final cards = [
        for (final title in ['学习报告', '学习日历', '成就勋章'])
          tester.getRect(
            find
                .ancestor(
                  of: find.text(title),
                  matching: find.byType(ColoredCard),
                )
                .first,
          ),
      ];
      for (final card in cards) {
        expect(card.top, closeTo(cards.first.top, .01));
        expect(card.bottom, closeTo(cards.first.bottom, .01));
        expect(card.width, closeTo(cards.first.width, .01));
        expect(card.width, greaterThanOrEqualTo(44));
      }
      expect(cards[1].left, greaterThan(cards[0].right));
      expect(cards[2].left, greaterThan(cards[1].right));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('奶糖三个学习入口可分别进入对应页面', (tester) async {
    const entries = [
      ('学习报告', AppRoutes.learningStats),
      ('学习日历', AppRoutes.learningCalendar),
      ('成就勋章', AppRoutes.achievements),
    ];
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const ProfilePage()),
        for (final (label, route) in entries)
          GoRoute(
            path: route,
            builder: (_, __) => Scaffold(body: Text('打开：$label')),
          ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [staticDayKeyOverride()],
        child: MaterialApp.router(
          theme: AppTheme.resolve(
            subject: AppSubject.candy,
            brightness: Brightness.light,
          ),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await drainHiveWritesForTesting(tester);
    for (final (label, _) in entries) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text('打开：$label'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  for (final subject in AppSubject.values) {
    for (final (size, scale) in [
      (const Size(914, 411), 1.0),
      (const Size(640, 320), 2.0),
    ]) {
      testWidgets('个人页横屏紧凑横排且编辑入口可用：$subject/$scale', (tester) async {
        await _pump(
          tester,
          subject: subject,
          size: size,
          textScale: scale,
          safeInsets: const EdgeInsets.only(left: 32, right: 24, top: 24),
        );
        await drainHiveWritesForTesting(tester);
        final background = tester.getRect(
          find.byKey(const ValueKey('profile-header-background')),
        );
        expect(background.height, lessThanOrEqualTo(200));
        if (subject == AppSubject.candy || subject == AppSubject.space) {
          final art = find.byKey(const ValueKey('hero-theme-illustration'));
          expect(art, findsOneWidget);
          final artBounds = tester.getRect(art);
          expect(artBounds.height, greaterThan(0));
          expect(background.contains(artBounds.center), isTrue);
          expect(artBounds.height, lessThanOrEqualTo(background.height));
        }
        final avatar = tester.getRect(find.byType(CircleAvatar));
        final name = tester.getRect(
          find.byKey(const ValueKey('profile-nickname-label')),
        );
        final settings = tester.getRect(find.byTooltip('设置'));
        expect(name.left, greaterThan(avatar.right));
        expect(name.right, lessThan(settings.left));
        // 两侧安全区为 32/24，中心比屏幕中心右移 4dp。
        expect(name.center.dx, closeTo(background.center.dx + 4, 1));
        final firstStat = tester.getRect(
          find
              .ancestor(
                of: find.text('已学诗词'),
                matching: find.byType(ColoredCard),
              )
              .first,
        );
        expect(firstStat.top, lessThan(size.height - 80));
        for (final key in ['profile-avatar-change', 'profile-nickname-edit']) {
          final target = find.byKey(ValueKey(key));
          expect(target.hitTestable(), findsOneWidget);
          expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
        }
        expect(find.byTooltip('设置').hitTestable(), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('profile-nickname-edit')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.byKey(const ValueKey('profile-nickname-input')),
          findsOneWidget,
        );
        await tester.tap(find.text('取消'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final subject in AppSubject.values) {
    testWidgets('个人页下拉使用底部空白，周报完整保留在可点击区域：$subject', (tester) async {
      const size = Size(411, 1100);
      await _pump(tester, subject: subject, size: size);
      await drainHiveWritesForTesting(tester);
      final viewport = find.byType(SingleChildScrollView);
      final report = find.ancestor(
        of: find.text('本周学习周报'),
        matching: find.byType(AppTile),
      );
      final before = tester.getRect(report);
      expect(tester.getRect(viewport).bottom, closeTo(size.height, .01));
      final gesture = await tester.startGesture(const Offset(40, 80));
      for (var step = 0; step < 4; step++) {
        await gesture.moveBy(const Offset(0, 80));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final after = tester.getRect(report);
      expect(after.top, greaterThan(before.top + 30));
      expect(after.bottom, lessThan(size.height));
      expect(report.hitTestable(at: const Alignment(0, .95)), findsOneWidget);
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(tester.getRect(report).top, closeTo(before.top, .01));
      expect(tester.takeException(), isNull);
    });
  }

  for (final subject in [AppSubject.candy, AppSubject.space]) {
    testWidgets('童趣个人页连续下拉后回弹：$subject', (tester) async {
      await _pump(tester, subject: subject);
      await drainHiveWritesForTesting(tester);
      final background = find.byKey(
        const ValueKey('profile-header-background'),
      );
      final before = tester.getRect(background);
      for (final target in [
        find.byType(CircleAvatar),
        find.byKey(const ValueKey('profile-nickname-label')),
        find.byKey(const ValueKey('profile-user-tags')),
      ]) {
        expect(tester.getCenter(target).dx, closeTo(before.center.dx, 1));
      }
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final gesture = await tester.startGesture(const Offset(40, 80));
      for (var step = 0; step < 4; step++) {
        await gesture.moveBy(const Offset(0, 40));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scroll.position.pixels, lessThan(-30));
      expect(tester.getRect(background).top, closeTo(0, .01));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(tester.getRect(background), before);
      expect(tester.takeException(), isNull);
    });
  }

  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      testWidgets('个人页状态栏透明衔接星空，滚动后图标适配正文：$subject/$brightness', (
        tester,
      ) async {
        await _pump(
          tester,
          size: const Size(411, 320),
          subject: subject,
          brightness: brightness,
        );
        void expectStatusBar(Brightness icons) {
          final style = tester.binding.renderViews.first.debugLayer!
              .find<SystemUiOverlayStyle>(const Offset(205, 16));
          expect(style?.statusBarColor, Colors.transparent);
          expect(style?.systemStatusBarContrastEnforced, isFalse);
          expect(style?.statusBarIconBrightness, icons);
          expect(
            style?.statusBarBrightness,
            icons == Brightness.light ? Brightness.dark : Brightness.light,
          );
        }

        final background = find.byKey(
          const ValueKey('profile-header-background'),
        );
        expect(tester.getTopLeft(background), Offset.zero);
        final headerIcons =
            brightness == Brightness.light &&
                (subject == AppSubject.candy || subject == AppSubject.poem)
            ? Brightness.dark
            : Brightness.light;
        expectStatusBar(headerIcons);
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(
          scroll.position.maxScrollExtent,
          greaterThanOrEqualTo(tester.getSize(background).height),
        );
        scroll.position.jumpTo(tester.getSize(background).height);
        await tester.pump();
        expectStatusBar(
          brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        );
        scroll.position.jumpTo(0);
        await tester.pump();
        expectStatusBar(headerIcons);
      });
    }
  }

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
        subject: AppSubject.math,
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
      testWidgets('个人页背景完整周期与徽章文字保持对比度：$subject/$brightness', (tester) async {
        await _pump(tester, subject: subject, brightness: brightness);
        final foreground = DefaultTextStyle.of(
          tester.element(find.byKey(const ValueKey('profile-nickname-label'))),
        ).style.color!.computeLuminance();
        if (subject == AppSubject.poem) {
          final stars = find.text('12345 颗星星');
          expect(
            contrastRatio(
              tester.widget<Text>(stars).style!.color!,
              solidBackgroundOf(tester.element(stars)),
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('profile-header-background')),
        );
        final orbitFinder = find.byKey(const ValueKey('hero-avatar-orbits'));
        expect(
          orbitFinder,
          subject == AppSubject.candy || subject == AppSubject.poem
              ? findsNothing
              : findsOneWidget,
        );
        final orbitBoundary =
            subject == AppSubject.candy || subject == AppSubject.poem
            ? null
            : tester.renderObject<RenderRepaintBoundary>(orbitFinder);
        final orbitOffset = orbitBoundary == null
            ? Offset.zero
            : orbitBoundary.localToGlobal(Offset.zero) -
                  boundary.localToGlobal(Offset.zero);
        for (var step = 0; step < 9; step++) {
          final pixels = (await tester.runAsync(() async {
            final background = await boundary.toImage();
            final orbits = await orbitBoundary?.toImage();
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder)
              ..drawImage(background, Offset.zero, Paint());
            if (orbits != null) canvas.drawImage(orbits, orbitOffset, Paint());
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
              orbits?.dispose();
              background.dispose();
            }
          }))!;
          var brightest = 0.0;
          var darkest = 1.0;
          for (var i = 0; i < pixels.lengthInBytes; i += 4) {
            final color = Color.fromARGB(
              pixels.getUint8(i + 3),
              pixels.getUint8(i),
              pixels.getUint8(i + 1),
              pixels.getUint8(i + 2),
            );
            final luminance = color.computeLuminance();
            if (luminance > brightest) brightest = luminance;
            if (luminance < darkest) darkest = luminance;
          }
          expect(
            foreground > brightest
                ? (foreground + .05) / (brightest + .05)
                : foreground < darkest
                ? (darkest + .05) / (foreground + .05)
                : 1.0,
            greaterThanOrEqualTo(4.5),
          );
          await tester.pump(const Duration(seconds: 2));
        }
      });
    }
  }

  testWidgets('个人信息竖屏居中、横屏横排，长昵称与大字号保留完整内容', (tester) async {
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
      final landscape = size.width > size.height;
      if (!landscape) {
        expect(identity.center.dx, closeTo(background.center.dx, .01));
      }
      final avatar = tester.getRect(find.byType(CircleAvatar));
      final nickname = tester.getRect(
        find.byKey(const ValueKey('profile-nickname-label')),
      );
      if (landscape) {
        expect(nickname.left, greaterThan(avatar.right));
      } else {
        expect(avatar.center.dx, closeTo(background.center.dx, .01));
        expect(nickname.center.dx, closeTo(avatar.center.dx, .01));
        expect(nickname.top, greaterThan(avatar.bottom));
      }
      expect(background.contains(nickname.topLeft), isTrue);
      expect(background.contains(nickname.bottomRight), isTrue);
      final tags = tester.getRect(
        find.byKey(const ValueKey('profile-user-tags')),
      );
      expect(tags.center.dx, closeTo(nickname.center.dx, .01));
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
        if (!landscape) expect(bounds.top, greaterThan(avatar.bottom));
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
