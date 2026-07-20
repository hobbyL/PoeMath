// Shared user journeys for Android integration tests.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/app.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/widgets/animated_favorite_button.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/formula.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/features/math/widgets/number_keypad.dart';
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
    await tester.tap(find.textContaining('开始练习').first);
    await _pumpUntil(tester, find.byType(NumberKeypad));

    final keypad = find.byType(NumberKeypad);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.descendant(of: keypad, matching: find.text('9')));
    }
    await tester.tap(
      find.descendant(
        of: keypad,
        matching: find.byIcon(Icons.check_rounded),
      ),
    );

    await _pumpUntil(tester, find.text('查看错题'));
    expect(HiveBoxes.mathMistakes.values, isNotEmpty);
    await tester.tap(find.text('查看错题'));
    await _pumpUntil(tester, find.text('错题本'));
  });

  testWidgets('公式详情可以收藏并持久化', (tester) async {
    await _startApp(tester);
    await tester.tap(find.text('查公式'));
    await _pumpUntil(tester, find.text('公式知识库'));

    await tester.tap(find.text('长方形面积'));
    await _pumpUntil(tester, find.text('长方形面积'));
    await tester.tap(find.byType(AnimatedFavoriteButton));
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      HiveBoxes.formulaFavorites.containsKey('default_integration_formula'),
      isTrue,
    );
  });

  testWidgets('完成每日目标后打卡并保存连续天数', (tester) async {
    await HiveBoxes.settings.put('daily_poem_goal', 0);
    await HiveBoxes.settings.put('daily_math_goal', 0);

    await _startApp(tester);
    await tester.tap(find.text('打卡'));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('今日已打卡 ✓'), findsOneWidget);
    expect(HiveBoxes.checkIns.values.single.isCheckedIn, isTrue);
    expect(HiveBoxes.userStats.values.single.currentStreak, equals(1));
  });

  testWidgets('离线备份恢复旅程保留本地学习数据', (tester) async {
    await _startApp(tester);
    await _tapTab(tester, '我的');
    await tester.tap(find.byTooltip('设置'));
    await _pumpUntil(tester, find.text('设置'));
    await tester.tap(find.text('备份与恢复'));
    await _pumpUntil(tester, find.text('导出备份'));
    expect(find.text('从备份恢复'), findsOneWidget);

    await HiveBoxes.settings.put('integration_marker', 'before-backup');
    final backup = BackupService();
    final json = backup.exportToJson();
    await HiveBoxes.settings.clear();
    expect(HiveBoxes.settings.get('integration_marker'), isNull);

    final restoredCount = await backup.restoreFromJson(json);
    expect(restoredCount, greaterThan(0));
    expect(
      HiveBoxes.settings.get('integration_marker'),
      equals('before-backup'),
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
  await tester.pumpWidget(const ProviderScope(child: App()));
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
  for (var i = 0; i < 20; i++) {
    if (target.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(target, findsOneWidget);
}
