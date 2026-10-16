import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:poemath/data/models/challenge_record.dart';
import 'package:poemath/data/models/learning_activity.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/models/review_schedule.dart';

/// 写出升级前的真实字段集合，以当前 adapter 重开，避免用 null 冒充缺字段。
class _LegacyFields {
  const _LegacyFields(this.values);
  final Map<int, Object?> values;
}

class _LegacyFieldsAdapter extends TypeAdapter<_LegacyFields> {
  _LegacyFieldsAdapter(this.typeId);

  @override
  final int typeId;

  @override
  _LegacyFields read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, _LegacyFields fields) {
    writer.writeByte(fields.values.length);
    for (final field in fields.values.entries) {
      writer
        ..writeByte(field.key)
        ..write(field.value);
    }
  }
}

void _registerCurrentAdapters() {
  Hive.registerAdapter(ChallengeRecordAdapter(), override: true);
  Hive.registerAdapter(LearningActivityAdapter(), override: true);
  Hive.registerAdapter(MathMistakeAdapter(), override: true);
  Hive.registerAdapter(PoemProgressAdapter(), override: true);
  Hive.registerAdapter(LearningStatusAdapter(), override: true);
  Hive.registerAdapter(ReviewScheduleAdapter(), override: true);
}

void main() {
  late Directory directory;
  final at = DateTime(2026, 10, 16, 10);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('learning_adapter_');
    Hive.init(directory.path);
    _registerCurrentAdapters();
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('学习明细、首次掌握、复习周期和竖式过程关闭重开后完整保留', () async {
    final box = await Hive.openBox<dynamic>('learning');
    await box.put(
      'activity',
      LearningActivity(
        id: 'activity',
        profileId: 'default',
        activityType: 'poemDictation',
        totalItems: 1,
        successfulItems: 0,
        starsEarned: 0,
        durationSeconds: 60,
        completedAt: at,
        detailsJson: '{"rawAnswer":"明月光","lines":[{"hintUsed":true}]}',
      ),
    );
    await box.put(
      'progress',
      PoemProgress(
        poemId: 'poem',
        profileId: 'default',
        status: LearningStatus.mastered,
        firstMasteredAt: at,
      ),
    );
    await box.put(
      'review',
      ReviewSchedule(
        poemId: 'poem',
        profileId: 'default',
        currentRound: 1,
        nextReviewDate: at,
        historyJson: '{"cycleId":"cycle-2","reviews":[{"id":"review-1"}]}',
      ),
    );
    await box.put(
      'mistake',
      MathMistake(
        id: 'mistake',
        profileId: 'default',
        problemText: '38+45',
        correctAnswer: '83',
        userAnswer: '83',
        problemType: 'vertical',
        grade: 2,
        skillId: 'addition_carry',
        semester: '上',
        problemJson: '{"operands":[38,45]}',
        attemptJson: '{"ones":"3","tens":"8","regroup":"0"}',
      ),
    );
    await box.close();
    final reopened = await Hive.openBox<dynamic>('learning');
    expect(
      (reopened.get('activity') as LearningActivity).detailsJson,
      '{"rawAnswer":"明月光","lines":[{"hintUsed":true}]}',
    );
    expect((reopened.get('progress') as PoemProgress).firstMasteredAt, at);
    expect(
      (reopened.get('review') as ReviewSchedule).historyJson,
      '{"cycleId":"cycle-2","reviews":[{"id":"review-1"}]}',
    );
    final mistake = reopened.get('mistake') as MathMistake;
    expect(mistake.skillId, 'addition_carry');
    expect(mistake.semester, '上');
    expect(mistake.problemJson, '{"operands":[38,45]}');
    expect(mistake.attemptJson, '{"ones":"3","tens":"8","regroup":"0"}');
  });

  test('竖式挑战方案关闭重开后保留', () async {
    final box = await Hive.openBox<ChallengeRecord>('challenge');
    await box.put(
      'vertical',
      ChallengeRecord(
        id: 'vertical',
        profileId: 'default',
        mode: 'fixed',
        calculationMode: 'vertical',
        score: 10,
        totalAnswered: 1,
        correctCount: 1,
        bestCombo: 1,
        grade: 2,
        semester: '上',
        difficulty: 'medium',
        durationSeconds: 60,
        createdAt: at,
      ),
    );
    await box.close();
    final reopened = await Hive.openBox<ChallengeRecord>('challenge');
    expect(reopened.get('vertical')!.calculationMode, 'vertical');
    expect(reopened.get('vertical')!.calculationModeLabel, '竖式');
  });

  final legacyCases = <({
    int typeId,
    Map<int, Object?> fields,
    void Function(Object) verify,
  })>[
    (
      typeId: 14,
      fields: {
        0: 'old-challenge',
        1: 'default',
        2: 'fixed',
        3: 80,
        4: 10,
        5: 8,
        6: 4,
        7: 2,
        8: '上',
        9: 'medium',
        10: 60,
        11: at,
        12: 2,
      },
      verify: (value) =>
          expect((value as ChallengeRecord).calculationMode, 'normal'),
    ),
    (
      typeId: 15,
      fields: {
        0: 'activity',
        1: 'default',
        2: 'poemQuiz',
        3: 1,
        4: 1,
        5: 'poem',
        6: 3,
        7: 60,
        8: at,
      },
      verify: (value) =>
          expect((value as LearningActivity).detailsJson, isNull),
    ),
    (
      typeId: 5,
      fields: {
        0: 'poem',
        1: 'default',
        2: LearningStatus.mastered,
        3: 4,
        4: 2,
        5: at,
        6: at,
        7: 3,
      },
      verify: (value) =>
          expect((value as PoemProgress).firstMasteredAt, isNull),
    ),
    (
      typeId: 7,
      fields: {0: 'poem', 1: 'default', 2: 5, 3: at, 4: at, 5: true, 6: 1.0},
      verify: (value) => expect((value as ReviewSchedule).historyJson, isNull),
    ),
    (
      typeId: 8,
      fields: {
        0: 'mistake',
        1: 'default',
        2: '38+45',
        3: '83',
        4: '82',
        5: 'vertical',
        6: 2,
        7: null,
        8: null,
        9: at,
        10: false,
        11: 0,
        12: 1,
        13: null,
        14: 0,
        15: null,
      },
      verify: (value) {
        final mistake = value as MathMistake;
        expect(mistake.skillId, isNull);
        expect(mistake.semester, isNull);
        expect(mistake.problemJson, isNull);
        expect(mistake.attemptJson, isNull);
      },
    ),
  ];
  for (final fixture in legacyCases) {
    test('旧字段集合 typeId=${fixture.typeId} 可读取，新增历史保持未知', () async {
      Hive.registerAdapter(
        _LegacyFieldsAdapter(fixture.typeId),
        override: true,
      );
      final old = await Hive.openBox<dynamic>('legacy');
      await old.put('record', _LegacyFields(fixture.fields));
      await old.close();
      _registerCurrentAdapters();
      final current = await Hive.openBox<dynamic>('legacy');
      fixture.verify(current.get('record') as Object);
    });
  }
}
