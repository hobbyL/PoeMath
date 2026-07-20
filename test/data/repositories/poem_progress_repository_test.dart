// test/data/repositories/poem_progress_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  late PoemProgressRepository repo;

  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
    repo = PoemProgressRepository();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  group('PoemProgressRepository', () {
    test('get 无记录返回 null', () {
      expect(repo.get('poem_001'), isNull);
    });

    test('save 和 get 正常工作', () async {
      final progress = PoemProgress(
        poemId: 'poem_001',
        profileId: ProfileScope.currentId,
        status: LearningStatus.learning,
        studyCount: 3,
      );
      await repo.save(progress);

      final loaded = repo.get('poem_001');
      expect(loaded, isNotNull);
      expect(loaded!.poemId, 'poem_001');
      expect(loaded.status, LearningStatus.learning);
      expect(loaded.studyCount, 3);
    });

    test('getAll 只返回当前 profile 的数据', () async {
      // 默认 profile
      await repo.save(PoemProgress(
        poemId: 'poem_001',
        profileId: 'default',
        status: LearningStatus.learning,
      ),);

      // 另一个 profile
      ProfileScope.switchTo('kid2');
      await repo.save(PoemProgress(
        poemId: 'poem_002',
        profileId: 'kid2',
        status: LearningStatus.mastered,
      ),);

      // 切回 default
      ProfileScope.reset();
      final all = repo.getAll();
      expect(all.length, 1);
      expect(all.first.poemId, 'poem_001');
    });

    test('byStatus 按学习状态筛选', () async {
      await repo.save(PoemProgress(
        poemId: 'p1',
        profileId: ProfileScope.currentId,
        status: LearningStatus.learning,
      ),);
      await repo.save(PoemProgress(
        poemId: 'p2',
        profileId: ProfileScope.currentId,
        status: LearningStatus.mastered,
      ),);
      await repo.save(PoemProgress(
        poemId: 'p3',
        profileId: ProfileScope.currentId,
        status: LearningStatus.learning,
      ),);

      expect(repo.byStatus(LearningStatus.learning).length, 2);
      expect(repo.byStatus(LearningStatus.mastered).length, 1);
      expect(repo.byStatus(LearningStatus.notStarted).length, 0);
    });

    test('learnedCount 排除 notStarted', () async {
      await repo.save(PoemProgress(
        poemId: 'p1',
        profileId: ProfileScope.currentId,
        status: LearningStatus.notStarted,
      ),);
      await repo.save(PoemProgress(
        poemId: 'p2',
        profileId: ProfileScope.currentId,
        status: LearningStatus.learning,
      ),);
      await repo.save(PoemProgress(
        poemId: 'p3',
        profileId: ProfileScope.currentId,
        status: LearningStatus.mastered,
      ),);

      expect(repo.learnedCount, 2);
    });

    test('masteredCount 只统计 mastered', () async {
      await repo.save(PoemProgress(
        poemId: 'p1',
        profileId: ProfileScope.currentId,
        status: LearningStatus.learning,
      ),);
      await repo.save(PoemProgress(
        poemId: 'p2',
        profileId: ProfileScope.currentId,
        status: LearningStatus.mastered,
      ),);

      expect(repo.masteredCount, 1);
    });

    test('recordStudy 首次学习创建新记录', () async {
      final progress = await repo.recordStudy('poem_new');
      expect(progress.poemId, 'poem_new');
      expect(progress.status, LearningStatus.learning);
      expect(progress.studyCount, 1);
      expect(progress.lastStudiedAt, isNotNull);
      expect(progress.firstStudiedAt, isNotNull);
    });

    test('recordStudy 再次学习增加计数', () async {
      await repo.recordStudy('poem_x');
      final progress = await repo.recordStudy('poem_x');
      expect(progress.studyCount, 2);
    });

    test('recordStudy 不改变非 notStarted 的状态', () async {
      await repo.save(PoemProgress(
        poemId: 'poem_r',
        profileId: ProfileScope.currentId,
        status: LearningStatus.reviewing,
      ),);
      final progress = await repo.recordStudy('poem_r');
      expect(progress.status, LearningStatus.reviewing);
    });

    test('recordRecitation 记录完成模式对应的掌握等级', () async {
      final progress = await repo.recordRecitation('poem_recite', level: 3);

      expect(progress.status, LearningStatus.learning);
      expect(progress.studyCount, 1);
      expect(progress.masteryLevel, 3);
      expect(repo.get('poem_recite')!.masteryLevel, 3);
    });

    test('recordRecitation 重练较低等级时不降低历史最高等级', () async {
      await repo.recordRecitation('poem_recite', level: 4);
      final progress = await repo.recordRecitation('poem_recite', level: 2);

      expect(progress.studyCount, 2);
      expect(progress.masteryLevel, 4);
    });

    test('recordRecitation 不覆盖测试通过等级 5', () async {
      await repo.save(PoemProgress(
        poemId: 'poem_quiz_passed',
        profileId: ProfileScope.currentId,
        status: LearningStatus.reviewing,
        masteryLevel: 5,
      ),);

      final progress = await repo.recordRecitation(
        'poem_quiz_passed',
        level: 4,
      );

      expect(progress.status, LearningStatus.reviewing);
      expect(progress.masteryLevel, 5);
    });

    test('recordRecitation 拒绝 1-4 之外的等级', () async {
      expect(
        () => repo.recordRecitation('poem_invalid', level: 0),
        throwsRangeError,
      );
      expect(
        () => repo.recordRecitation('poem_invalid', level: 5),
        throwsRangeError,
      );
    });

    test('delete 删除指定进度', () async {
      await repo.save(PoemProgress(
        poemId: 'poem_del',
        profileId: ProfileScope.currentId,
      ),);
      expect(repo.get('poem_del'), isNotNull);

      await repo.delete('poem_del');
      expect(repo.get('poem_del'), isNull);
    });
  });
}
