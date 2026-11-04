// Shared user journeys for host regression tests and Android integration tests.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/app.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/backup_history_service.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/providers/backup_protection_providers.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/core/widgets/animated_favorite_button.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/formula.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/features/chinese/chinese_tab_page.dart';
import 'package:poemath/features/home/home_page.dart';
import 'package:poemath/features/math/widgets/number_keypad.dart';
import 'package:poemath/features/math/math_mistake_page.dart';
import 'package:poemath/features/math/math_session_detail_page.dart';
import 'package:poemath/features/profile/backup_restore_page.dart';
import 'package:poemath/features/profile/parent_protection_page.dart';
import 'package:poemath/features/profile/settings_page.dart';
import 'package:poemath/features/shell/main_shell.dart';

typedef JourneyStorageCallback = Future<void> Function();

/// Defines deterministic journeys. The caller owns the storage
/// backend so a supported integration runner can reuse the assertions without
/// network access or production data.
void defineAppJourneyTests({
  required JourneyStorageCallback setUpStorage,
  required JourneyStorageCallback tearDownStorage,
  required Future<Directory> Function() directoryProvider,
}) {
  setUp(() async {
    ProfileScope.reset();
    await setUpStorage();
    // Exercise the real PIN setup and gate with test-only credentials. Never
    // read, overwrite, or depend on the device's existing secure storage.
    FlutterSecureStorage.setMockInitialValues({});
    final access = ParentAccessService.instance;
    access.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await access.initialize();
    access.lock();
    await _seedFixture();
  });

  tearDown(() async {
    ParentAccessService.instance.lock();
    ProfileScope.reset();
    await tearDownStorage();
  });

  testWidgets('冷启动进入首页并可完成诗词浏览收藏和测试入口', (tester) async {
    await _startApp(tester, directoryProvider: directoryProvider);

    expect(find.byType(MainShell), findsOneWidget);
    await _showHomeAction(tester, '背诗词');
    expect(find.text('背诗词'), findsOneWidget);

    await _tapTab(tester, '语文');
    final poemSection = find.descendant(
      of: find.byType(SegmentedButton<ChineseSection>),
      matching: find.text('诗词(2)'),
    );
    await _pumpUntil(tester, poemSection);
    await _tap(tester, poemSection);
    await _pumpUntil(tester, find.text('静夜思'));
    expect(find.text('诗词(2)'), findsOneWidget);
    await _tap(tester, find.text('静夜思').first);
    await _pumpUntil(tester, find.text('床前明月光'));

    expect(find.text('疑是地上霜'), findsOneWidget);
    await _tap(tester, find.byType(AnimatedFavoriteButton));
    await _pumpUntil(
      tester,
      find.byType(AnimatedFavoriteButton),
      isReady: () =>
          HiveBoxes.poemFavorites.containsKey('default_integration_poem'),
    );
    expect(
      HiveBoxes.poemFavorites.containsKey('default_integration_poem'),
      isTrue,
    );

    await _tap(tester, find.text('学习'));
    await _pumpUntil(tester, find.text('选择练习方式'));
    await _tap(tester, find.text('填空测试'));
    await _pumpUntil(tester, find.textContaining('____'));
    expect(find.text('请输入答案…'), findsOneWidget);
    expect(find.text('提交'), findsOneWidget);
  });

  testWidgets('口算错误答题会落入错题本', (tester) async {
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('math_batch_size', 1);
      await HiveBoxes.settings.put('math_practice_mode', 'findResult');
    });

    await _startApp(tester, directoryProvider: directoryProvider);
    await _tapTab(tester, '口算');
    await _pumpUntil(tester, find.text('口算练习'));
    await _tap(tester, find.text('口算练习').first);
    await _pumpUntil(tester, find.byType(NumberKeypad));

    final keypad = find.byType(NumberKeypad);
    for (var i = 0; i < 5; i++) {
      await _tap(tester, find.descendant(of: keypad, matching: find.text('9')));
    }
    await _tap(
      tester,
      find.descendant(
        of: keypad,
        matching: find.byIcon(Icons.check_rounded),
      ),
    );

    final resultsButton = find.widgetWithText(FilledButton, '查看成绩');
    await _pumpUntil(
      tester,
      resultsButton,
      isReady: () =>
          tester.widget<FilledButton>(resultsButton).onPressed != null,
    );
    await _tap(tester, resultsButton);
    await _pumpUntil(tester, find.text('看本轮错题（1）'));
    expect(HiveBoxes.mathMistakes.values, isNotEmpty);
    await _tap(tester, find.text('看本轮错题（1）'));
    await _pumpUntil(tester, find.byType(MathSessionDetailPage));
    final detail = tester.widget<MathSessionDetailPage>(
      find.byType(MathSessionDetailPage),
    );
    expect(detail.session.id, HiveBoxes.mathSessions.values.single.id);
    expect(detail.initiallyMistakesOnly, isTrue);
    expect(detail.session.problemRecords.single.isCorrect, isFalse);
    await _tap(tester, find.text('全部错题'));
    await _pumpUntil(tester, find.byType(MathMistakePage));
  });

  testWidgets('公式详情可以收藏并持久化', (tester) async {
    await _startApp(tester, directoryProvider: directoryProvider);
    await _showHomeAction(tester, '查公式');
    await _tap(tester, find.text('查公式'));
    await _pumpUntil(tester, find.text('公式知识库'));

    await _tap(tester, find.text('长方形面积'));
    await _pumpUntil(tester, find.byType(AnimatedFavoriteButton));
    await _tap(tester, find.byType(AnimatedFavoriteButton));
    await _pumpUntil(
      tester,
      find.byType(AnimatedFavoriteButton),
      isReady: () =>
          HiveBoxes.formulaFavorites.containsKey('default_integration_formula'),
    );

    expect(
      HiveBoxes.formulaFavorites.containsKey('default_integration_formula'),
      isTrue,
    );
  });

  testWidgets('完成每日目标后打卡并保存连续天数', (tester) async {
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('daily_poem_goal', 1);
      await HiveBoxes.settings.put('daily_math_goal', 1);
      await HiveBoxes.poemProgress.put(
        'default_integration_poem',
        PoemProgress(
          poemId: 'integration_poem',
          profileId: 'default',
          status: LearningStatus.learning,
          lastStudiedAt: DateTime.now(),
        ),
      );
      await HiveBoxes.mathSessions.put(
        'default_goal',
        MathSession(
          id: 'goal',
          profileId: 'default',
          grade: 1,
          problemType: 'addition',
          totalProblems: 1,
          correctCount: 1,
          durationSeconds: 1,
          startedAt: DateTime.now(),
          finishedAt: DateTime.now(),
        ),
      );
    });

    await _startApp(tester, directoryProvider: directoryProvider);
    await _tap(tester, find.text('打卡'));
    await _pumpUntil(tester, find.text('今日已打卡 ✓'));
    // The checked-in label refreshes before the achievement write chain ends.
    // The celebration is shown after that chain has actually completed.
    await _pumpUntil(tester, find.textContaining('连续打卡 1 天！继续保持！'));

    expect(find.text('今日已打卡 ✓'), findsOneWidget);
    expect(HiveBoxes.checkIns.values.single.isCheckedIn, isTrue);
    expect(HiveBoxes.userStats.values.single.currentStreak, equals(1));
  });

  testWidgets('离线备份恢复旅程保留本地学习数据', (tester) async {
    await _startApp(tester, directoryProvider: directoryProvider);
    await _tapTab(tester, '我的');
    await _pumpUntil(tester, find.byTooltip('设置'));
    await _tap(tester, find.byTooltip('设置'));
    await _pumpUntil(tester, find.byType(ParentProtectionPage));
    expect(find.byType(SettingsPage, skipOffstage: false), findsNothing);
    expect(ParentAccessService.instance.isUnlocked, isFalse);
    await tester.enterText(
      find.widgetWithText(TextField, '新的 6 位数字 PIN'),
      '246810',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '再次输入 PIN'),
      '246810',
    );
    await _tap(tester, find.widgetWithText(FilledButton, '设置家长密码'));
    await _pumpUntil(tester, find.text('保存一次性恢复码'));
    await _tap(tester, find.widgetWithText(FilledButton, '我已保存'));
    await _pumpUntil(tester, find.byType(SettingsPage));
    expect(find.byType(ParentProtectionPage), findsNothing);
    expect(ParentAccessService.instance.isUnlocked, isTrue);
    await tester.ensureVisible(find.text('家长与数据'));
    await _tap(tester, find.text('家长与数据'));
    await _pumpUntil(tester, find.text('备份与恢复'));
    await _tap(tester, find.text('备份与恢复'));
    await _pumpUntil(tester, find.text('导出备份'));
    expect(find.text('从备份恢复'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BackupRestorePage)),
    );
    final backup = container.read(backupServiceProvider);
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('theme_mode', 'dark');
      await HiveBoxes.mathSessions.put(
        'default_backup',
        MathSession(
          id: 'backup',
          profileId: 'default',
          grade: 1,
          problemType: 'addition',
          totalProblems: 1,
          correctCount: 1,
          durationSeconds: 1,
          startedAt: DateTime.now(),
          finishedAt: DateTime.now(),
        ),
      );
      final json = await backup.exportToJson();
      await HiveBoxes.mathSessions.clear();
      await HiveBoxes.settings.put('theme_mode', 'light');
      expect(HiveBoxes.mathSessions.values, isEmpty);
      expect(HiveBoxes.settings.get('theme_mode'), 'light');

      final restoredCount = await backup.restoreFromJson(json);
      expect(restoredCount, greaterThan(0));
      expect(HiveBoxes.mathSessions.values.single.id, 'backup');
      expect(
        HiveBoxes.settings.get('theme_mode'),
        equals('dark'),
      );
    });
  });
}

Future<void> _seedFixture() async {
  await HiveBoxes.poems.putAll({
    'integration_poem': Poem(
      id: 'integration_poem',
      title: '静夜思',
      author: '李白',
      dynasty: '唐',
      content: '床前明月光\n疑是地上霜\n举头望明月\n低头思故乡',
      pinyin: 'chuang qian ming yue guang',
      layer: 'core',
      grade: 1,
      semester: '上',
      isRequired: true,
      translation: '明亮的月光洒在床前。',
      appreciation: '借月抒发思乡之情。',
      difficulty: 1,
    ),
    'integration_poem_two': Poem(
      id: 'integration_poem_two',
      title: '登鹳雀楼',
      author: '王之涣',
      dynasty: '唐',
      content: '白日依山尽\n黄河入海流',
      pinyin: 'bai ri yi shan jin',
      layer: 'core',
      grade: 1,
      semester: '上',
      isRequired: true,
      difficulty: 1,
    ),
  });
  await HiveBoxes.formulas.put(
    'integration_formula',
    Formula(
      id: 'integration_formula',
      category: '几何图形',
      name: '长方形面积',
      formulaText: '面积 = 长 × 宽',
      formulaLatex: r'S = a \times b',
      grade: 3,
      example: '长 5 米、宽 2 米的长方形面积是 10 平方米。',
    ),
  );
  await HiveBoxes.settings.put('sound_enabled', false);
  await HiveBoxes.settings.put('haptic_enabled', false);
}

Future<void> _startApp(
  WidgetTester tester, {
  required Future<Directory> Function() directoryProvider,
}) async {
  addTearDown(() async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
  await tester.runAsync(
    () => tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupServiceProvider.overrideWith(
            (ref) => BackupService(
              secureStore: ref.read(secureCredentialStoreProvider),
              pictureStoryImages: PictureStoryImageService(
                directoryProvider: directoryProvider,
              ),
            ),
          ),
          backupHistoryProvider.overrideWith(
            (ref) => BackupHistoryService(
              backup: ref.read(backupServiceProvider),
              directoryProvider: directoryProvider,
              keyProvider: () async => List<int>.generate(32, (i) => i),
            ),
          ),
        ],
        child: const App(),
      ),
    ),
  );
  await _pumpUntil(tester, find.byType(MainShell));
  await _pumpUntil(tester, find.text('打卡目标 · 诗词与口算'));
}

Future<void> _showHomeAction(WidgetTester tester, String label) async {
  await tester.runAsync(
    () => tester.scrollUntilVisible(
      find.text(label),
      250,
      scrollable: find.descendant(
        of: find.byType(HomePage),
        matching: find.byType(Scrollable),
      ),
    ),
  );
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  final navigationBar = find.byType(NavigationBar);
  await _tap(
    tester,
    find.descendant(of: navigationBar, matching: find.text(label)),
  );
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget);
  await tester.runAsync(() async {
    await tester.tap(target);
    // Navigation can initialize Hive-backed services at the destination.
    await tester.pump(const Duration(milliseconds: 400));
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder target, {
  bool Function()? isReady,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    await tester.runAsync(() async {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    if (target.evaluate().isNotEmpty && (isReady?.call() ?? true)) {
      await tester.runAsync(
        () => tester.pump(const Duration(milliseconds: 400)),
      );
      return;
    }
  }
  expect(target, findsOneWidget);
  expect(isReady?.call() ?? true, isTrue, reason: '等待操作完成');
}
