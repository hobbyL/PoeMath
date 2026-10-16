import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/models/review_schedule.dart';
import 'package:poemath/data/poem_identity.dart';
import 'package:poemath/data/repositories/learning_activity_repository.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/data/repositories/review_repository.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/domain/poem_practice_details.dart';
import 'package:poemath/domain/poem_review_history.dart';
import '../../helpers/hive_test_helper.dart';

class _FailingReviewRepository extends ReviewRepository {
  @override
  Future<void> save(ReviewSchedule schedule) =>
      Future.error(StateError('disk'));
}

void main() {
  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
  });
  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForTesting();
  });
  const wrong = PoemLineResult(
    lineIndex: 1,
    lineText: '疑是地上霜。',
    expected: '疑是地上霜',
    answer: '疑似地上霜',
    passed: false,
  );
  const corrected = PoemLineResult(
    lineIndex: 1,
    lineText: '疑是地上霜。',
    expected: '疑是地上霜',
    answer: '疑是地上霜',
    passed: true,
  );

  test('错句快照真实落盘、别名归一；填空答对不清错，完整听写清错', () async {
    final repo = LearningActivityRepository();
    Future<void> record(String id, PoemPracticeDetails details, int day) async {
      await repo.record(
        id: id,
        activityType: LearningActivityType.poemDictation,
        totalItems: 1,
        successfulItems: details.lines.single.passed ? 1 : 0,
        starsEarned: 0,
        durationSeconds: 1,
        completedAt: DateTime(2026, 10, day),
        poemId: 'poem_exp_661',
        detailsJson: details.encode(),
      );
    }

    await record(
      'a',
      const PoemPracticeDetails(mode: 'dictation', lines: [wrong]),
      1,
    );
    await record(
      'b',
      const PoemPracticeDetails(mode: 'quiz', lines: [corrected]),
      2,
    );
    await HiveBoxes.close();
    await HiveBoxes.init();
    expect(repo.forPoem('poem_core_004').length, 2);
    expect(repo.unresolvedLines('poem_core_004').single.answer, '疑似地上霜');
    await record(
      'c',
      const PoemPracticeDetails(
        mode: 'dictation',
        targeted: true,
        lines: [corrected],
      ),
      3,
    );
    expect(repo.unresolvedLines('poem_exp_661'), isEmpty);
    ProfileScope.switchTo('other');
    expect(repo.forPoem('poem_core_004'), isEmpty);
  });

  test('五轮真实完成历史、重开幂等、跨周期累计，失败不计通过', () async {
    final repo = ReviewRepository();
    await repo.createSchedule('p');
    await repo.completeReview(
      'p',
      score: 0.79,
      activityId: 'failed',
      reviewedAt: DateTime(2026, 10, 1),
    );
    expect(repo.completedReviewCount('p'), 0);
    for (var i = 0; i < 5; i++) {
      await repo.completeReview(
        'p',
        score: 0.8,
        activityId: 'pass$i',
        reviewedAt: DateTime(2026, 10, i + 2),
      );
      await repo.completeReview(
        'p',
        score: 0.8,
        activityId: 'pass$i',
        reviewedAt: DateTime(2026, 10, i + 2),
      );
    }
    expect(repo.get('p')!.isCompleted, isTrue);
    expect(repo.completedReviewCount('p'), 5);
    await repo.restartSchedule(
      'p',
      operationId: 'new',
      startedAt: DateTime(2026, 10, 10),
    );
    await repo.restartSchedule(
      'p',
      operationId: 'new',
      startedAt: DateTime(2026, 10, 10),
    );
    expect(repo.get('p')!.currentRound, 0);
    expect(repo.get('p')!.isCompleted, isFalse);
    expect(
      PoemReviewHistory.decode(repo.get('p')!.historyJson)!.cycles.length,
      1,
    );
    await repo.completeReview(
      'p',
      activityId: 'next',
      reviewedAt: DateTime(2026, 10, 11),
    );
    await HiveBoxes.close();
    await HiveBoxes.init();
    expect(repo.completedReviewCount('p'), 6);
    expect(
      repo
          .completedReviewsBetween(
            DateTime(2026, 10, 2),
            DateTime(2026, 10, 6),
          )
          .length,
      4,
    );
    expect(
      repo
          .completedReviewsBetween(
            DateTime(2026, 10, 11),
            DateTime(2026, 10, 12),
          )
          .single
          .cycleId,
      'new',
    );
    ProfileScope.switchTo('other');
    expect(
      repo.completedReviewsBetween(DateTime(2026), DateTime(2027)),
      isEmpty,
    );
  });

  test('复习保存失败不污染旧轮数，旧已完成记录不伪造完成事件', () async {
    final repo = ReviewRepository();
    await repo.createSchedule('p');
    await expectLater(
      _FailingReviewRepository().completeReview('p'),
      throwsStateError,
    );
    expect(repo.get('p')!.currentRound, 0);
    await repo.save(
      ReviewSchedule(
        poemId: 'old',
        profileId: 'default',
        currentRound: 5,
        nextReviewDate: DateTime(2026),
        isCompleted: true,
        lastReviewedAt: DateTime(2026),
      ),
    );
    expect(repo.completedReviewCount('old'), 0);
    await repo.restartSchedule('old', operationId: 'new-old');
    expect(
      PoemReviewHistory.decode(repo.get('old')!.historyJson)!
          .cycles
          .single['isCompleted'],
      true,
    );
    expect(repo.completedReviewCount('old'), 0);
  });

  test('别名合并保留新周期，不被旧完成状态覆盖，逐次事件仍保留', () async {
    final repo = ReviewRepository();
    await repo.save(
      ReviewSchedule(
        poemId: 'poem_core_004',
        profileId: 'default',
        currentRound: 5,
        isCompleted: true,
        nextReviewDate: DateTime(2026),
      ),
    );
    await repo.restartSchedule(
      'poem_core_004',
      operationId: 'new',
      startedAt: DateTime(2026, 10, 1),
    );
    final rows = PoemIdentity.merge('review', [
      PoemIdentity.reviewMap(repo.get('poem_core_004')!),
      {
        'poemId': 'poem_exp_661',
        'profileId': 'default',
        'currentRound': 5,
        'isCompleted': true,
        'nextReviewDate': DateTime(2027).toIso8601String(),
      }
    ]);
    final merged = PoemIdentity.review(rows.single);
    expect(merged.isCompleted, false);
    expect(merged.currentRound, 0);
    expect(PoemReviewHistory.decode(merged.historyJson)!.cycleId, 'new');
  });

  test('首次掌握记录时间并落盘；旧已掌握未知时间不回填', () async {
    final repo = PoemProgressRepository();
    await repo.recordStudy('p');
    await repo.save(repo.get('p')!.copyWith(status: LearningStatus.mastered));
    final first = repo.get('p')!.firstMasteredAt;
    expect(first, isNotNull);
    await repo.save(repo.get('p')!.copyWith());
    await HiveBoxes.poemProgress.put(
      'default_old',
      PoemProgress(
        poemId: 'old',
        profileId: 'default',
        status: LearningStatus.mastered,
      ),
    );
    await repo.save(repo.get('old')!.copyWith());
    await HiveBoxes.close();
    await HiveBoxes.init();
    expect(
      repo.get('p')!.firstMasteredAt!.millisecondsSinceEpoch,
      first!.millisecondsSinceEpoch,
    );
    expect(repo.get('old')!.firstMasteredAt, isNull);
  });
}
