// test/data/hive/migrations/math_mistake_key_migration_test.dart
//
// 错题 key 迁移单测：
// 多条同题合并计数、单条改写 id、版本标记幂等、已置位早退、
// 跨 profile 不合并。

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/constants/hive_keys.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/hive/migrations/math_mistake_key_migration.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';

import '../../../helpers/hive_test_helper.dart';

void main() {
  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  MathMistake legacyMistake({
    required String id,
    String profileId = 'default',
    required DateTime createdAt,
    int retryCount = 0,
    bool isResolved = false,
  }) {
    return MathMistake(
      id: id,
      profileId: profileId,
      problemText: '25 + 38 = ?',
      correctAnswer: '63',
      userAnswer: '61',
      problemType: 'addition',
      grade: 2,
      createdAt: createdAt,
      retryCount: retryCount,
      isResolved: isResolved,
    );
  }

  test('多条同题合并：保最早 createdAt、wrongCount=组条数、retryCount 取最大',
      () async {
    final old = DateTime(2026, 1, 1);
    final mid = DateTime(2026, 2, 1);
    final recent = DateTime(2026, 3, 1);
    await HiveBoxes.mathMistakes.put('default_s1',
        legacyMistake(id: 's1', createdAt: mid, retryCount: 2),);
    await HiveBoxes.mathMistakes.put('default_s2',
        legacyMistake(id: 's2', createdAt: old, retryCount: 0),);
    await HiveBoxes.mathMistakes.put('default_s3',
        legacyMistake(id: 's3', createdAt: recent, retryCount: 1),);

    await MathMistakeKeyMigration.run();

    final list = HiveBoxes.mathMistakes.values.toList();
    expect(list, hasLength(1));
    final merged = list.single;
    expect(
      merged.id,
      MathMistakeRepository.problemKey(
        problemText: '25 + 38 = ?',
        correctAnswer: '63',
      ),
    );
    expect(merged.createdAt, old);
    expect(merged.wrongCount, 3);
    expect(merged.lastWrongAt, recent);
    expect(merged.retryCount, 2);
    // 版本标记置位
    expect(
      HiveBoxes.meta.get(HiveKeys.metaMistakeKeyMigrated),
      true,
    );
  });

  test('单条错题改写 id 为新 key 并回填 lastWrongAt', () async {
    final created = DateTime(2026, 5, 1);
    await HiveBoxes.mathMistakes
        .put('default_uuid_abc', legacyMistake(id: 'uuid_abc', createdAt: created));

    await MathMistakeKeyMigration.run();

    final list = HiveBoxes.mathMistakes.values.toList();
    expect(list, hasLength(1));
    final m = list.single;
    expect(
      m.id,
      MathMistakeRepository.problemKey(
        problemText: '25 + 38 = ?',
        correctAnswer: '63',
      ),
    );
    expect(m.wrongCount, 1);
    expect(m.lastWrongAt, created);
    expect(HiveBoxes.mathMistakes.get('default_uuid_abc'), isNull);
  });

  test('迁移幂等：置位后再次运行不改动数据', () async {
    await HiveBoxes.mathMistakes.put(
        'default_s1', legacyMistake(id: 's1', createdAt: DateTime(2026, 1, 1)),);
    await MathMistakeKeyMigration.run();
    final countAfterFirst = HiveBoxes.mathMistakes.length;
    final recordAfterFirst = HiveBoxes.mathMistakes.values.first;

    await MathMistakeKeyMigration.run();

    expect(HiveBoxes.mathMistakes.length, countAfterFirst);
    final recordAfterSecond = HiveBoxes.mathMistakes.values.first;
    expect(recordAfterSecond.id, recordAfterFirst.id);
    expect(recordAfterSecond.wrongCount, recordAfterFirst.wrongCount);
  });

  test('同题面跨 profile 不合并', () async {
    await HiveBoxes.mathMistakes.put(
        'default_s1',
        legacyMistake(
            id: 's1', profileId: 'default', createdAt: DateTime(2026, 1, 1),),);
    await HiveBoxes.mathMistakes.put(
        'kid2_s1',
        legacyMistake(
            id: 's1', profileId: 'kid2', createdAt: DateTime(2026, 6, 1),),);

    await MathMistakeKeyMigration.run();

    final list = HiveBoxes.mathMistakes.values.toList();
    expect(list, hasLength(2));
    expect(
      list.where((m) => m.profileId == 'default').single.wrongCount,
      1,
    );
    expect(
      list.where((m) => m.profileId == 'kid2').single.wrongCount,
      1,
    );
  });

  test('空库迁移正常完成并置位', () async {
    await MathMistakeKeyMigration.run();
    expect(HiveBoxes.mathMistakes.isEmpty, isTrue);
    expect(
      HiveBoxes.meta.get(HiveKeys.metaMistakeKeyMigrated),
      true,
    );
  });
}
