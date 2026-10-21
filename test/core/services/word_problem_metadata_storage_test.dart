import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/data/repositories/llm_problem_repository.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

import '../../helpers/hive_test_helper.dart';

/// 写出真实旧字段格式，确保新 adapter 的缺字段默认值可从磁盘读取。
class _LegacyProblemAdapter extends TypeAdapter<LlmProblem> {
  _LegacyProblemAdapter(this.fieldCount);
  final int fieldCount;
  @override
  int get typeId => 16;
  @override
  LlmProblem read(BinaryReader reader) => LlmProblemAdapter().read(reader);
  @override
  void write(BinaryWriter writer, LlmProblem obj) {
    final fields = <Object?>[
      obj.id,
      obj.profileId,
      obj.questionText,
      obj.unit,
      obj.operands,
      obj.operators,
      obj.answer,
      obj.explanation,
      obj.batchId,
      obj.createdAt,
      obj.grade,
      obj.semester,
      obj.topic,
      obj.difficulty,
      obj.done,
      obj.attempts,
      obj.correctCount,
      obj.lastDoneAt,
      obj.appliedActivityIds,
    ];
    writer.writeByte(fieldCount);
    for (var i = 0; i < fieldCount; i++) {
      writer.writeByte(i);
      writer.write(fields[i]);
    }
  }
}

LlmProblem problem({String id = 'p1', bool legacy = false}) {
  final plan = WordProblemPlanGenerator.withScene(
    const ProblemSkeleton(
      operands: [36, 4],
      operators: [Operator.divide],
      answer: 9,
      unitHint: '瓶',
      difficulty: 2,
    ),
    WordProblemRelation.equalShare,
    'water',
  );
  final rendered = WordProblemRenderer.render(plan);
  return LlmProblem(
    id: id,
    profileId: 'default',
    questionText: rendered.text,
    unit: '瓶',
    operands: [36, 4],
    operators: ['÷'],
    answer: 9,
    explanation: rendered.explanation,
    batchId: 'batch',
    createdAt: DateTime(2026, 10, 21),
    grade: 3,
    semester: '上',
    topic: 'division',
    difficulty: 2,
    generationMetadataJson: legacy
        ? ''
        : WordProblemMetadata(
            plan: plan,
            source: WordProblemSource.localTemplate,
          ).encode(),
  );
}

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  test('旧18及19字段Hive记录可读取，新增字段回落且原统计保留', () async {
    for (final fieldCount in [18, 19]) {
      await HiveBoxes.close();
      Hive.registerAdapter(_LegacyProblemAdapter(fieldCount), override: true);
      await HiveBoxes.init();
      final original = problem(legacy: true);
      original.attempts = 3;
      original.correctCount = 2;
      original.appliedActivityIds = ['old_activity'];
      await HiveBoxes.llmProblems.put('default_p1', original);
      await HiveBoxes.close();
      Hive.registerAdapter(LlmProblemAdapter(), override: true);
      await HiveBoxes.init();
      final restored = LlmProblemRepository().getById('p1')!;
      expect(restored.generationMetadataJson, '');
      expect(restored.attempts, 3);
      expect(restored.correctCount, 2);
      expect(restored.appliedActivityIds,
          fieldCount == 18 ? <String>[] : ['old_activity'],);
      expect(restored.questionText, original.questionText);
      expect(restored.answer, 9);
    }
  });

  test('未知未来版本备份原样恢复，不能作为新版已校验题入库', () async {
    final snapshot = problem().toSnapshot();
    final metadata = jsonDecode(snapshot['generationMetadataJson'] as String)
        as Map<String, dynamic>;
    metadata['schemaVersion'] = 2;
    snapshot['generationMetadataJson'] = jsonEncode(metadata);
    await BackupService().restoreFromJson(jsonEncode({
      'version': 1,
      'llmProblems': [snapshot],
    }),);
    await HiveBoxes.close();
    await HiveBoxes.init();
    final restored = LlmProblemRepository().getById('p1')!;
    expect(restored.toSnapshot(), snapshot);
    expect(WordProblemMetadata.decode(restored.generationMetadataJson), isNull);
    await expectLater(
        LlmProblemRepository().addAll([restored]), throwsFormatException,);
  });

  test('错误知识点及未学年级在入库和备份写入前拒绝', () async {
    final repository = LlmProblemRepository();
    await repository.addAll([problem(id: 'existing')]);
    for (final change in [
      <String, Object>{'topic': 'addition'},
      <String, Object>{'grade': 1},
    ]) {
      final snapshot = problem().toSnapshot()..addAll(change);
      await expectLater(repository.addAll([LlmProblem.fromSnapshot(snapshot)]),
          throwsFormatException,);
      await expectLater(
          BackupService().restoreFromJson(jsonEncode({
            'version': 1,
            'llmProblems': [snapshot],
          }),),
          throwsFormatException,);
      expect(HiveBoxes.llmProblems.keys, ['default_existing']);
    }
  });

  test('新题快照关闭重开Hive、作答snapshot复制、备份恢复均保留', () async {
    final original = problem();
    final repository = LlmProblemRepository();
    await repository.addAll([original]);
    await HiveBoxes.close();
    await HiveBoxes.init();
    expect(repository.getById('p1')!.generationMetadataJson,
        original.generationMetadataJson,);
    await repository.recordAttempt('p1',
        correct: true, activityId: 'test_word_activity',);
    final attempted = repository.getById('p1')!;
    expect(attempted.generationMetadataJson, original.generationMetadataJson);
    expect(attempted.appliedActivityIds, ['test_word_activity']);
    // Hive 的 DateTime 帧保存到毫秒，先从磁盘读取再比较备份往返。
    await HiveBoxes.close();
    await HiveBoxes.init();
    final snapshot = repository.getById('p1')!.toSnapshot();
    final backup = BackupService();
    final exported = await backup.exportToJson(includeCredentials: false);
    await backup.restoreFromJson(exported);
    expect(repository.getById('p1')!.toSnapshot(), snapshot);
    await HiveBoxes.close();
    await HiveBoxes.init();
    expect(repository.getById('p1')!.toSnapshot(), snapshot);
  });

  test('旧题缺少元数据可恢复且保持历史题面', () async {
    final old = problem(legacy: true).toSnapshot()
      ..remove('generationMetadataJson');
    await BackupService().restoreFromJson(jsonEncode({
      'version': 1,
      'llmProblems': [old],
    }),);
    final stored = LlmProblemRepository().getById('p1')!;
    expect(stored.generationMetadataJson, '');
    expect(stored.questionText, old['questionText']);
    expect(stored.answer, 9);
  });

  test('篡改目标、题面、讲解或单位在备份写入前拒绝，存量不丢', () async {
    await LlmProblemRepository().addAll([problem(id: 'existing')]);
    for (final field in [
      'questionText',
      'unit',
      'explanation',
      'generationMetadataJson',
    ]) {
      final invalid = problem().toSnapshot();
      invalid[field] = field == 'unit'
          ? '朵'
          : field == 'generationMetadataJson'
              ? '{broken'
              : '被更改的文本';
      await expectLater(
        BackupService().restoreFromJson(jsonEncode({
          'version': 1,
          'llmProblems': [invalid],
        }),),
        throwsFormatException,
        reason: field,
      );
      expect(HiveBoxes.llmProblems.keys, ['default_existing']);
    }
    final invalid = problem().toSnapshot();
    final metadata =
        jsonDecode(invalid['generationMetadataJson'] as String) as Map;
    metadata['targetQuantityId'] = 'q0';
    invalid['generationMetadataJson'] = jsonEncode(metadata);
    await expectLater(
        BackupService().restoreFromJson(jsonEncode({
          'version': 1,
          'llmProblems': [invalid],
        }),),
        throwsFormatException,);
    expect(HiveBoxes.llmProblems.keys, ['default_existing']);
  });

  test('仓储预验证整批，新题面篡改不允许部分写入', () async {
    final invalid = problem(id: 'invalid').toSnapshot()
      ..['questionText'] = '一共有36瓶水，问另一个人的数量';
    final repository = LlmProblemRepository();
    await expectLater(
        repository.addAll([problem(), LlmProblem.fromSnapshot(invalid)]),
        throwsFormatException,);
    expect(repository.getAll(), isEmpty);
  });
}
