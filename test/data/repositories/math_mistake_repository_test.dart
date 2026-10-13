// test/data/repositories/math_mistake_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  late MathMistakeRepository repo;

  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
    repo = MathMistakeRepository();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  MathMistake makeMistake({
    required String id,
    String problemType = 'arithmetic',
    int grade = 1,
    bool isResolved = false,
  }) {
    return MathMistake(
      id: id,
      profileId: ProfileScope.currentId,
      problemText: '1 + 1 = ?',
      correctAnswer: '2',
      userAnswer: '3',
      problemType: problemType,
      grade: grade,
      isResolved: isResolved,
    );
  }

  group('MathMistakeRepository', () {
    test('getById 无记录返回 null', () {
      expect(repo.getById('m1'), isNull);
    });

    test('add 和 getById 正常工作', () async {
      await repo.add(makeMistake(id: 'm1'));
      final m = repo.getById('m1');
      expect(m, isNotNull);
      expect(m!.correctAnswer, '2');
    });

    test('getAll 只返回当前 profile 的错题', () async {
      await repo.add(makeMistake(id: 'm1'));

      ProfileScope.switchTo('kid2');
      final kid2Repo = MathMistakeRepository();
      await kid2Repo.add(MathMistake(
        id: 'm2',
        profileId: 'kid2',
        problemText: '2 + 2 = ?',
        correctAnswer: '4',
        userAnswer: '5',
        problemType: 'arithmetic',
        grade: 1,
      ),);

      ProfileScope.reset();
      expect(repo.getAll().length, 1);
      expect(repo.getAll().first.id, 'm1');
    });

    test('byType 按题型筛选', () async {
      await repo.add(makeMistake(id: 'm1', problemType: 'arithmetic'));
      await repo.add(makeMistake(id: 'm2', problemType: 'fraction'));
      await repo.add(makeMistake(id: 'm3', problemType: 'arithmetic'));

      expect(repo.byType('arithmetic').length, 2);
      expect(repo.byType('fraction').length, 1);
    });

    test('byGrade 按年级筛选', () async {
      await repo.add(makeMistake(id: 'm1', grade: 1));
      await repo.add(makeMistake(id: 'm2', grade: 2));

      expect(repo.byGrade(1).length, 1);
      expect(repo.byGrade(2).length, 1);
    });

    test('getUnresolved 返回未解决的错题', () async {
      await repo.add(makeMistake(id: 'm1'));
      await repo.add(makeMistake(id: 'm2', isResolved: true));

      expect(repo.getUnresolved().length, 1);
      expect(repo.getUnresolved().first.id, 'm1');
    });

    test('resolve 手动标记已解决但不增加重练次数', () async {
      await repo.add(makeMistake(id: 'm1'));
      await repo.resolve('m1');

      final m = repo.getById('m1')!;
      expect(m.isResolved, isTrue);
      expect(m.retryCount, 0);
    });

    test('recordRetryResult 答错只增加一次重练次数', () async {
      await repo.add(makeMistake(id: 'm1'));
      await repo.recordRetryResult('m1', isCorrect: false);

      final m = repo.getById('m1')!;
      expect(m.retryCount, 1);
      expect(m.isResolved, isFalse);
    });

    test('recordRetryResult 答对只增加一次并标记已解决', () async {
      await repo.add(makeMistake(id: 'm1'));
      await repo.recordRetryResult('m1', isCorrect: true);

      final m = repo.getById('m1')!;
      expect(m.retryCount, 1);
      expect(m.isResolved, isTrue);
    });

    test('totalCount 和 unresolvedCount', () async {
      await repo.add(makeMistake(id: 'm1'));
      await repo.add(makeMistake(id: 'm2', isResolved: true));

      expect(repo.totalCount, 2);
      expect(repo.unresolvedCount, 1);
    });

    test('delete 删除错题', () async {
      await repo.add(makeMistake(id: 'm1'));
      await repo.delete('m1');
      expect(repo.getById('m1'), isNull);
    });
  });

  group('problemKey 归一化', () {
    test('同题面同答案得同 key（含空白与减号差异）', () {
      final a = MathMistakeRepository.problemKey(
        problemText: '25 + 38 = ?',
        correctAnswer: '63',
      );
      final b = MathMistakeRepository.problemKey(
        problemText: '25  +\t38   = ?',
        correctAnswer: '63',
      );
      final c = MathMistakeRepository.problemKey(
        problemText: '25 − 38 = ?',
        correctAnswer: '-13',
      );
      final d = MathMistakeRepository.problemKey(
        problemText: '25 - 38 = ?',
        correctAnswer: '-13',
      );
      expect(a, equals(b));
      expect(c, equals(d));
      expect(a, isNot(equals(c)));
    });

    test('答案不同则 key 不同', () {
      final a = MathMistakeRepository.problemKey(
        problemText: '1 + 1 = ?',
        correctAnswer: '2',
      );
      final b = MathMistakeRepository.problemKey(
        problemText: '1 + 1 = ?',
        correctAnswer: '3',
      );
      expect(a, isNot(equals(b)));
    });

    test('key 带 m_ 前缀', () {
      final key = MathMistakeRepository.problemKey(
        problemText: '1 + 1 = ?',
        correctAnswer: '2',
      );
      expect(key.startsWith('m_'), isTrue);
    });
  });

  group('recordWrong 同题聚合', () {
    test('首次错题新建 wrongCount=1', () async {
      await repo.recordWrong(
        problemText: '3 × 5 = ?',
        correctAnswer: '15',
        userAnswer: '14',
        problemType: 'multiplication',
        grade: 2,
      );

      final list = repo.getAll();
      expect(list, hasLength(1));
      expect(list.first.wrongCount, 1);
      expect(list.first.lastWrongAt, isNotNull);
      expect(
        list.first.id,
        MathMistakeRepository.problemKey(
          problemText: '3 × 5 = ?',
          correctAnswer: '15',
        ),
      );
    });

    test('同题再错累加 wrongCount 并覆盖最近作答', () async {
      await repo.recordWrong(
        problemText: '3 × 5 = ?',
        correctAnswer: '15',
        userAnswer: '14',
        problemType: 'multiplication',
        grade: 2,
        errorType: 'multiplication_table',
      );
      await repo.recordWrong(
        problemText: '3 × 5 = ?',
        correctAnswer: '15',
        userAnswer: '16',
        problemType: 'multiplication',
        grade: 2,
      );

      expect(repo.getAll(), hasLength(1));
      final m = repo.getAll().first;
      expect(m.wrongCount, 2);
      expect(m.userAnswer, '16');
      expect(m.lastWrongAt!.isAfter(m.createdAt), isTrue);
    });

    test('跨 profile 同题不合并', () async {
      await repo.recordWrong(
        problemText: '3 × 5 = ?',
        correctAnswer: '15',
        userAnswer: '14',
        problemType: 'multiplication',
        grade: 2,
      );

      ProfileScope.switchTo('kid2');
      final kid2Repo = MathMistakeRepository();
      await kid2Repo.recordWrong(
        problemText: '3 × 5 = ?',
        correctAnswer: '15',
        userAnswer: '14',
        problemType: 'multiplication',
        grade: 2,
      );

      ProfileScope.reset();
      expect(repo.getAll(), hasLength(1));
      expect(repo.getAll().first.profileId, 'default');
      expect(repo.getAll().first.wrongCount, 1);
    });

    test('已掌握的题再次答错回到待复练', () async {
      await repo.recordWrong(
        problemText: '3 × 5 = ?',
        correctAnswer: '15',
        userAnswer: '14',
        problemType: 'multiplication',
        grade: 2,
      );
      final id = MathMistakeRepository.problemKey(
        problemText: '3 × 5 = ?',
        correctAnswer: '15',
      );
      await repo.resolve(id);
      expect(repo.getById(id)!.isResolved, isTrue);

      await repo.recordWrong(
        problemText: '3 × 5 = ?',
        correctAnswer: '15',
        userAnswer: '16',
        problemType: 'multiplication',
        grade: 2,
      );

      final m = repo.getById(id)!;
      expect(m.isResolved, isFalse);
      expect(m.wrongCount, 2);
    });

    test('getAll 按 lastWrongAt 倒序（最近答错在前）', () async {
      final old = DateTime(2026, 1, 1);
      await repo.add(
        MathMistake(
          id: 'm_old',
          profileId: ProfileScope.currentId,
          problemText: '1 + 1 = ?',
          correctAnswer: '2',
          userAnswer: '3',
          problemType: 'arithmetic',
          grade: 1,
          createdAt: old,
        ),
      );
      await repo.recordWrong(
        problemText: '9 − 1 = ?',
        correctAnswer: '8',
        userAnswer: '7',
        problemType: 'subtraction',
        grade: 1,
      );

      final list = repo.getAll();
      expect(list.first.problemText, '9 − 1 = ?');
      expect(list.last.id, 'm_old');
    });
  });
}
