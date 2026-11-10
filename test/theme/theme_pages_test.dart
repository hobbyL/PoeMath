import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/theme_providers.dart';
import 'package:poemath/core/widgets/app_tile.dart';
import 'package:poemath/core/widgets/colored_card.dart';
import 'package:poemath/core/widgets/page_animation_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/challenge_record.dart';
import 'package:poemath/data/models/check_in.dart';
import 'package:poemath/data/models/webdav_config.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/data/models/formula.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/formula/formula_detail_page.dart';
import 'package:poemath/features/chinese/expression/picture_story_page.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/home/home_page.dart';
import 'package:poemath/features/home/learning_calendar_page.dart';
import 'package:poemath/features/profile/cloud_sync_page.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/challenge_history_page.dart';
import 'package:poemath/features/math/math_challenge_page.dart';
import 'package:poemath/features/math/math_session_detail_page.dart';
import 'package:poemath/features/poem/poem_detail_page.dart';
import 'package:poemath/features/poem/poem_recite_mode_page.dart';
import 'package:poemath/features/profile/achievement_page.dart';
import 'package:poemath/features/profile/about_page.dart';
import 'package:poemath/features/profile/ai_settings_page.dart';
import 'package:poemath/features/profile/backup_restore_page.dart';
import 'package:poemath/features/profile/cloud_usage_history_page.dart';
import 'package:poemath/features/profile/learning_stats_page.dart';
import 'package:poemath/features/profile/notification_settings_page.dart';
import 'package:poemath/features/profile/practice_settings_page.dart';
import 'package:poemath/features/profile/profile_page.dart';
import 'package:poemath/features/profile/providers/stats_chart_providers.dart';
import 'package:poemath/features/profile/settings_page.dart';
import 'package:poemath/features/profile/weekly_report_page.dart';

import '../helpers/day_key_override.dart';
import '../helpers/hive_test_helper.dart';
import '../helpers/parent_access_test_helper.dart';
import '../helpers/picture_story_fixture.dart';
import '../helpers/theme_contrast.dart';

class _Tts extends Mock implements TtsService {}

class _Notifications extends Mock implements NotificationService {}

class _BlockedCredentials extends SettingsRepository {
  final loading = Completer<WebDavConfig>();
  final config = WebDavConfig(
    id: 'theme',
    name: '测试网盘',
    url: 'https://example.com',
    username: '',
    password: '',
  );
  @override
  ({List<WebDavConfig> configs, int skipped}) get webDavConfigsDetailed =>
      (configs: [config], skipped: 0);
  @override
  Future<WebDavConfig> loadWebDavConfigWithCredentials(WebDavConfig config) =>
      loading.future;
}

final _session = MathSession(
  id: 'theme-session',
  profileId: 'default',
  grade: 1,
  problemType: 'mixed',
  totalProblems: 15,
  correctCount: 12,
  starsEarned: 2,
  durationSeconds: 73,
  startedAt: DateTime(2026, 11, 10),
  finishedAt: DateTime(2026, 11, 10),
);

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
  await drainHiveWritesForTesting(tester);
}

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme,
  Widget page, {
  SettingsRepository? settings,
  List<Override> overrides = const [],
}) async {
  final tts = _Tts();
  when(() => tts.stop()).thenAnswer((_) async {});
  when(() => tts.currentSessionId).thenReturn(0);
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        staticDayKeyOverride(),
        if (settings != null)
          settingsRepositoryProvider.overrideWithValue(settings),
        ttsServiceProvider.overrideWithValue(tts),
        mistakeCountProvider.overrideWith((ref) => 7),
        dailyStatsProvider(7).overrideWith(
          (ref) => [
            DailyStat(
              date: DateTime(2026, 11, 10),
              poemCount: 3,
              mathTotal: 15,
              mathCorrect: 12,
              starsEarned: 9,
            ),
          ],
        ),
        ...overrides,
      ],
      child: MaterialApp(
        theme: theme,
        home: PageAnimationScope(enabled: false, child: page),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await drainHiveWritesForTesting(tester);
}

void _expectTileIcons(WidgetTester tester) {
  final tiles = find.byType(AppTile);
  expect(tiles, findsWidgets);
  for (final tile in tiles.evaluate()) {
    final widget = tile.widget as AppTile;
    if (widget.icon == null) continue;
    expectReadableIcon(
      tester,
      find.descendant(
        of: find.byWidget(widget),
        matching: find.byIcon(widget.icon!),
      ),
    );
  }
}

void _expectPrimaryTiles(WidgetTester tester, ThemeData theme) {
  final tiles = tester.widgetList<AppTile>(find.byType(AppTile));
  expect(tiles, isNotEmpty);
  for (final tile in tiles) {
    expect(tile.iconColor, theme.colorScheme.primary, reason: tile.title);
    expect(
      tile.backgroundColor ?? tile.iconColor,
      theme.colorScheme.primary,
      reason: tile.title,
    );
  }
  _expectTileIcons(tester);
}

void _expectBarTooltips(WidgetTester tester) {
  final charts = tester.widgetList<BarChart>(find.byType(BarChart));
  expect(charts, isNotEmpty);
  for (final chart in charts) {
    final data = chart.data;
    final tooltip = data.barTouchData.touchTooltipData;
    final group = data.barGroups.first;
    final item = tooltip.getTooltipItem(group, 0, group.barRods.first, 0)!;
    expect(
      contrastRatio(item.textStyle.color!, tooltip.getTooltipColor(group)),
      greaterThanOrEqualTo(4.5),
    );
  }
}

void main() {
  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: '韵算',
      packageName: 'com.poemath.app',
      version: '1.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await setUpHiveForTesting();
    await unlockParentForTesting();
    await HiveBoxes.poems.put(
      'theme-poem',
      Poem(
        id: 'theme-poem',
        title: '静夜思',
        author: '李白',
        dynasty: '唐',
        content: '床前明月光，\n疑是地上霜。',
        pinyin: '',
        layer: 'core',
        grade: 1,
      ),
    );
    await HiveBoxes.formulas.put(
      'theme-formula',
      Formula(
        id: 'theme-formula',
        name: '长方形面积',
        category: '图形',
        formulaText: '面积 = 长 × 宽',
        formulaLatex: '',
        grade: 3,
      ),
    );
    await HiveBoxes.challengeRecords.put(
      'default_theme-record',
      ChallengeRecord(
        id: 'theme-record',
        profileId: 'default',
        mode: 'fixed',
        score: 37,
        totalAnswered: 15,
        correctCount: 12,
        bestCombo: 5,
        grade: 1,
        semester: '上',
        difficulty: 'easy',
        durationSeconds: 73,
      ),
    );
    await HiveBoxes.meta.put('cloud_usage:2026-11-10:asr', 3);
  });
  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForTesting();
  });

  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      final theme = AppTheme.resolve(subject: subject, brightness: brightness);
      final label = '$subject/$brightness';
      testWidgets('$label 设置一级入口保持同一主题色，分类往返后图标和背景一致', (tester) async {
        addTearDown(tester.view.reset);
        await _pump(tester, theme, const SettingsPage());
        final titles = ['外观与反馈', '学习与内容', 'AI 与语音', '家长与数据', '应用与提醒'];
        final reference = find.text(titles.first);
        final cardBackground = solidBackgroundOf(tester.element(reference));
        for (final title in titles) {
          expectReadableText(tester, find.text(title));
          final tile = tester.widget<AppTile>(
            find.ancestor(of: find.text(title), matching: find.byType(AppTile)),
          );
          final icon = find.byIcon(tile.icon!);
          expect(tester.widget<Icon>(icon).color, theme.colorScheme.primary);
          expect(
            solidBackgroundOf(tester.element(find.text(title))),
            cardBackground,
          );
          expectReadableIcon(tester, icon);
          await tester.tap(find.text(title));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          _expectPrimaryTiles(tester, theme);
          await tester.pageBack();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(tester.widget<Icon>(icon).color, theme.colorScheme.primary);
          expect(
            solidBackgroundOf(tester.element(find.text(title))),
            cardBackground,
          );
        }
        await _unmount(tester);
      });
      testWidgets('$label 关于页版本、版权及隐私政策正文清晰', (tester) async {
        addTearDown(tester.view.reset);
        await _pump(tester, theme, const AboutPage());
        _expectPrimaryTiles(tester, theme);
        expectReadableText(tester, find.text('v1.0 (1)'));
        expectReadableText(tester, find.textContaining('©'));
        await tester.runAsync(() async {
          await tester.tap(find.text('隐私政策'));
          await rootBundle.loadString('assets/legal/privacy_policy.md');
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final policy = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Text),
        );
        // 等待页面自己的转换 Future，避免资产 I/O 跨 FakeAsync 区域悬挂。
        final body = tester.widget<FutureBuilder<String>>(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(FutureBuilder<String>),
          ),
        );
        await tester.runAsync(() => body.future!);
        await tester.pump();
        expect(policy, findsNWidgets(2));
        expectReadableText(tester, policy);
        await _unmount(tester);
      });
      testWidgets('$label 首页快捷入口与错题数、设置卡片图标可读', (tester) async {
        addTearDown(tester.view.reset);
        await _pump(tester, theme, const HomePage());
        for (final name in ['做口算', '查公式', '错题本', '7']) {
          expectReadableText(tester, find.text(name));
        }
        _expectPrimaryTiles(tester, theme);
        await _unmount(tester);
        await _pump(tester, theme, const SettingsPage());
        await tester.tap(find.text('外观与反馈'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('外观模式'), findsOneWidget);
        _expectPrimaryTiles(tester, theme);
        await _unmount(tester);
      });

      testWidgets('$label 诗词详情和模式预览保持阅读字号、四个模式可辨认', (tester) async {
        addTearDown(tester.view.reset);
        await _pump(tester, theme, const PoemDetailPage(poemId: 'theme-poem'));
        final line = find.text('床前明月光，');
        expectReadableText(tester, line);
        expectReadableText(tester, find.text('生成讲解'));
        expect(
          tester.widget<Text>(line).style!.fontSize,
          greaterThanOrEqualTo(20),
        );
        await _unmount(tester);
        await _pump(
          tester,
          theme,
          const PoemReciteModePage(poemId: 'theme-poem'),
        );
        _expectPrimaryTiles(tester, theme);
        await tester.tap(find.text('诗文预览'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final preview = find.text('床前明月光，\n疑是地上霜。');
        expectReadableText(tester, preview);
        expect(
          tester.widget<Text>(preview).style!.fontSize,
          greaterThanOrEqualTo(20),
        );
        await _unmount(tester);
      });

      testWidgets('$label 公式年级、口算用时和挑战最高分可读', (tester) async {
        addTearDown(tester.view.reset);
        await _pump(
          tester,
          theme,
          const FormulaDetailPage(formulaId: 'theme-formula'),
        );
        expectReadableText(tester, find.text('3年级'));
        await _unmount(tester);
        await _pump(tester, theme, MathSessionDetailPage(session: _session));
        expectReadableText(tester, find.text('1分13秒'));
        await _unmount(tester);
        await _pump(tester, theme, const ChallengeHistoryPage());
        expectReadableText(tester, find.text('37'));
        expectReadableText(tester, find.text('1年级上学期'));
        expectReadableIcon(tester, find.byIcon(Icons.hourglass_top_rounded));
        await _unmount(tester);
        await _pump(tester, theme, const MathChallengePage());
        expect(find.text('固定时间'), findsOneWidget);
        expectReadableText(tester, find.text('普通'));
        expectReadableIcon(tester, find.byIcon(Icons.radio_button_checked));
        await _unmount(tester);
      });

      testWidgets('$label 我的、成就、练习设置中的统计与必要图标可读', (tester) async {
        addTearDown(tester.view.reset);
        await _pump(tester, theme, const ProfilePage());
        _expectPrimaryTiles(tester, theme);
        for (final icon in [
          Icons.bar_chart_rounded,
          Icons.calendar_month_rounded,
          Icons.emoji_events_rounded,
        ]) {
          expect(
            tester.widget<Icon>(find.byIcon(icon)).color,
            theme.colorScheme.primary,
          );
        }
        final stat = find
            .ancestor(of: find.text('连续打卡'), matching: find.byType(Column))
            .first;
        expectReadableText(
          tester,
          find.descendant(of: stat, matching: find.byType(Text)),
        );
        await _unmount(tester);
        await _pump(tester, theme, const AchievementPage());
        for (final name in ['复习', '错题']) {
          await tester.scrollUntilVisible(find.text(name), 400);
          expectReadableText(tester, find.text(name));
        }
        await _unmount(tester);
        await _pump(tester, theme, const PracticeSettingsPage());
        for (final card in tester.widgetList<ColoredCard>(
          find.byType(ColoredCard),
        )) {
          expect(card.color, theme.colorScheme.primary);
        }
        expectReadableIcon(tester, find.byIcon(Icons.speed_rounded));
        expectReadableIcon(tester, find.byIcon(Icons.calculate_rounded));
        await _unmount(tester);
      });

      testWidgets('$label AI 设置与备份操作使用主题主色', (tester) async {
        addTearDown(tester.view.reset);
        await _pump(tester, theme, const AiSettingsPage());
        _expectPrimaryTiles(tester, theme);
        await _unmount(tester);
        await _pump(tester, theme, const BackupRestorePage());
        _expectPrimaryTiles(tester, theme);
        for (final title in ['导出备份', '从备份恢复']) {
          final card = tester.widget<ColoredCard>(
            find.ancestor(
              of: find.text(title),
              matching: find.byType(ColoredCard),
            ),
          );
          expect(card.color, theme.colorScheme.primary);
          expectReadableText(tester, find.text(title));
        }
        await _unmount(tester);
      });

      testWidgets('$label 提醒设置与表达题目卡片跟随主色', (tester) async {
        addTearDown(tester.view.reset);
        final notifications = _Notifications();
        when(() => notifications.isReminderEnabled).thenReturn(true);
        when(() => notifications.reminderHour).thenReturn(18);
        when(() => notifications.reminderMinute).thenReturn(30);
        when(() => notifications.isWeeklyReportEnabled).thenReturn(false);
        when(() => notifications.isReminderDegraded).thenReturn(false);
        await _pump(
          tester,
          theme,
          NotificationSettingsPage(notificationService: notifications),
        );
        expectReadableText(tester, find.text('查看本周学习周报'));
        for (final card in tester.widgetList<ColoredCard>(
          find.byType(ColoredCard),
        )) {
          expect(card.color, theme.colorScheme.primary);
        }
        await _unmount(tester);
        await _pump(
          tester,
          theme,
          const PictureStoryPage(),
          overrides: [
            pictureStoryPromptProvider.overrideWithValue([
              pictureStoryFixture(),
            ]),
          ],
        );
        final card = tester.widget<ColoredCard>(
          find.ancestor(
            of: find.text('窗前的小猫'),
            matching: find.byType(ColoredCard),
          ),
        );
        expect(card.color, theme.colorScheme.primary);
        expectReadableText(tester, find.text('窗前的小猫'));
        await _unmount(tester);
      });

      testWidgets('$label 日历五级热力日期及详情清晰，下载忙碌图标匹配禁用底色', (tester) async {
        addTearDown(tester.view.reset);
        final now = DateTime.now();
        await tester.runAsync(() async {
          for (final (day, poems) in [(12, 1), (13, 5), (14, 15), (15, 25)]) {
            final date =
                '${now.year}-${now.month.toString().padLeft(2, '0')}-$day';
            await HiveBoxes.checkIns.put(
              'default_$date',
              CheckIn(profileId: 'default', date: date, poemCount: poems),
            );
          }
        });
        await _pump(tester, theme, const LearningCalendarPage());
        for (final day in [12, 13, 14, 15, 16]) {
          expectReadableText(tester, find.text('$day'));
        }
        await tester.tap(find.text('12'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expectReadableText(tester, find.text('1 首'));
        expectReadableIcon(tester, find.byIcon(Icons.calculate_rounded).last);
        await _unmount(tester);
        final settings = _BlockedCredentials();
        await _pump(tester, theme, const CloudSyncPage(), settings: settings);
        await tester.tap(find.text('测试网盘'));
        await tester.pump();
        await tester.tap(find.text('从云端下载'));
        await tester.pump();
        expect(find.text('下载中…'), findsOneWidget);
        final spinner = find.byType(CircularProgressIndicator);
        expect(spinner, findsOneWidget);
        final indicator = tester.widget<CircularProgressIndicator>(spinner);
        expect(
          contrastRatio(
            indicator.color!,
            solidBackgroundOf(tester.element(spinner)),
          ),
          greaterThanOrEqualTo(3),
        );
        // 在凭据读取阶段结束替身，不触发网络或备份恢复。
        settings.loading.completeError(StateError('模拟凭据不可读'));
        await tester.pump();
        expect(find.text('下载中…'), findsNothing);
        await _unmount(tester);
      });

      testWidgets('$label 学习报告、周报、云用量的数值与图表提示配色正确', (tester) async {
        addTearDown(tester.view.reset);
        await _pump(tester, theme, const LearningStatsPage());
        expectReadableText(tester, find.text('15'));
        _expectBarTooltips(tester);
        final line = tester.widget<LineChart>(find.byType(LineChart));
        final spot = LineBarSpot(
          line.data.lineBarsData.first,
          0,
          line.data.lineBarsData.first.spots.first,
        );
        final tooltip = line.data.lineTouchData.touchTooltipData;
        expect(
          contrastRatio(
            tooltip.getTooltipItems([spot]).single!.textStyle.color!,
            tooltip.getTooltipColor(spot),
          ),
          greaterThanOrEqualTo(4.5),
        );
        await _unmount(tester);
        await _pump(tester, theme, const WeeklyReportPage());
        expectReadableText(tester, find.text('15'));
        _expectBarTooltips(tester);
        await _unmount(tester);
        await _pump(
          tester,
          theme,
          CloudUsageHistoryPage(
            usage: CloudUsageService(clock: () => DateTime(2026, 11, 10)),
          ),
        );
        expect(find.text('语音识别'), findsOneWidget);
        expectReadableIcon(tester, find.byIcon(Icons.mic_none_rounded));
        _expectBarTooltips(tester);
        await _unmount(tester);
      });
    }
  }

  testWidgets('日历详情打开期间切换主题，统计文字即时更新且仍可关闭', (tester) async {
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-12';
    await tester.runAsync(
      () => HiveBoxes.checkIns.put(
        'default_$date',
        CheckIn(
          profileId: 'default',
          date: date,
          poemCount: 1,
          mathCorrectCount: 7,
          mathTotalCount: 9,
          activitySources: CheckIn.mathActivitySource,
        ),
      ),
    );
    final container = ProviderContainer(overrides: [staticDayKeyOverride()]);
    addTearDown(container.dispose);
    container.read(activeSubjectProvider.notifier).setSubject(AppSubject.math);
    container.read(themeModeProvider.notifier).setMode(ThemeMode.light);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: ref.watch(lightThemeProvider),
            darkTheme: ref.watch(darkThemeProvider),
            themeMode: ref.watch(themeModeProvider),
            home: const LearningCalendarPage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('12'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final before = tester.widget<Text>(find.text('7/9 题')).style!.color;
    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      container.read(themeModeProvider.notifier).setMode(mode);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expectReadableText(tester, find.text('7/9 题'));
      expect(
        tester.widget<Text>(find.text('7/9 题')).style!.color,
        mode == ThemeMode.dark ? isNot(before) : before,
      );
    }
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BottomSheet), findsNothing);
    await _unmount(tester);
  });

  testWidgets('主题切换时已打开的外观 Sheet 即时刷新，关闭后页面保持主题且重建恢复偏好', (tester) async {
    final container = ProviderContainer(overrides: [staticDayKeyOverride()]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: ref.watch(lightThemeProvider),
            darkTheme: ref.watch(darkThemeProvider),
            themeMode: ref.watch(themeModeProvider),
            home: const SettingsPage(),
          ),
        ),
      ),
    );
    await tester.tap(find.text('外观与反馈'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('外观模式'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('跟随系统'), findsWidgets);
    container.read(activeSubjectProvider.notifier).setSubject(AppSubject.math);
    container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final sheet = tester.element(find.byType(BottomSheet));
    expect(Theme.of(sheet).brightness, Brightness.dark);
    expect(
      Theme.of(sheet).colorScheme.primary,
      AppTheme.resolve(
        subject: AppSubject.math,
        brightness: Brightness.dark,
      ).colorScheme.primary,
    );
    Navigator.of(sheet).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('外观模式'), findsOneWidget);
    _expectTileIcons(tester);
    await _unmount(tester);
    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    expect(restored.read(activeSubjectProvider), AppSubject.math);
    expect(restored.read(themeModeProvider), ThemeMode.dark);
  });
}
