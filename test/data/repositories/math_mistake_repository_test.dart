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

    test('recordRepracticeResult 答错只增加一次重练次数且不入巩固队列', () async {
      await repo.add(makeMistake(id: 'm1'));
      final outcome =
          await repo.recordRepracticeResult('m1', isCorrect: false);

      expect(outcome, RepracticeOutcome.reset);
      final m = repo.getById('m1')!;
      expect(m.retryCount, 1);
      expect(m.isResolved, isFalse);
      expect(m.consolidationRound, 0);
      expect(m.nextConsolidationDate, isNull);
    });

    test('recordRepracticeResult 首次答对进入巩固队列而非直接掌握', () async {
      await repo.add(makeMistake(id: 'm1'));
      final outcome = await repo.recordRepracticeResult('m1', isCorrect: true);

      expect(outcome, RepracticeOutcome.enteredConsolidation);
      final m = repo.getById('m1')!;
      expect(m.retryCount, 1);
      // 关键语义变更：答对一次不再立即出列，先进入 1 天后的抽查。
      expect(m.isResolved, isFalse);
      expect(m.consolidationRound, 1);
      expect(m.isConsolidating, isTrue);
      expect(
        m.nextConsolidationDate,
        _today().add(const Duration(days: 1)),
      );
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
      await repo.add(
        MathMistake(
          id: 'm_old',
          profileId: ProfileScope.currentId,
          problemText: '1 + 1 = ?',
          correctAnswer: '2',
          userAnswer: '3',
          problemType: 'arithmetic',
          grade: 1,
          createdAt: DateTime(2026, 1, 1),
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

  group('巩固状态机（1/3/7 天三关）', () {
    /// 连续答对 n 次，返回最后一次的 outcome。
    Future<RepracticeOutcome?> passTimes(String id, int n) async {
      RepracticeOutcome? outcome;
      for (var i = 0; i < n; i++) {
        outcome = await repo.recordRepracticeResult(id, isCorrect: true);
      }
      return outcome;
    }

    test('三关依次顺延 1 → 3 → 7 天', () async {
      await repo.add(makeMistake(id: 'm1'));

      await passTimes('m1', 1);
      var m = repo.getById('m1')!;
      expect(m.consolidationRound, 1);
      expect(m.nextConsolidationDate, _today().add(const Duration(days: 1)));

      expect(
        await repo.recordRepracticeResult('m1', isCorrect: true),
        RepracticeOutcome.advanced,
      );
      m = repo.getById('m1')!;
      expect(m.consolidationRound, 2);
      expect(m.nextConsolidationDate, _today().add(const Duration(days: 3)));

      expect(
        await repo.recordRepracticeResult('m1', isCorrect: true),
        RepracticeOutcome.advanced,
      );
      m = repo.getById('m1')!;
      expect(m.consolidationRound, 3);
      expect(m.nextConsolidationDate, _today().add(const Duration(days: 7)));
      expect(m.isResolved, isFalse);
    });

    test('三关全过后出列标记已掌握', () async {
      await repo.add(makeMistake(id: 'm1'));
      final outcome = await passTimes('m1', 4);

      expect(outcome, RepracticeOutcome.mastered);
      final m = repo.getById('m1')!;
      expect(m.isResolved, isTrue);
      expect(m.isConsolidating, isFalse);
      expect(m.nextConsolidationDate, isNull);
      expect(m.retryCount, 4);
    });

    test('任一关答错即打回未掌握并清零轮次', () async {
      await repo.add(makeMistake(id: 'm1'));
      await passTimes('m1', 3);
      expect(repo.getById('m1')!.consolidationRound, 3);

      final outcome =
          await repo.recordRepracticeResult('m1', isCorrect: false);

      expect(outcome, RepracticeOutcome.reset);
      final m = repo.getById('m1')!;
      expect(m.consolidationRound, 0);
      expect(m.isUnmastered, isTrue);
      expect(m.nextConsolidationDate, isNull);
    });

    test('已掌握后答错重新回到未掌握', () async {
      await repo.add(makeMistake(id: 'm1'));
      await passTimes('m1', 4);
      expect(repo.getById('m1')!.isResolved, isTrue);

      await repo.recordRepracticeResult('m1', isCorrect: false);

      final m = repo.getById('m1')!;
      expect(m.isResolved, isFalse);
      expect(m.isUnmastered, isTrue);
    });

    test('手动 resolve 跳过巩固直接出列并清零轮次', () async {
      await repo.add(makeMistake(id: 'm1'));
      await passTimes('m1', 2);
      expect(repo.getById('m1')!.consolidationRound, 2);

      await repo.resolve('m1');

      final m = repo.getById('m1')!;
      expect(m.isResolved, isTrue);
      expect(m.consolidationRound, 0);
      expect(m.nextConsolidationDate, isNull);
      // 手动出列不计重练次数
      expect(m.retryCount, 2);
    });

    test('记录不存在时返回 null', () async {
      expect(
        await repo.recordRepracticeResult('missing', isCorrect: true),
        isNull,
      );
    });

    test('getUnresolved 含未掌握与待巩固两组', () async {
      await repo.add(makeMistake(id: 'm_unmastered'));
      await repo.add(makeMistake(id: 'm_consolidating'));
      await repo.add(makeMistake(id: 'm_mastered'));
      await passTimes('m_consolidating', 1);
      await passTimes('m_mastered', 4);

      final unresolved = repo.getUnresolved().map((m) => m.id).toSet();
      expect(unresolved, {'m_unmastered', 'm_consolidating'});
    });

    test('getDueConsolidation 只返回到期的待巩固题', () async {
      // 到期：抽查日为昨天
      await repo.add(makeMistake(id: 'm_due'));
      await passTimes('m_due', 1);
      final due = repo.getById('m_due')!;
      due.nextConsolidationDate =
          _today().subtract(const Duration(days: 1));
      await due.save();

      // 未到期：抽查日为 1 天后
      await repo.add(makeMistake(id: 'm_pending'));
      await passTimes('m_pending', 1);

      // 未掌握题不进抽查队列
      await repo.add(makeMistake(id: 'm_unmastered'));

      expect(repo.getDueConsolidation().map((m) => m.id), ['m_due']);
    });

    test('抽查日为今天即算到期', () async {
      await repo.add(makeMistake(id: 'm1'));
      await passTimes('m1', 1);
      final m = repo.getById('m1')!;
      m.nextConsolidationDate = _today();
      await m.save();

      expect(m.isConsolidationDue, isTrue);
    });
  });
}

/// 当天零点（与仓储内 nextConsolidationDate 的构造口径一致）。
DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}
