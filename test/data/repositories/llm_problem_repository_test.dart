// test/data/repositories/llm_problem_repository_test.dart
//
// LLM 应用题仓储测试：CRUD、Profile 隔离、批次、过滤、作答记录与统计。

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/data/repositories/llm_problem_repository.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';

LlmProblem _problem({
  required String id,
  String profileId = 'default',
  String batchId = 'batch-1',
  String topic = 'addition',
  int grade = 3,
  String semester = '上',
  DateTime? createdAt,
}) =>
    LlmProblem(
      id: id,
      profileId: profileId,
      questionText: '小明有12支铅笔，妈妈又买了4支，现在有多少支铅笔？',
      unit: '支',
      operands: const [12, 4],
      operators: const ['+'],
      answer: 16,
      explanation: '12加4等于16。',
      batchId: batchId,
      createdAt: createdAt ?? DateTime(2026, 10, 1),
      grade: grade,
      semester: semester,
      topic: topic,
      difficulty: 1,
    );

void main() {
  late LlmProblemRepository repository;

  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
    lockParentForTesting();
    repository = LlmProblemRepository();
  });

  tearDown(() async {
    lockParentForTesting();
    ProfileScope.reset();
    await tearDownHiveForTesting();
  });

  test('addAll 入库后 getAll 按创建时间倒序', () async {
    await repository.addAll([
      _problem(id: 'p1', createdAt: DateTime(2026, 10, 1)),
      _problem(id: 'p2', createdAt: DateTime(2026, 10, 3)),
      _problem(id: 'p3', createdAt: DateTime(2026, 10, 2)),
    ]);

    final all = repository.getAll();
    expect(all.map((p) => p.id), ['p2', 'p3', 'p1']);
  });

  test('getById 命中与未命中', () async {
    await repository.addAll([_problem(id: 'p1')]);

    expect(repository.getById('p1')?.answer, 16);
    expect(repository.getById('missing'), isNull);
  });

  test('byBatch 只返回指定批次', () async {
    await repository.addAll([
      _problem(id: 'p1', batchId: 'batch-1'),
      _problem(id: 'p2', batchId: 'batch-2'),
      _problem(id: 'p3', batchId: 'batch-1'),
    ]);

    final batch = repository.byBatch('batch-1');
    expect(batch.map((p) => p.id).toSet(), {'p1', 'p3'});
  });

  test('filter 按 topic/grade/semester/done 过滤', () async {
    await repository.addAll([
      _problem(id: 'p1', topic: 'addition', grade: 3),
      _problem(id: 'p2', topic: 'subtraction', grade: 4, semester: '下'),
      _problem(id: 'p3', topic: 'addition', grade: 3),
    ]);

    expect(repository.filter(topic: 'addition'), hasLength(2));
    expect(repository.filter(grade: 4), hasLength(1));
    expect(repository.filter(semester: '下'), hasLength(1));
    expect(repository.filter(done: false), hasLength(3));
    expect(repository.filter(done: true), isEmpty);
    expect(repository.filter(topic: 'addition', grade: 3), hasLength(2));
  });

  test('recordAttempt 累计做题/答对次数并标记完成', () async {
    await repository.addAll([_problem(id: 'p1')]);

    await repository.recordAttempt('p1', correct: true);
    await repository.recordAttempt('p1', correct: false);

    final problem = repository.getById('p1')!;
    expect(problem.attempts, 2);
    expect(problem.correctCount, 1);
    expect(problem.done, isTrue);
    expect(problem.lastDoneAt, isNotNull);
  });

  test('recordAttempt 对不存在的 ID 静默跳过', () async {
    await repository.recordAttempt('missing', correct: true);
    expect(repository.getAll(), isEmpty);
  });

  test('stats 汇总题库统计', () async {
    await repository.addAll([_problem(id: 'p1'), _problem(id: 'p2')]);
    await repository.recordAttempt('p1', correct: true);
    await repository.recordAttempt('p1', correct: true);
    await repository.recordAttempt('p2', correct: false);

    final stats = repository.stats();
    expect(stats.total, 2);
    expect(stats.done, 2);
    expect(stats.attempts, 3);
    expect(stats.correctCount, 2);
    expect(stats.accuracy, closeTo(2 / 3, 0.001));
  });

  test('delete / deleteBatch / clearAll', () async {
    await unlockParentForTesting();
    await repository.addAll([
      _problem(id: 'p1', batchId: 'b1'),
      _problem(id: 'p2', batchId: 'b1'),
      _problem(id: 'p3', batchId: 'b2'),
    ]);

    await repository.delete('p1');
    expect(repository.getById('p1'), isNull);
    expect(repository.getAll(), hasLength(2));

    await repository.deleteBatch('b1');
    expect(repository.byBatch('b1'), isEmpty);
    expect(repository.getAll(), hasLength(1));

    await repository.clearAll();
    expect(repository.getAll(), isEmpty);
  });

  test('未设置和锁定时拒绝所有删除，仍可正常作答', () async {
    await repository.addAll([
      _problem(id: 'p1'),
      _problem(id: 'p2'),
    ]);
    final actions = <Future<void> Function()>[
      () => repository.delete('p1'),
      () => repository.deleteBatch('batch-1'),
      () => repository.clearAll(),
    ];
    for (final action in actions) {
      await expectLater(action(), throwsA(isA<ParentAccessDenied>()));
    }
    await unlockParentForTesting();
    lockParentForTesting();
    for (final action in actions) {
      await expectLater(action(), throwsA(isA<ParentAccessDenied>()));
    }
    expect(repository.getAll(), hasLength(2));
    await repository.recordAttempt('p1', correct: true);
    expect(repository.getById('p1')!.attempts, 1);
  });

  for (final clearAll in [false, true]) {
    test('${clearAll ? '清空' : '批次删除'}在每题删除前复验，锁定后停止', () async {
      await unlockParentForTesting();
      await repository.addAll([
        _problem(id: 'p1'),
        _problem(id: 'p2'),
        _problem(id: 'p3'),
      ]);
      void authorize() {
        if (repository.getAll().length < 3) lockParentForTesting();
      }

      await expectLater(
        clearAll
            ? repository.clearAll(authorize: authorize)
            : repository.deleteBatch('batch-1', authorize: authorize),
        throwsA(isA<ParentAccessDenied>()),
      );
      expect(repository.getAll(), hasLength(2));
    });

    test('${clearAll ? '清空' : '批次删除'}等待期间切换档案，不删除新档案同 ID 题目', () async {
      await unlockParentForTesting();
      await repository.addAll([_problem(id: 'p1'), _problem(id: 'p2')]);
      ProfileScope.switchTo('other');
      await repository.addAll([
        _problem(id: 'p1', profileId: 'other'),
        _problem(id: 'p2', profileId: 'other'),
      ]);
      ProfileScope.reset();
      void authorize() {
        if (repository.getAll().length < 2) ProfileScope.switchTo('other');
      }

      await expectLater(
        clearAll
            ? repository.clearAll(authorize: authorize)
            : repository.deleteBatch('batch-1', authorize: authorize),
        throwsA(isA<ParentAccessDenied>()),
      );
      expect(ProfileScope.currentId, 'other');
      expect(repository.getAll(), hasLength(2));
      ProfileScope.reset();
      expect(repository.getAll(), hasLength(1));
    });
  }

  test('实际删除前执行调用方授权检查', () async {
    await unlockParentForTesting();
    await repository.addAll([_problem(id: 'p1')]);
    await expectLater(
      repository.delete(
        'p1',
        authorize: () => throw const ParentAccessDenied(),
      ),
      throwsA(isA<ParentAccessDenied>()),
    );
    expect(repository.getById('p1'), isNotNull);
  });

  test('expressionText 组装算式文本', () async {
    await repository.addAll([_problem(id: 'p1')]);
    expect(repository.getById('p1')!.expressionText, '12 + 4');
  });
}
