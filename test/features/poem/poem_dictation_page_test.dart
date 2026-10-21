// test/features/poem/poem_dictation_page_test.dart
//
// ⑧ 诗词听写页 Widget 测试：
// 点选完整流程（拼对/拼错）、打字模式、模式切换、
// 得分两分支的 pop 值与侧信道分数、退出停播。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/data/repositories/learning_activity_repository.dart';
import 'package:poemath/data/repositories/user_stats_repository.dart';
import 'package:poemath/data/repositories/check_in_repository.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/domain/poem_practice_details.dart';
import '../../helpers/hive_test_helper.dart';
import '../../helpers/recording_sound_service.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/poem/poem_dictation_page.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/poem/poem_practice_result.dart';
import 'package:poemath/features/poem/poem_practice_score.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

class _MockTtsService extends Mock implements TtsService {}

class _Progress extends PoemProgressRepository {
  int studies = 0;
  @override
  int get learnedCount => 1;
  @override
  Future<PoemProgress> recordStudy(String poemId) async {
    studies++;
    return PoemProgress(
      poemId: poemId,
      profileId: 'default',
      studyCount: studies,
    );
  }
}

class _Activities extends LearningActivityRepository {
  final types = <LearningActivityType>[];
  String? details;
  int? stars;
  @override
  Future<bool> record({
    required String id,
    required LearningActivityType activityType,
    required int totalItems,
    required int successfulItems,
    required int starsEarned,
    required int durationSeconds,
    required DateTime completedAt,
    String? poemId,
    String? detailsJson,
  }) async {
    types.add(activityType);
    details = detailsJson;
    stars = starsEarned;
    return true;
  }
}

class _Stats extends UserStatsRepository {
  @override
  Future<void> updatePoemStats({int? learned, int? mastered}) async {}
  @override
  Future<void> addStars(int count, {String? activityId}) async {}
}

class _CheckIn extends CheckInRepository {
  bool failNext = false;
  Completer<void>? pending;
  int calls = 0;
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
    if (failNext) {
      failNext = false;
      throw StateError('模拟汇总保存失败');
    }
    if (pending != null) await pending!.future;
    calls++;
  }
}

const _poemId = 'dictation-test-poem';

Poem _makePoem() {
  return Poem(
    id: _poemId,
    title: '静夜思',
    author: '李白',
    dynasty: '唐',
    content: '床前明月光，\n疑是地上霜。',
    pinyin: '',
    layer: 'core',
    grade: 1,
  );
}

void main() {
  late RecordingSoundService sound;
  late _MockTtsService tts;
  late _Progress progress;
  late _Activities activities;
  late _CheckIn checkIn;

  setUp(() async {
    await setUpHiveForTesting();
    sound = RecordingSoundService();
    progress = _Progress();
    activities = _Activities();
    checkIn = _CheckIn();
    tts = _MockTtsService();
    // 朗读立即完成、无回调（onReady 不触发 → 遮罩不出现）。
    when(
      () => tts.speakLines(
        any(),
        onLineStart: any(named: 'onLineStart'),
        onReady: any(named: 'onReady'),
        onComplete: any(named: 'onComplete'),
      ),
    ).thenAnswer((_) async {});
    when(() => tts.stop()).thenAnswer((_) async {});
    when(() => tts.currentSessionId).thenReturn(1);
  });

  tearDown(tearDownHiveForTesting);

  Future<ProviderContainer> pumpPage(
    WidgetTester tester, {
    Poem? poem,
    List<int>? targetLineIndices,
  }) async {
    final container = ProviderContainer(
      overrides: [
        soundServiceProvider.overrideWithValue(sound),
        ttsServiceProvider.overrideWithValue(tts),
        poemProgressRepoProvider.overrideWithValue(progress),
        learningActivityRepositoryProvider.overrideWithValue(activities),
        userStatsRepoProvider.overrideWithValue(_Stats()),
        checkInRepoProvider.overrideWithValue(checkIn),
        poemByIdProvider(_poemId).overrideWith((ref) => poem ?? _makePoem()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: PoemDictationPage(
            poemId: _poemId,
            targetLineIndices: targetLineIndices,
          ),
        ),
      ),
    );
    await tester.pump();
    // postFrameCallback 触发 _initPoem 与首句朗读。
    await tester.pump(const Duration(milliseconds: 100));
    return container;
  }

  /// 按顺序点选候选格拼出 [text]（按字符匹配第一个未用尽的格）。
  Future<void> pickChars(WidgetTester tester, String text) async {
    for (final ch in text.characters) {
      final tiles = find.ancestor(
        of: find.text(ch),
        matching: find.byType(InkWell),
      );
      // 同字可能有多个候选格（本句字 + 干扰字），取第一个可点的。
      var tapped = false;
      for (var i = 0; i < tiles.evaluate().length; i++) {
        final one = tiles.at(i);
        if (tester.widget<InkWell>(one).onTap != null) {
          await tester.tap(one);
          tapped = true;
          break;
        }
      }
      if (!tapped) {
        fail('没有找到字符「$ch」的可点候选格');
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('错句专项只练目标句，保存实际作答且无全诗奖励或复习结果', (tester) async {
    final container = await pumpPage(tester, targetLineIndices: [1]);
    await pickChars(tester, '疑是地上霜');
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump();
    expect(activities.stars, 0);
    final details = PoemPracticeDetails.decode(activities.details)!;
    expect(details.targeted, isTrue);
    expect(details.lines.single.lineIndex, 1);
    expect(details.lines.single.answer, '疑是地上霜');
    expect(details.lines.single.passed, isTrue);
    expect(find.textContaining('全诗掌握和复习轮次保持原值'), findsOneWidget);
    await tester.ensureVisible(find.text('完成'));
    await tester.tap(find.text('完成'));
    await tester.pump();
    expect(container.read(lastPracticeScoreProvider), isNull);
    expect(
      PoemPracticeResult.targetedPracticeCompleted.completesReview,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('听写保存失败不播放，成功重试播放一次', (tester) async {
    checkIn.failNext = true;
    await pumpPage(tester, targetLineIndices: [0]);
    await pickChars(tester, '床前明月光');
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump();
    expect(sound.completions, 0);
    await tester.ensureVisible(find.text('重试保存'));
    await tester.tap(find.text('重试保存'));
    await tester.pump();
    expect(sound.completions, 1);
    expect(checkIn.calls, 1);
    expect(progress.studies, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('听写保存途中退出，保存完成后不播放', (tester) async {
    checkIn.pending = Completer<void>();
    await pumpPage(tester, targetLineIndices: [0]);
    await pickChars(tester, '床前明月光');
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    checkIn.pending!.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(sound.completions, 0);
    expect(checkIn.calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('进入页面清空侧信道陈旧分数', (tester) async {
    // 先预置陈旧分数，再挂载页面（_initPoem 在 postFrame 内清空）。
    final container = ProviderContainer(
      overrides: [
        ttsServiceProvider.overrideWithValue(tts),
        poemByIdProvider(_poemId).overrideWith((ref) => _makePoem()),
      ],
    );
    addTearDown(container.dispose);
    container.read(lastPracticeScoreProvider.notifier).state = 0.5;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PoemDictationPage(poemId: _poemId)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(lastPracticeScoreProvider), isNull);
  });

  testWidgets('两句全部拼对：得分 100%，pop quizPassed 且侧信道 1.0', (tester) async {
    final container = await pumpPage(tester);

    final popResults = <PoemPracticeResult?>[];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                unawaited(
                  Navigator.of(context)
                      .push<PoemPracticeResult>(
                        MaterialPageRoute(
                          builder: (_) =>
                              const PoemDictationPage(poemId: _poemId),
                        ),
                      )
                      .then((r) => popResults.add(r)),
                );
              },
              child: const Text('开始听写'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开始听写'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 第 1 句：床前明月光（候选格打乱，按目标字逐个点选）
    await pickChars(tester, '床前明月光');
    // 判定反馈期 900ms
    await tester.pump(const Duration(milliseconds: 950));
    // 第 2 句：疑是地上霜
    await pickChars(tester, '疑是地上霜');
    await tester.pump(const Duration(milliseconds: 950));

    await tester.pump();
    expect(activities.types, [LearningActivityType.poemDictation]);
    expect(progress.studies, 1);
    expect(find.text('听写完成！'), findsOneWidget);
    expect(sound.completions, 1);

    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(popResults.single, PoemPracticeResult.quizPassed);
    expect(sound.completions, 1);
    expect(container.read(lastPracticeScoreProvider), 1.0);
  });

  /// 从候选格中找一个不在 [exclude] 字集内的干扰字并点选。
  /// 干扰字按构造必然不属于本句目标字（候选池 = 目标字 + 非目标干扰字）。
  Future<void> pickDistractor(
    WidgetTester tester,
    Set<String> exclude,
  ) async {
    final tiles = find.ancestor(
      of: find.byType(Text),
      matching: find.byType(InkWell),
    );
    for (var i = 0; i < tiles.evaluate().length; i++) {
      final one = tiles.at(i);
      final text = tester.widget<Text>(
        find.descendant(of: one, matching: find.byType(Text)),
      );
      final char = text.data;
      if (char != null &&
          char.characters.length == 1 &&
          !exclude.contains(char)) {
        await tester.tap(one);
        await tester.pump(const Duration(milliseconds: 50));
        return;
      }
    }
    fail('没有找到干扰字候选格');
  }

  testWidgets('拼错一句：得分 50%，pop quizFailed 且侧信道 0.5', (tester) async {
    final container = await pumpPage(tester);

    // 第 1 句故意拼错：首字点一个干扰字（必然不属于「床前明月光」），
    // 其余 4 字接正确的目标字，凑满 5 格触发判定。
    await pickDistractor(tester, {'床', '前', '明', '月', '光'});
    await pickChars(tester, '前明月光');
    await tester.pump(const Duration(milliseconds: 950));
    // 第 2 句拼对
    await pickChars(tester, '疑是地上霜');
    await tester.pump(const Duration(milliseconds: 950));

    expect(find.text('再听一遍，会更好！'), findsOneWidget);
    expect(sound.completions, 1);
    // 错句展示原文
    expect(find.textContaining('床前明月光'), findsWidgets);

    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(lastPracticeScoreProvider), 0.5);
  });

  testWidgets('打字模式：输入整句判定通过', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('打字'));
    await tester.pump();

    await tester.enterText(
      find.byType(TextField),
      '床前明月光，',
    );
    await tester.tap(find.text('确认本句'));
    await tester.pump(const Duration(milliseconds: 950));

    // 第 1 句已判定进入第 2 句（进度 1/2）
    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('退出页面调用 TTS 停播', (tester) async {
    await pumpPage(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    verify(() => tts.stop()).called(greaterThanOrEqualTo(1));
    expect(sound.completions, 0);
  });
}
