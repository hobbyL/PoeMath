import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/hive/migrations/math_mistake_key_migration.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/math/math_practice_request.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  test('错题知识点及完整快照经过适配器重开和备份恢复仍相同', () async {
    final p = MathEngine.generate(
        grade: 2,
        semester: '下',
        skillId: MathSkill.remainderDivision.id,
        random: Random(7),);
    final repo = MathMistakeRepository();
    await repo.recordWrong(
      problemText: p.problemText,
      correctAnswer: p.answerText,
      userAnswer: '0',
      problemType: 'remainder',
      grade: p.grade,
      skillId: p.skillId,
      semester: p.semester,
      problemJson: jsonEncode(p.toJson()),
    );
    final id = repo.getAll().single.id;
    final original = repo.getById(id)!;
    original.wrongCount = 7;
    original.consolidationRound = 2;
    original.nextConsolidationDate = DateTime(2026, 10, 18);
    await original.save();
    await MathMistakeKeyMigration.run();
    expect(repo.getById(id)!.wrongCount, 7);
    expect(repo.getById(id)!.consolidationRound, 2);
    expect(repo.getById(id)!.nextConsolidationDate, DateTime(2026, 10, 18));
    await HiveBoxes.close();
    await HiveBoxes.init();
    expect(repo.getById(id)!.skillId, MathSkill.remainderDivision.id);
    expect(repo.getById(id)!.semester, '下');
    final backup = BackupService();
    final json = await backup.exportToJson();
    await backup.restoreFromJson(json);
    final restored = repo.getById(id)!;
    expect(jsonDecode(restored.problemJson!), p.toJson());
    expect(restored.skillId, p.skillId);
    expect(restored.semester, p.semester);
  });

  test('一次性专项请求消费后清空，不改变默认偏好', () async {
    await SettingsRepository().setLearningBackground(4, '下');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final next = container.read(nextMathPracticeRequestProvider.notifier);
    const request = MathPracticeRequest(
      grade: 2,
      semester: '上',
      count: 5,
      difficulty: DifficultyLevel.medium,
      skillId: 'multiplication_table',
    );
    next.setNext(request);
    expect(next.consume(), same(request));
    expect(next.consume(), isNull);
    expect(container.read(mathGradeProvider), 4);
    expect(container.read(mathSemesterProvider), '下');
    expect(SettingsRepository().selectedGrade, 4);
    expect(MathPracticeRequest.fromJson(request.toJson()).toJson(),
        request.toJson(),);
  });

  test('旧作答记录兼容，新的知识点和过程字段完整往返', () {
    final old =
        ProblemRecord.fromJson({'q': '1+1=?', 'a': '2', 'u': '2', 'c': true});
    expect(old.skillId, isNull);
    const record = ProblemRecord(
      problemText: '38+45=?',
      answerText: '83',
      userAnswer: '83',
      isCorrect: false,
      skillId: 'addition_carry',
      attempt: {'carry': 0},
    );
    expect(ProblemRecord.fromJson(record.toJson()).toJson(), record.toJson());
  });
}
