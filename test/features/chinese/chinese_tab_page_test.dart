import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/backup_history_service.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/widgets/swipe_navigation_region.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/providers/backup_protection_providers.dart';
import 'package:poemath/data/providers/provider_invalidation.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/features/chinese/chinese_tab_page.dart';
import 'package:poemath/features/chinese/expression/picture_story_page.dart';
import 'package:poemath/features/english/english_tab_page.dart';
import 'package:poemath/features/home/home_page.dart';
import 'package:poemath/features/math/math_home_page.dart';
import 'package:poemath/features/math/math_tab_page.dart';
import 'package:poemath/features/profile/profile_page.dart';
import 'package:poemath/features/poem/poem_favorites_page.dart';
import 'package:poemath/features/poem/poem_learning_path_page.dart';
import 'package:poemath/features/poem/poem_tab_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/textbook_detail_page.dart';
import 'package:poemath/features/textbook/textbook_management_page.dart';

import '../../helpers/day_key_override.dart';
import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';
import '../../helpers/textbook_fixture.dart';

class _MissingFiles extends TextbookFileService {
  @override
  Future<String?> installedPath(Textbook book) async => null;
}

class _NoSnapshots extends BackupHistoryService {
  _NoSnapshots() : super(backup: BackupService());

  @override
  Future<void> maybeCreateDaily() async {}
}

Future<({GoRouter router, ProviderContainer container})> _pumpAt(
  WidgetTester tester, {
  String location = AppRoutes.chineseTab,
  double textScale = 1,
  ThemeData? theme,
}) async {
  final router = createAppRouter(initialLocation: location);
  final container = ProviderContainer(
    overrides: [
      staticDayKeyOverride(),
      backupHistoryProvider.overrideWithValue(_NoSnapshots()),
      textbookCatalogProvider.overrideWith((ref) async => []),
      textbookFileServiceProvider.overrideWithValue(_MissingFiles()),
      textbookCourseProvider.overrideWith((ref, id) async => null),
      textbookCourseDocumentProvider.overrideWith((ref, id) async => null),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: theme,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (router: router, container: container);
}

Finder _bookCard(Textbook book) =>
    find.byKey(ValueKey('textbook-${book.pdfSha256}'));

Finder _textbookSegment() => find.ancestor(
  of: find.textContaining(RegExp(r'^课本\(\d+\)$')),
  matching: find.byType(FittedBox),
);

void _expectTextbookSection(WidgetTester tester) {
  final switcher = tester.widget<SegmentedButton<ChineseSection>>(
    find.byType(SegmentedButton<ChineseSection>),
  );
  expect(switcher.selected, {ChineseSection.textbook});
  expect(find.text('课本(1)'), findsOneWidget);
  expect(find.text('三年级上册'), findsNothing);
  expect(find.text('三年级下册'), findsNothing);
}

Finder _poemSegment() => find.ancestor(
  of: find.textContaining(RegExp(r'^诗词\(\d+\)$')),
  matching: find.byType(FittedBox),
);

void _expectPoemSection(WidgetTester tester) {
  final switcher = tester.widget<SegmentedButton<ChineseSection>>(
    find.byType(SegmentedButton<ChineseSection>),
  );
  expect(switcher.selected, {ChineseSection.poem});
  expect(find.byTooltip('搜索筛选'), findsOneWidget);
}

Future<void> _pumpHome(WidgetTester tester) async {
  // 首页待打卡卡片会持续重绘；导航完成以实际页面和底栏选中项为准。
  // 只推进有限的入场动画，不等待整页动画停止，也不关闭真实动效。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(HomePage), findsOneWidget);
  expect(
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
    0,
  );
  final context = tester.element(find.byType(HomePage));
  expect(GoRouterState.of(context).uri.path, AppRoutes.home);
  expect(ModalRoute.of(context)!.isCurrent, isTrue);
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // 离开管理页会恢复授权倒计时，在框架检查遗留定时器前显式锁定。
  lockParentForTesting();
  // 多次栏目切换会在 fake zone 排队写 Hive；在测试体内关闭并推动该队列，
  // 避免真实 zone 的 tearDown 等待已经停止的 fake 时钟。
  var closed = false;
  final closing = HiveBoxes.close().then((_) => closed = true);
  for (var i = 0; i < 100 && !closed; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(closed, isTrue, reason: '测试结束前须完成本机偏好写入');
  await closing;
}

void main() {
  late Textbook current;
  late Textbook other;

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    await SettingsRepository().setLearningBackground(3, '上');
    current = textbookFixture(title: '当前课本');
    other = Textbook.fromJson({
      ...textbookFixture(id: 'b'.padLeft(64, 'b'), title: '其他册次').toJson(),
      'semester': '下',
    });
    final repository = TextbookRepository();
    await repository.addIfAbsent(current);
    await repository.addIfAbsent(other);
    await repository.savePage(ProfileScope.currentId, current, 2);
  });

  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForWidgetTesting();
  });

  testWidgets('语文默认课本，只显示本学期本地书及阅读位置，详情全屏返回', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await _pumpAt(tester);
    _expectTextbookSection(tester);
    expect(_bookCard(current), findsOneWidget);
    expect(_bookCard(other), findsNothing);
    expect(find.text('第 2 / 3 页'), findsNothing);
    expect(find.bySemanticsLabel('当前课本，三年级上册，页码读取失败'), findsOneWidget);
    expect(
      TextbookRepository()
          .reading(ProfileScope.currentId, current.pdfSha256)
          .page,
      2,
    );
    semantics.dispose();
    expect(find.text('请家长补齐课本文件'), findsOneWidget);
    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navigation.selectedIndex, 1);
    expect(
      tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(NavigationBar),
              matching: find.byType(Text),
            ),
          )
          .map((item) => item.data)
          .toList(),
      ['首页', '语文', '数学', '英语', '我的'],
    );
    await tester.tap(_bookCard(current));
    await tester.pumpAndSettle();
    expect(find.byType(TextbookDetailPage), findsOneWidget);
    expect(
      tester.widget<TextbookDetailPage>(find.byType(TextbookDetailPage)).manage,
      isFalse,
    );
    expect(find.byTooltip('内容审核'), findsNothing);
    expect(find.byIcon(Icons.fact_check_outlined), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    app.router.pop();
    await tester.pumpAndSettle();
    _expectTextbookSection(tester);
    expect(
      app.router.routeInformationProvider.value.uri.path,
      AppRoutes.chineseTab,
    );
    await _finish(tester);
  });

  testWidgets('栏目首次访问才创建，切换后保留已访问页面和搜索输入', (tester) async {
    await _pumpAt(tester);
    expect(find.byType(PoemTabPage, skipOffstage: false), findsNothing);
    expect(find.byType(PictureStoryPage, skipOffstage: false), findsNothing);

    await tester.tap(_poemSegment());
    await tester.pumpAndSettle();
    expect(find.byType(PoemTabPage), findsOneWidget);
    expect(find.byType(PictureStoryPage, skipOffstage: false), findsNothing);
    final poemState = tester.state(find.byType(PoemTabPage));
    await tester.tap(find.byTooltip('搜索筛选'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '保留搜索');
    await tester.tap(_textbookSegment());
    await tester.pumpAndSettle();
    await tester.tap(_poemSegment());
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(PoemTabPage)), same(poemState));
    expect(find.text('保留搜索'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('旧诗词入口直达诗词，搜索草稿与工具导航在栏目切换后保留', (tester) async {
    final app = await _pumpAt(tester, location: AppRoutes.poemTab);
    _expectPoemSection(tester);
    expect(find.byTooltip('学习路径'), findsOneWidget);
    expect(find.byTooltip('我的收藏'), findsOneWidget);
    await tester.tap(find.byTooltip('搜索筛选'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '春晓');
    await tester.tap(_textbookSegment());
    await tester.pumpAndSettle();
    _expectTextbookSection(tester);
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.tap(_poemSegment());
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '春晓',
    );
    await tester.tap(find.byTooltip('我的收藏'));
    await tester.pumpAndSettle();
    expect(find.byType(PoemFavoritesPage), findsOneWidget);
    app.router.pop();
    await tester.pumpAndSettle();
    _expectPoemSection(tester);
    expect(SettingsRepository().chineseSection, 'poem');
    await _finish(tester);
  });

  testWidgets('底部 Tab 往返记住栏目，首页背诗词仍直达诗词', (tester) async {
    final app = await _pumpAt(tester);
    await tester.tap(_poemSegment());
    await tester.pumpAndSettle();
    await tester.tap(find.text('首页'));
    await _pumpHome(tester);
    await tester.tap(find.text('语文'));
    await tester.pumpAndSettle();
    _expectPoemSection(tester);
    await tester.tap(_textbookSegment());
    await tester.pumpAndSettle();
    app.router.go(AppRoutes.home);
    await _pumpHome(tester);
    await tester.scrollUntilVisible(
      find.text('背诗词'),
      250,
      scrollable: find.descendant(
        of: find.byType(HomePage),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('背诗词'));
    await tester.pumpAndSettle();
    _expectPoemSection(tester);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    await _finish(tester);
  });

  testWidgets('左右滑动沿栏目顺序切换，到达边界后衔接底部 Tab', (tester) async {
    await _pumpAt(tester);
    _expectTextbookSection(tester);

    Future<void> swipe(Finder page, double dx) async {
      await tester.drag(page, Offset(dx, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    // 首页左划进入语文课本，语文栏目向左依次前进。
    await swipe(find.byType(ChineseTabPage), 120);
    await _pumpHome(tester);
    await swipe(find.byType(HomePage), -120);
    _expectTextbookSection(tester);

    // 语文栏目按顶部标签从左到右移动，中间栏目不会误切到底部 Tab。
    await swipe(find.byType(ChineseTabPage), -120);
    expect(
      tester
          .widget<SegmentedButton<ChineseSection>>(
            find.byType(SegmentedButton<ChineseSection>),
          )
          .selected,
      {ChineseSection.expression},
    );
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );

    await swipe(find.byType(ChineseTabPage), -120);
    _expectPoemSection(tester);

    // 语文末尾左划进入数学练习，继续左划经过数学课本和英语到我的。
    await swipe(find.byType(ChineseTabPage), -120);
    expect(find.byType(MathHomePage), findsOneWidget);
    expect(find.byType(MathTabPage), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    await swipe(find.byType(MathHomePage), -120);
    expect(
      tester
          .widget<SegmentedButton<MathSection>>(
            find.byType(SegmentedButton<MathSection>),
          )
          .selected,
      {MathSection.textbook},
    );

    // 数学末尾进入英语，再从我的页反向回到英语和数学课本。
    await swipe(find.byType(MathHomePage), -120);
    expect(find.byType(EnglishTabPage), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    await swipe(find.byType(EnglishTabPage), -120);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      4,
    );
    // 反向手指右划依次返回英语、数学课本、数学练习和语文诗词。
    await swipe(find.byType(ProfilePage), 120);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    await swipe(find.byType(EnglishTabPage), 120);
    expect(
      tester
          .widget<SegmentedButton<MathSection>>(
            find.byType(SegmentedButton<MathSection>),
          )
          .selected,
      {MathSection.textbook},
    );
    await swipe(find.byType(MathHomePage), 120);
    expect(find.byType(MathTabPage), findsOneWidget);
    await swipe(find.byType(MathHomePage), 120);
    _expectPoemSection(tester);

    // 语文反向依次穿过诗词、表达、课本，右划返回首页。
    for (final section in [
      ChineseSection.expression,
      ChineseSection.textbook,
    ]) {
      await swipe(find.byType(ChineseTabPage), 120);
      final switcher = tester.widget<SegmentedButton<ChineseSection>>(
        find.byType(SegmentedButton<ChineseSection>),
      );
      expect(switcher.selected, {section});
    }
    await swipe(find.byType(ChineseTabPage), 120);
    await _pumpHome(tester);
    await _finish(tester);
  });

  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      testWidgets('内部滑动只移动正文，顶部导航和底栏固定：$subject/$brightness', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(411, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = await _pumpAt(
          tester,
          textScale: 2,
          theme: AppTheme.resolve(subject: subject, brightness: brightness),
        );

        Future<void> swipeInside(
          Finder switcher,
          double dx, {
          bool fromToolbar = false,
        }) async {
          final toolbar = find.byType(AppBar);
          final navigation = find.byType(NavigationBar);
          final toolbarRect = tester.getRect(toolbar);
          final switcherRect = tester.getRect(switcher);
          final navigationRect = tester.getRect(navigation);
          final selectedTab = tester
              .widget<NavigationBar>(navigation)
              .selectedIndex;
          final body = find.byType(SwipeNavigationBody);
          final bodyRect = tester.getRect(body);
          final scrollable = find
              .descendant(of: body, matching: find.byType(Scrollable))
              .last;
          final contentRect = tester.getRect(scrollable);
          final sourceButton = tester.widget(switcher);
          final direction = dx < 0 ? 1 : -1;
          final (sourceIndex, segmentCount) = switch (sourceButton) {
            SegmentedButton<ChineseSection>(:final selected) => (
              ChineseSection.navigationOrder.indexOf(selected.single),
              ChineseSection.navigationOrder.length,
            ),
            SegmentedButton<MathSection>(:final selected) => (
              selected.single.index,
              MathSection.values.length,
            ),
            _ => throw StateError('未知栏目分段按钮'),
          };
          final buttonGroup = find.ancestor(
            of: switcher,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is SwipeNavigationSegmentedButton<ChineseSection> ||
                  widget is SwipeNavigationSegmentedButton<MathSection>,
            ),
          );
          void expectLinkedSelection(double progress) {
            final overlay = find.descendant(
              of: buttonGroup,
              matching: find.byKey(
                const ValueKey('swipe-navigation-selection'),
              ),
            );
            expect(overlay, findsOneWidget);
            final clip = tester
                .widget<ClipRect>(overlay)
                .clipper!
                .getClip(tester.getSize(overlay));
            final segmentWidth = switcherRect.width / segmentCount;
            expect(clip.width, closeTo(segmentWidth, .01));
            expect(
              clip.left,
              closeTo((sourceIndex + direction * progress) * segmentWidth, .01),
            );
          }

          final gesture = await tester.startGesture(
            tester.getCenter(fromToolbar ? switcher : scrollable),
          );
          await gesture.moveBy(Offset(dx, 0));
          await tester.pump();

          void expectChromeFixed() {
            expect(tester.getRect(toolbar), toolbarRect);
            expect(tester.getRect(switcher), switcherRect);
            expect(tester.getRect(navigation), navigationRect);
            expect(
              tester.widget<NavigationBar>(navigation).selectedIndex,
              selectedTab,
            );
          }

          expectChromeFixed();
          final dragProgress = dx.abs() / bodyRect.width;
          expectLinkedSelection(dragProgress);
          expect(
            tester.getRect(scrollable).left,
            closeTo(contentRect.left + dx, .01),
          );
          final preview = find.byKey(
            ValueKey(
              dx < 0
                  ? 'swipe-navigation-next-preview'
                  : 'swipe-navigation-previous-preview',
            ),
          );
          expect(preview, findsOneWidget);
          final previewPage = find
              .descendant(of: preview, matching: find.byType(Scaffold))
              .first;
          expect(
            tester.getRect(previewPage).top,
            bodyRect.top,
            reason: '相邻正文须在固定导航下直接接入，不能带入第二个导航栏',
          );
          expect(
            find.descendant(of: preview, matching: find.byType(AppBar)),
            findsNothing,
          );

          await gesture.up();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 110));
          expectChromeFixed();
          expectLinkedSelection(
            dragProgress +
                (1 - dragProgress) * Curves.easeOutCubic.transform(.5),
          );
          await tester.pump(const Duration(milliseconds: 120));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(
            tester.widget<NavigationBar>(navigation).selectedIndex,
            selectedTab,
          );
          expect(tester.getRect(navigation), navigationRect);
          expect(
            tester.getRect(switcher),
            switcherRect,
            reason: '切换完成后顶部栏目的位置和宽度也应保持一致',
          );
        }

        final chineseSwitcher = find
            .byType(SegmentedButton<ChineseSection>)
            .first;
        final mathSwitcher = find.byType(SegmentedButton<MathSection>).first;
        for (final size in [const Size(320, 720), const Size(844, 390)]) {
          tester.view.physicalSize = size;
          app.router.go(AppRoutes.chineseSectionOf('textbook'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump();
          await swipeInside(chineseSwitcher, -80);
          expect(
            tester
                .widget<SegmentedButton<ChineseSection>>(chineseSwitcher)
                .selected,
            {ChineseSection.expression},
          );
          await swipeInside(chineseSwitcher, -80, fromToolbar: true);
          _expectPoemSection(tester);
          await swipeInside(chineseSwitcher, 80);
          await swipeInside(chineseSwitcher, 80);
          _expectTextbookSection(tester);

          app.router.go(AppRoutes.mathSectionOf('practice'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump();
          await swipeInside(mathSwitcher, -80);
          expect(
            tester.widget<SegmentedButton<MathSection>>(mathSwitcher).selected,
            {MathSection.textbook},
          );
          await swipeInside(mathSwitcher, 80, fromToolbar: true);
          expect(
            tester.widget<SegmentedButton<MathSection>>(mathSwitcher).selected,
            {MathSection.practice},
          );
        }
        await _finish(tester);
      });
    }
  }

  testWidgets('背景改变后课本立即换册，设置管理仍展示所有教材', (tester) async {
    final app = await _pumpAt(tester);
    await tester.runAsync(
      () => SettingsRepository().setLearningBackground(3, '下'),
    );
    invalidateLearningBackground(app.container.invalidate);
    await tester.pumpAndSettle();
    _expectTextbookSection(tester);
    expect(_bookCard(other), findsOneWidget);
    expect(_bookCard(current), findsNothing);
    final learningCoverSize = tester.getSize(_bookCard(other));
    await tester.runAsync(unlockParentForTesting);
    addTearDown(lockParentForTesting);
    app.router.push<void>(AppRoutes.textbookManagement);
    await tester.pumpAndSettle();
    expect(find.byType(TextbookManagementPage), findsOneWidget);
    expect(
      find.byKey(ValueKey('textbook-card-${current.pdfSha256}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('textbook-card-${other.pdfSha256}')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(ValueKey('textbook-card-${other.pdfSha256}'))),
      learningCoverSize,
    );
    expect(find.byTooltip('导入'), findsOneWidget);
    expect(find.byTooltip('下载'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('档案切换恢复各自栏目，空册次不展示其他教材', (tester) async {
    final app = await _pumpAt(tester);
    await tester.tap(_poemSegment());
    await tester.pumpAndSettle();
    ProfileScope.switchTo('second');
    await tester.pumpAndSettle();
    _expectTextbookSection(tester);
    ProfileScope.reset();
    await tester.pumpAndSettle();
    _expectPoemSection(tester);
    await tester.runAsync(
      () => SettingsRepository().setLearningBackground(6, '下'),
    );
    invalidateLearningBackground(app.container.invalidate);
    await tester.tap(_textbookSegment());
    await tester.pumpAndSettle();
    expect(find.text('暂无六年级下册课本'), findsOneWidget);
    expect(find.text('课本(0)'), findsOneWidget);
    expect(_bookCard(current), findsNothing);
    expect(_bookCard(other), findsNothing);
    await _finish(tester);
  });

  testWidgets('课本滚动位置在栏目切换和底部 Tab 往返后保留', (tester) async {
    await tester.runAsync(() async {
      for (var i = 1; i <= 20; i++) {
        await TextbookRepository().addIfAbsent(
          textbookFixture(
            id: i.toRadixString(16).padLeft(64, '0'),
            title: '课本 $i',
          ),
        );
      }
    });
    await _pumpAt(tester);
    expect(find.text('课本(21)'), findsOneWidget);
    final scrollView = find.byKey(
      const PageStorageKey('textbook-list-chinese-三年级上册'),
    );
    await tester.drag(scrollView, const Offset(0, -600));
    await tester.pumpAndSettle();
    double offset() => tester
        .state<ScrollableState>(
          find.descendant(of: scrollView, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;
    final before = offset();
    expect(before, greaterThan(200));
    await tester.tap(_poemSegment());
    await tester.pumpAndSettle();
    await tester.tap(_textbookSegment());
    await tester.pumpAndSettle();
    expect(offset(), closeTo(before, 1));
    await tester.tap(find.text('首页'));
    await _pumpHome(tester);
    await tester.tap(find.text('语文'));
    await tester.pumpAndSettle();
    expect(offset(), closeTo(before, 1));
    await _finish(tester);
  });

  testWidgets('诗词学习路径可返回，诗词列表位置在两个栏目与底部 Tab 往返后保留', (tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 1031; i++) {
        await HiveBoxes.poems.put(
          'poem_$i',
          Poem(
            id: 'poem_$i',
            title: '诗词 $i',
            author: '作者',
            dynasty: '唐',
            content: '春眠不觉晓，处处闻啼鸟。',
            pinyin: '',
            layer: 'core',
            grade: 3,
            semester: '上',
          ),
        );
      }
    });
    final app = await _pumpAt(tester, location: AppRoutes.poemTab);
    expect(find.text('诗词(1031)'), findsOneWidget);
    await tester.tap(find.byTooltip('学习路径'));
    await tester.pumpAndSettle();
    expect(find.byType(PoemLearningPathPage), findsOneWidget);
    app.router.pop();
    await tester.pumpAndSettle();
    final list = find.byKey(const PageStorageKey('poem-list'));
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    double offset() => tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;
    final before = offset();
    expect(before, greaterThan(200));
    await tester.tap(_textbookSegment());
    await tester.pumpAndSettle();
    await tester.tap(_poemSegment());
    await tester.pumpAndSettle();
    expect(offset(), closeTo(before, 1));
    await tester.tap(find.text('首页'));
    await _pumpHome(tester);
    await tester.tap(find.text('语文'));
    await tester.pumpAndSettle();
    expect(offset(), closeTo(before, 1));
    await tester.pump(const Duration(seconds: 3));
    app.container.read(poemSearchQueryProvider.notifier).state = '诗词 999';
    await tester.pumpAndSettle();
    expect(find.text('诗词(1)'), findsOneWidget);
    app.container.read(poemSearchQueryProvider.notifier).state = '无匹配结果';
    await tester.pumpAndSettle();
    expect(find.text('诗词(0)'), findsOneWidget);
    await _finish(tester);
  });

  for (final width in [320.0, 800.0, 1200.0]) {
    testWidgets('宽度 $width 大字体下栏目与课本不溢出', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpAt(tester, textScale: 2);
      expect(_bookCard(current), findsOneWidget);
      final coverSize = tester.getSize(_bookCard(current));
      expect(coverSize.width / coverSize.height, closeTo(3 / 4, 0.001));
      expect(tester.takeException(), isNull);
      await tester.tap(_poemSegment());
      await tester.pumpAndSettle();
      _expectPoemSection(tester);
      final switcher = tester.getRect(
        find.byType(SegmentedButton<ChineseSection>),
      );
      final search = tester.getRect(find.byTooltip('搜索筛选'));
      final favorites = tester.getRect(find.byTooltip('我的收藏'));
      final path = tester.getRect(find.byTooltip('学习路径'));
      expect(switcher.center.dy, closeTo(search.center.dy, 1));
      expect(path.right, lessThanOrEqualTo(switcher.left));
      expect(switcher.right, lessThanOrEqualTo(favorites.left));
      expect(tester.takeException(), isNull);
      await _finish(tester);
    });
  }
}
