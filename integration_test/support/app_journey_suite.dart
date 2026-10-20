// Shared user journeys for Android integration tests.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import 'package:poemath/app.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/backup_history_service.dart';
import 'package:poemath/data/providers/backup_protection_providers.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/core/widgets/animated_favorite_button.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/formula.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/features/math/widgets/number_keypad.dart';
import 'package:poemath/features/math/math_mistake_page.dart';
import 'package:poemath/features/shell/main_shell.dart';

typedef JourneyStorageCallback = Future<void> Function();

/// Defines deterministic on-device journeys. The caller owns the storage
/// backend so a supported integration runner can reuse the assertions without
/// network access or production data.
void defineAppJourneyTests({
  required JourneyStorageCallback setUpStorage,
  required JourneyStorageCallback tearDownStorage,
}) {
  setUp(() async {
    await setUpStorage();
    await _seedFixture();
  });

  tearDown(tearDownStorage);

  testWidgets('冷启动进入首页并可完成诗词浏览收藏和测试入口', (tester) async {
    await _startApp(tester);

    expect(find.byType(MainShell), findsOneWidget);
    expect(find.text('背诗词'), findsOneWidget);

    await _tapTab(tester, '诗词');
    await _pumpUntil(tester, find.textContaining('诗词('));
    expect(find.text('诗词(2)'), findsOneWidget);
    await tester.tap(find.text('静夜思').first);
    await _pumpUntil(tester, find.text('床前明月光'));

    expect(find.text('疑是地上霜'), findsOneWidget);
    await tester.tap(find.byType(AnimatedFavoriteButton));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      HiveBoxes.poemFavorites.containsKey('default_integration_poem'),
      isTrue,
    );

    await tester.tap(find.text('学习'));
    await _pumpUntil(tester, find.text('选择练习方式'));
    await tester.tap(find.text('填空测试'));
    await _pumpUntil(tester, find.textContaining('____'));
    expect(find.text('请输入答案…'), findsOneWidget);
    expect(find.text('提交'), findsOneWidget);
  });

  testWidgets('口算错误答题会落入错题本', (tester) async {
    await HiveBoxes.settings.put('math_batch_size', 1);
    await HiveBoxes.settings.put('math_practice_mode', 'findResult');

    await _startApp(tester);
    await _tapTab(tester, '口算');
    await tester.tap(find.text('口算练习').first);
    await _pumpUntil(tester, find.byType(NumberKeypad));

    final keypad = find.byType(NumberKeypad);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.descendant(of: keypad, matching: find.text('9')));
      await tester.pump();
    }
    await tester.tap(
      find.descendant(
        of: keypad,
        matching: find.byIcon(Icons.check_rounded),
      ),
    );

    await _pumpUntil(tester, find.text('查看成绩'));
    for (var i = 0; i < 160; i++) {
      final button = tester.widget<FilledButton>(find.ancestor(
        of: find.text('查看成绩'), matching: find.byType(FilledButton),
      ),);
      if (button.onPressed != null) break;
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.tap(find.text('查看成绩'));
    await _pumpUntil(tester, find.text('查看错题'));
    expect(HiveBoxes.mathMistakes.values, isNotEmpty);
    await tester.tap(find.text('查看错题'));
    await _pumpUntil(tester, find.byType(MathMistakePage));
  });

  testWidgets('公式详情可以收藏并持久化', (tester) async {
    await _startApp(tester);
    await tester.tap(find.text('查公式'));
    await _pumpUntil(tester, find.text('公式知识库'));

    await tester.tap(find.text('长方形面积'));
    await _pumpUntil(tester, find.byType(AnimatedFavoriteButton));
    await tester.tap(find.byType(AnimatedFavoriteButton));
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      HiveBoxes.formulaFavorites.containsKey('default_integration_formula'),
      isTrue,
    );
  });

  testWidgets('完成每日目标后打卡并保存连续天数', (tester) async {
    await HiveBoxes.settings.put('daily_poem_goal', 1);
    await HiveBoxes.settings.put('daily_math_goal', 1);
    await HiveBoxes.poemProgress.put('default_integration_poem', PoemProgress(
      poemId: 'integration_poem', profileId: 'default',
      status: LearningStatus.learning, lastStudiedAt: DateTime.now(),
    ),);
    await HiveBoxes.mathSessions.put('default_goal', MathSession(
      id: 'goal', profileId: 'default', grade: 1, problemType: 'addition',
      totalProblems: 1, correctCount: 1, durationSeconds: 1,
      startedAt: DateTime.now(), finishedAt: DateTime.now(),
    ),);

    await _startApp(tester);
    await tester.tap(find.text('打卡'));
    await _pumpUntil(tester, find.text('今日已打卡 ✓'));

    expect(find.text('今日已打卡 ✓'), findsOneWidget);
    expect(HiveBoxes.checkIns.values.single.isCheckedIn, isTrue);
    expect(HiveBoxes.userStats.values.single.currentStreak, equals(1));
  });

  testWidgets('离线备份恢复旅程保留本地学习数据', (tester) async {
    await _startApp(tester);
    await _tapTab(tester, '我的');
    await tester.tap(find.byTooltip('设置'));
    await _pumpUntil(tester, find.text('设置'));
    await tester.ensureVisible(find.text('数据与同步'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('数据与同步'));
    await _pumpUntil(tester, find.text('备份与恢复'));
    await tester.tap(find.text('备份与恢复'));
    await _pumpUntil(tester, find.text('导出备份'));
    expect(find.text('从备份恢复'), findsOneWidget);

    await HiveBoxes.settings.put('theme_mode', 'dark');
    await HiveBoxes.mathSessions.put('default_backup', MathSession(
      id: 'backup', profileId: 'default', grade: 1, problemType: 'addition',
      totalProblems: 1, correctCount: 1, durationSeconds: 1,
      startedAt: DateTime.now(), finishedAt: DateTime.now(),
    ),);
    final backup = BackupService();
    final json = await backup.exportToJson();
    await HiveBoxes.mathSessions.clear();
    await HiveBoxes.settings.put('theme_mode', 'light');
    expect(HiveBoxes.settings.get('theme_mode'), 'light');

    final restoredCount = await backup.restoreFromJson(json);
    expect(restoredCount, greaterThan(0));
    expect(HiveBoxes.mathSessions.values.single.id, 'backup');
    expect(
      HiveBoxes.settings.get('theme_mode'),
      equals('dark'),
    );
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

Future<void> _startApp(WidgetTester tester) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(ProviderScope(
    overrides: [
      backupHistoryProvider.overrideWith((ref) => BackupHistoryService(
            backup: ref.read(backupServiceProvider),
            directoryProvider: () async {
              final support = await getApplicationSupportDirectory();
              return Directory('${support.path}/integration_test');
            },
            keyProvider: () async => List<int>.generate(32, (i) => i),
          ),),
    ],
    child: const App(),
  ),);
  await _pumpUntil(tester, find.byType(MainShell));
  await _pumpUntil(tester, find.text('背诗词'));
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  final navigationBar = find.byType(NavigationBar);
  await tester.tap(
    find.descendant(of: navigationBar, matching: find.text(label)),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _pumpUntil(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 160; i++) {
    if (target.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(target, findsOneWidget);
}
