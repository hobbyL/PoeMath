// test/data/repositories/math_session_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/repositories/math_session_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  late MathSessionRepository repo;

  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
    repo = MathSessionRepository();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  MathSession makeSession({
    required String id,
    int grade = 1,
    int totalProblems = 10,
    int correctCount = 8,
  }) {
    return MathSession(
      id: id,
      profileId: ProfileScope.currentId,
      grade: grade,
      problemType: 'arithmetic',
      totalProblems: totalProblems,
      correctCount: correctCount,
    );
  }

  group('MathSessionRepository', () {
    test('getById 无记录返回 null', () {
      expect(repo.getById('s1'), isNull);
    });

    test('save 和 getById 正常工作', () async {
      await repo.save(makeSession(id: 's1'));
      final s = repo.getById('s1');
      expect(s, isNotNull);
      expect(s!.totalProblems, 10);
    });

    test('getAll 只返回当前 profile 的会话', () async {
      await repo.save(makeSession(id: 's1'));

      ProfileScope.switchTo('kid2');
      final kid2Repo = MathSessionRepository();
      await kid2Repo.save(MathSession(
        id: 's2',
        profileId: 'kid2',
        grade: 1,
        problemType: 'arithmetic',
        totalProblems: 5,
      ),);

      ProfileScope.reset();
      expect(repo.getAll().length, 1);
    });

    test('getRecent 返回最近 N 次会话', () async {
      for (var i = 0; i < 15; i++) {
        await repo.save(makeSession(id: 's_$i'));
      }

      expect(repo.getRecent(limit: 5).length, 5);
      expect(repo.getRecent().length, 10); // 默认 10
    });

    test('byGrade 按年级筛选', () async {
      await repo.save(makeSession(id: 's1', grade: 1));
      await repo.save(makeSession(id: 's2', grade: 2));
      await repo.save(makeSession(id: 's3', grade: 1));

      expect(repo.byGrade(1).length, 2);
      expect(repo.byGrade(2).length, 1);
    });

    test('totalProblems 统计总做题数', () async {
      await repo.save(makeSession(id: 's1', totalProblems: 10));
      await repo.save(makeSession(id: 's2', totalProblems: 20));

      expect(repo.totalProblems, 30);
    });

    test('totalCorrect 统计总正确数', () async {
      await repo.save(makeSession(id: 's1', correctCount: 8));
      await repo.save(makeSession(id: 's2', correctCount: 15));

      expect(repo.totalCorrect, 23);
    });

    test('overallAccuracy 计算正确率', () async {
      await repo.save(makeSession(
          id: 's1', totalProblems: 10, correctCount: 8,),);
      await repo.save(makeSession(
          id: 's2', totalProblems: 10, correctCount: 6,),);

      // 14/20 = 0.7
      expect(repo.overallAccuracy, closeTo(0.7, 0.001));
    });

    test('overallAccuracy 无数据返回 0', () {
      expect(repo.overallAccuracy, 0.0);
    });
  });
}
