import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/achievement.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/achievement_repository.dart';
import 'package:poemath/data/repositories/check_in_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/data/repositories/user_stats_repository.dart';
import 'package:poemath/features/poem/poem_dictation_page.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/poem/poem_practice_draft.dart';
import 'package:poemath/features/poem/poem_quiz_page.dart';
import 'package:poemath/features/poem/poem_recite_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';
import 'package:poemath/features/poem/quiz/quiz_models.dart';
import 'package:poemath/features/poem/widgets/poem_sentence_writing_sheet.dart';
import 'package:poemath/features/textbook/writing/stroke_data_provider.dart';
import 'package:poemath/features/textbook/writing/writing_canvas.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/recording_sound_service.dart';

class _Tts extends Mock implements TtsService {}

class _Achievements extends AchievementRepository {
  @override
  Achievement? getById(String id) =>
      Achievement(id: id, profileId: 'default', title: id, isUnlocked: true);
}

class _FailDraft extends PracticeDraftRepository {
  bool fail = false;
  bool failRemoval = false;
  @override
  Future<void> save(String kind, Map<String, dynamic> data, {String? scope}) {
    if (fail) return Future.error(StateError('模拟磁盘不可写'));
    return super.save(kind, data, scope: scope);
  }

  @override
  Future<void> remove(String kind, {String? sessionId, String? scope}) {
    if (failRemoval) return Future.error(StateError('模拟草稿清理失败'));
    return super.remove(kind, sessionId: sessionId, scope: scope);
  }
}

class _FailCheckIn extends CheckInRepository {
  bool fail = true;
  @override
  Future<void> updateForDate(
    DateTime date, {
    String? activityId,
    int? addPoems,
    int? addMathTotal,
    int? addMathCorrect,
    int? addStars,
    int? addDuration,
  }) async {
    if (fail) throw StateError('模拟汇总写入失败');
    return super.updateForDate(
      date,
      activityId: activityId,
      addPoems: addPoems,
      addMathTotal: addMathTotal,
      addMathCorrect: addMathCorrect,
      addStars: addStars,
      addDuration: addDuration,
    );
  }
}

Future<void> _io(WidgetTester tester, {bool Function()? until}) async {
  for (var i = 0; i < (until == null ? 8 : 100); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 40));
    if (until?.call() ?? false) return;
  }
  if (until != null) expect(until(), isTrue, reason: '等待真实 Hive 写入与界面完成');
}

void main() {
  late _Tts tts;
  final poem = Poem(
    id: 'resume-poem',
    title: '续练诗',
    author: '作者',
    dynasty: '唐',
    content: '床前明月光\n疑是地上霜\n举头望明月',
    pinyin: '',
    layer: 'core',
    grade: 1,
  );
  PracticeDraftRepository repo() => PracticeDraftRepository();
  String scope(String variant) => jsonEncode([poem.id, variant]);
  Map<String, dynamic> draft(String kind, String variant) =>
      repo().get(kind, scope: scope(variant))!;

  setUp(() async {
    await setUpHiveForTesting();
    await HiveBoxes.settings.put('haptic_enabled', false);
    tts = _Tts();
    when(() => tts.currentSessionId).thenReturn(1);
    when(() => tts.stop()).thenAnswer((_) async {});
    when(() => tts.speakLines(any(), onReady: any(named: 'onReady')))
        .thenAnswer((_) async {});
  });
  tearDown(tearDownHiveForWidgetTesting);

  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    PracticeDraftRepository? drafts,
    CheckInRepository? checkIn,
  }) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          poemByIdProvider(poem.id).overrideWithValue(poem),
          filteredPoemsProvider.overrideWithValue([poem]),
          soundServiceProvider.overrideWithValue(RecordingSoundService()),
          ttsServiceProvider.overrideWithValue(tts),
          achievementRepoProvider.overrideWithValue(_Achievements()),
          writingStrokeDataProvider.overrideWith(
            (ref) => const WritingStrokeAsset({}),
          ),
          if (drafts != null)
            poemPracticeDraftRepositoryFactoryProvider.overrideWithValue(
              () => drafts,
            ),
          if (checkIn != null) checkInRepoProvider.overrideWithValue(checkIn),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    Navigator.of(context)
                        .push<void>(MaterialPageRoute(builder: (_) => page)),
                child: const Text('打开练习'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开练习'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await _io(tester);
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton));
    await _io(tester, until: () => find.text('打开练习').evaluate().isNotEmpty);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> reopen(WidgetTester tester, {String choice = '继续上次'}) async {
    await tester.tap(find.text('打开练习'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text(choice));
    await _io(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _io(tester);
    await drainHiveWritesForTesting(tester);
  }

  void resumeTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await close(tester);
        // 完整结算涉及多个 box；在 fake 区发起 close 并轮询 IO，
        // 不能把尚未排空的完成回调留给真实区的 tearDown。
        var closed = false;
        final closing = HiveBoxes.close().then((_) => closed = true);
        await _io(tester, until: () => closed);
        await closing;
      }
    });
  }

  resumeTest('测试保留原题顺序、已答与第二题输入，取消保留，完成只记录一次', (tester) async {
    await mount(
      tester,
      PoemQuizPage(poemId: poem.id, quizType: QuizType.fillBlank),
    );
    final initial = draft('poemQuiz', 'fillBlank');
    final questions =
        ((initial['state'] as Map)['session'] as Map)['questions'] as List;
    expect(questions, hasLength(2));
    await tester.enterText(
      find.byType(TextField),
      (questions.first as Map)['correct'] as String,
    );
    await tester.tap(find.text('提交'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('下一题'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(find.byType(TextField), '未写完的答案');
    await leave(tester);
    final saved = draft('poemQuiz', 'fillBlank');
    expect(((saved['state'] as Map)['session'] as Map)['index'], 1);
    await reopen(tester, choice: '取消');
    expect(find.text('打开练习'), findsOneWidget);
    expect(draft('poemQuiz', 'fillBlank')['sessionId'], initial['sessionId']);
    await reopen(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '未写完的答案',
    );
    expect(
      ((draft('poemQuiz', 'fillBlank')['state'] as Map)['session']
          as Map)['questions'],
      questions,
    );
    await tester.enterText(
      find.byType(TextField),
      (questions.last as Map)['correct'] as String,
    );
    await tester.tap(find.text('提交'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('查看结果'));
    await _io(
      tester,
      until: () => !repo().exists('poemQuiz', scope: scope('fillBlank')),
    );
    expect(PoemProgressRepository().get(poem.id)!.studyCount, 1);
    expect(
      HiveBoxes.learningActivities.values.where((a) => a.poemId == poem.id),
      hasLength(1),
    );
  });

  resumeTest('背诵保存难度、提示和当前随机空位，重开只在明确选择后发生', (tester) async {
    await mount(tester, PoemRecitePage(poemId: poem.id));
    await tester.tap(find.text('困难'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('显示拼音提示'));
    await tester.pump();
    await leave(tester);
    final saved = draft('poemRecite', 'levels');
    await reopen(tester);
    final state = draft('poemRecite', 'levels')['state'] as Map;
    expect(state['level'], 'hard');
    expect(state['hintUsed'], true);
    expect(state['blanks'], (saved['state'] as Map)['blanks']);
    expect(find.text('已显示提示'), findsOneWidget);
    await leave(tester);
    await reopen(tester, choice: '开始新练习');
    expect(
      draft('poemRecite', 'levels')['sessionId'],
      isNot(saved['sessionId']),
    );
    expect((draft('poemRecite', 'levels')['state'] as Map)['level'], 'easy');
  });

  resumeTest('背诵键盘输入与听写未确认笔迹退出后恢复', (tester) async {
    await mount(tester, PoemRecitePage(poemId: poem.id));
    await tester.tap(find.text('默写'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byTooltip('切换键盘输入'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(find.byType(TextField), '床前明');
    await leave(tester);
    await reopen(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '床前明',
    );
    await close(tester);
    await mount(tester, PoemDictationPage(poemId: poem.id));
    await tester.tap(find.text('默写'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final canvas = find.byType(WritingCanvas).first;
    await tester.drag(canvas, const Offset(50, 10));
    await tester.pump();
    await leave(tester);
    await reopen(tester);
    final sheet = tester.widget<PoemSentenceWritingSheet>(
      find.byType(PoemSentenceWritingSheet),
    );
    expect(sheet.pendingInk!.strokes, isNotEmpty);
    expect(
      tester.widget<WritingCanvas>(find.byType(WritingCanvas).first).strokes,
      isNotEmpty,
    );
  });

  resumeTest('草稿写入失败保留页面及输入，重试成功才返回', (tester) async {
    final failing = _FailDraft();
    await mount(
      tester,
      PoemQuizPage(poemId: poem.id, quizType: QuizType.fillBlank),
      drafts: failing,
    );
    failing.fail = true;
    await tester.enterText(find.byType(TextField), '保留我的答案');
    await tester.tap(find.byType(BackButton));
    await _io(tester);
    expect(find.byType(PoemQuizPage), findsOneWidget);
    expect(find.text('进度保存失败，请重试后再离开'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '保留我的答案',
    );
    failing.fail = false;
    await tester.tap(find.text('重试保存'));
    await _io(tester);
    await leave(tester);
    expect((draft('poemQuiz', 'fillBlank')['state'] as Map)['input'], '保留我的答案');
  });

  resumeTest('后台保存当前输入且暂停时长，回到前台继续计时', (tester) async {
    await mount(
      tester,
      PoemQuizPage(poemId: poem.id, quizType: QuizType.fillBlank),
    );
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.enterText(find.byType(TextField), '暂停前的输入');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _io(tester);
    final paused = draft('poemQuiz', 'fillBlank');
    expect((paused['state'] as Map)['input'], '暂停前的输入');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await _io(tester);
    expect(draft('poemQuiz', 'fillBlank')['elapsedMs'], paused['elapsedMs']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await leave(tester);
    expect(
      draft('poemQuiz', 'fillBlank')['elapsedMs'],
      greaterThan(paused['elapsedMs'] as int),
    );
  });

  resumeTest('旧版本草稿先提示，取消保留，仅明确重开才替换', (tester) async {
    await mount(
      tester,
      PoemQuizPage(poemId: poem.id, quizType: QuizType.fillBlank),
    );
    await leave(tester);
    final old = draft('poemQuiz', 'fillBlank');
    final writer = repo()..claim('poemQuiz', scope: scope('fillBlank'));
    var written = false;
    final saving = writer
        .save('poemQuiz', {
          ...old,
          'poemVersion': 99,
        }, scope: scope('fillBlank'))
        .then((_) => written = true);
    await _io(tester, until: () => written);
    await saving;
    await tester.tap(find.text('打开练习'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('这份草稿无法继续'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await _io(tester);
    expect(draft('poemQuiz', 'fillBlank')['sessionId'], old['sessionId']);
    await reopen(tester, choice: '开始新练习');
    expect(
      draft('poemQuiz', 'fillBlank')['sessionId'],
      isNot(old['sessionId']),
    );
  });

  resumeTest('损坏的背诵填空下标提示重开，取消时仍保留原草稿', (tester) async {
    await mount(tester, PoemRecitePage(poemId: poem.id));
    await leave(tester);
    final old = draft('poemRecite', 'levels');
    final state = Map<String, dynamic>.from(old['state'] as Map);
    state['blank'] = (state['blanks'] as List).length;
    final repository = repo()..claim('poemRecite', scope: scope('levels'));
    var written = false;
    final saving = repository
        .save('poemRecite', {...old, 'state': state}, scope: scope('levels'))
        .then((_) => written = true);
    await _io(tester, until: () => written);
    await saving;
    await reopen(tester);
    expect(find.text('这份草稿无法继续'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await _io(tester);
    expect(draft('poemRecite', 'levels')['sessionId'], old['sessionId']);
    expect(tester.takeException(), isNull);
  });

  for (final failure in ['汇总写入', '草稿清理']) {
    resumeTest('$failure失败退出再进入保持活动 ID 与完成时间，不重复次数和星星', (tester) async {
      final checkIn = _FailCheckIn()..fail = failure == '汇总写入';
      final drafts = _FailDraft()..failRemoval = failure == '草稿清理';
      await mount(
        tester,
        PoemQuizPage(poemId: poem.id, quizType: QuizType.chooseAuthor),
        checkIn: checkIn,
        drafts: drafts,
      );
      final questions =
          ((draft('poemQuiz', 'chooseAuthor')['state'] as Map)['session']
                  as Map)['questions']
              as List;
      for (var i = 0; i < questions.length; i++) {
        await tester.tap(find.text(poem.author));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        if (i < questions.length - 1) {
          await tester.tap(find.text('下一题'));
          await tester.pump();
        }
      }
      await tester.tap(find.text('查看结果'));
      await _io(tester, until: () => find.text('重试保存').evaluate().isNotEmpty);
      final saved = draft('poemQuiz', 'chooseAuthor');
      final stars = UserStatsRepository().get().totalStars;
      expect(PoemProgressRepository().get(poem.id)!.studyCount, 1);
      await leave(tester);
      checkIn.fail = false;
      drafts.failRemoval = false;
      await reopen(tester);
      await _io(
        tester,
        until: () => !repo().exists('poemQuiz', scope: scope('chooseAuthor')),
      );
      final activities = HiveBoxes.learningActivities.values
          .where((a) => a.poemId == poem.id)
          .toList();
      expect(activities, hasLength(1));
      expect(activities.single.id, saved['sessionId']);
      expect(
        activities.single.completedAt.toIso8601String(),
        (saved['state'] as Map)['completedAt'],
      );
      expect(PoemProgressRepository().get(poem.id)!.studyCount, 1);
      expect(UserStatsRepository().get().totalStars, stars);
    });
  }
}
