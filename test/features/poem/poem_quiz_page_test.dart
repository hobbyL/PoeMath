import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/achievement.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/repositories/achievement_repository.dart';
import 'package:poemath/data/repositories/check_in_repository.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/data/repositories/user_stats_repository.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/poem/poem_quiz_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';
import 'package:poemath/features/poem/quiz/quiz_models.dart';

import '../../helpers/hive_test_helper.dart';

class _BlockingPoemProgressRepository extends PoemProgressRepository {
  final _pending = Completer<PoemProgress>();
  var recordStudyCalls = 0;

  @override
  Future<PoemProgress> recordStudy(String poemId) {
    recordStudyCalls++;
    return _pending.future;
  }

  void release(PoemProgress progress) => _pending.complete(progress);
}

class _ImmediateStatsRepository extends UserStatsRepository {
  @override
  UserStats get() => UserStats(profileId: 'test');

  @override
  Future<void> updatePoemStats({int? learned, int? mastered}) async {}
}

class _ImmediateCheckInRepository extends CheckInRepository {
  @override
  Future<void> updateToday({
    int? addPoems,
    int? addMathTotal,
    int? addMathCorrect,
    int? addStars,
    int? addDuration,
  }) async {}
}

class _AlreadyUnlockedAchievementRepository extends AchievementRepository {
  @override
  Achievement? getById(String id) {
    return Achievement(
      id: id,
      profileId: 'test',
      title: id,
      isUnlocked: true,
    );
  }

  @override
  int get unlockedCount => 0;
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('最后一题结算期间避免重复写入', (tester) async {
    final poem = Poem(
      id: 'quiz_guard',
      title: '测试诗',
      author: '测试作者',
      dynasty: '唐',
      content: '第一句长长',
      pinyin: '',
      layer: 'core',
      grade: 1,
    );
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('sound_enabled', false);
      await HiveBoxes.settings.put('haptic_enabled', false);
    });
    final progressRepo = _BlockingPoemProgressRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          poemByIdProvider('quiz_guard').overrideWith((ref) => poem),
          poemProgressRepoProvider.overrideWith((ref) => progressRepo),
          checkInRepoProvider.overrideWith(
            (ref) => _ImmediateCheckInRepository(),
          ),
          userStatsRepoProvider.overrideWith(
            (ref) => _ImmediateStatsRepository(),
          ),
          achievementRepoProvider.overrideWith(
            (ref) => _AlreadyUnlockedAchievementRepository(),
          ),
        ],
        child: const MaterialApp(
          home: PoemQuizPage(
            poemId: 'quiz_guard',
            quizType: QuizType.chooseDynasty,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    // 朝1 是引擎保证存在的错误干扰项，不触发撒花动画。
    expect(find.text('朝1'), findsOneWidget);
    await tester.tap(find.text('朝1'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    final resultButton = find.text('查看结果');
    expect(resultButton, findsOneWidget);

    // 两次点击之间不重建 UI，模拟用户快速重复点击。
    await tester.tap(resultButton);
    await tester.tap(resultButton);
    expect(progressRepo.recordStudyCalls, 1);

    progressRepo.release(
      PoemProgress(
        poemId: poem.id,
        profileId: 'test',
        status: LearningStatus.learning,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
