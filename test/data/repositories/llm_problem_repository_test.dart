// test/data/repositories/llm_problem_repository_test.dart
//
// LLM 应用题仓储测试：CRUD、Profile 隔离、批次、过滤、作答记录与统计。

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/data/repositories/llm_problem_repository.dart';

import '../../helpers/hive_test_helper.dart';

LlmProblem _problem({
  required String id,
  String batchId = 'batch-1',
  String topic = 'addition',
  int grade = 3,
  String semester = '上',
  DateTime? createdAt,
}) =>
    LlmProblem(
      id: id,
      profileId: 'default',
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
    repository = LlmProblemRepository();
  });

  tearDown(() async {
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

  test('expressionText 组装算式文本', () async {
    await repository.addAll([_problem(id: 'p1')]);
    expect(repository.getById('p1')!.expressionText, '12 + 4');
  });
}
