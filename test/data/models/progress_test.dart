// test/data/models/progress_test.dart
//
// 单元测试：PoemProgress / ReviewSchedule 模型。

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/models/review_schedule.dart';

void main() {
  group('PoemProgress', () {
    test('默认值正确', () {
      final progress = PoemProgress(
        poemId: 'poem_001',
        profileId: 'default',
      );
      expect(progress.status, LearningStatus.notStarted);
      expect(progress.masteryLevel, 0);
      expect(progress.studyCount, 0);
      expect(progress.stars, 0);
    });

    test('LearningStatus 枚举索引正确', () {
      expect(LearningStatus.notStarted.index, 0);
      expect(LearningStatus.learning.index, 1);
      expect(LearningStatus.reviewing.index, 2);
      expect(LearningStatus.mastered.index, 3);
    });
  });

  group('ReviewSchedule', () {
    test('intervals 包含 5 轮', () {
      expect(ReviewSchedule.intervals, [1, 3, 7, 14, 30]);
      expect(ReviewSchedule.intervals.length, 5);
    });

    test('advanceToNextRound 推进复习轮次', () {
      final schedule = ReviewSchedule(
        poemId: 'poem_001',
        profileId: 'default',
        nextReviewDate: DateTime.now(),
      );

      expect(schedule.currentRound, 0);
      expect(schedule.isCompleted, false);

      schedule.advanceToNextRound();
      expect(schedule.currentRound, 1);
      expect(schedule.isCompleted, false);
      expect(schedule.lastReviewedAt, isNotNull);
    });

    test('5 轮后标记完成', () {
      final schedule = ReviewSchedule(
        poemId: 'poem_001',
        profileId: 'default',
        nextReviewDate: DateTime.now(),
      );

      for (int i = 0; i < 5; i++) {
        schedule.advanceToNextRound();
      }
      expect(schedule.currentRound, 5);
      expect(schedule.isCompleted, true);
    });
  });
}
