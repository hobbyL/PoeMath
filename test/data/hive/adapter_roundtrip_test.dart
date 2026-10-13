// test/data/hive/adapter_roundtrip_test.dart
//
// Hive 适配器落盘往返测试。
//
// 守卫「模型加了 @HiveField 但忘记重跑 build_runner」这类缺陷：
// 同进程内 box.get 返回的是内存中的同一实例，仓储单测读到的字段值
// 即使适配器没写盘也是对的；只有关闭 box 后重新打开（真正走
// 序列化 → 反序列化）才能暴露适配器缺字段。
// 因此这里用纯 test() 做真实 IO，不在 testWidgets 的 fake-async 区内。

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/models/review_schedule.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  /// 关闭并重开所有 box，强制数据走一遍磁盘序列化。
  Future<void> reopenBoxes() async {
    await HiveBoxes.close();
    await HiveBoxes.init();
  }

  test('ReviewSchedule.lastScore 关闭重开后仍保留', () async {
    await HiveBoxes.reviewSchedules.put(
      'default_poem_a',
      ReviewSchedule(
        poemId: 'poem_a',
        profileId: 'default',
        currentRound: 2,
        nextReviewDate: DateTime(2026, 10, 20),
        lastReviewedAt: DateTime(2026, 10, 13),
        lastScore: 0.85,
      ),
    );
    // 背诵完成路径：lastScore 为 null 也要原样保留。
    await HiveBoxes.reviewSchedules.put(
      'default_poem_b',
      ReviewSchedule(
        poemId: 'poem_b',
        profileId: 'default',
        nextReviewDate: DateTime(2026, 10, 14),
      ),
    );

    await reopenBoxes();

    final a = HiveBoxes.reviewSchedules.get('default_poem_a')!;
    expect(a.lastScore, 0.85);
    expect(a.currentRound, 2);
    expect(a.lastReviewedAt, DateTime(2026, 10, 13));
    final b = HiveBoxes.reviewSchedules.get('default_poem_b')!;
    expect(b.lastScore, isNull);
  });

  test('MathMistake 聚合字段关闭重开后仍保留', () async {
    await HiveBoxes.mathMistakes.put(
      'default_m_a',
      MathMistake(
        id: 'm_a',
        profileId: 'default',
        problemText: '25 + 38 = ?',
        correctAnswer: '63',
        userAnswer: '61',
        problemType: 'addition',
        grade: 2,
        errorType: 'carry_omission',
        createdAt: DateTime(2026, 10, 1),
        retryCount: 1,
        wrongCount: 3,
        lastWrongAt: DateTime(2026, 10, 12),
        consolidationRound: 2,
        nextConsolidationDate: DateTime(2026, 10, 15),
      ),
    );
    // 迁移前的旧数据：lastWrongAt 为 null 也要原样保留。
    await HiveBoxes.mathMistakes.put(
      'default_m_b',
      MathMistake(
        id: 'm_b',
        profileId: 'default',
        problemText: '7 × 8 = ?',
        correctAnswer: '56',
        userAnswer: '54',
        problemType: 'multiplication',
        grade: 2,
      ),
    );

    await reopenBoxes();

    final a = HiveBoxes.mathMistakes.get('default_m_a')!;
    expect(a.wrongCount, 3);
    expect(a.lastWrongAt, DateTime(2026, 10, 12));
    expect(a.createdAt, DateTime(2026, 10, 1));
    expect(a.retryCount, 1);
    expect(a.consolidationRound, 2);
    expect(a.nextConsolidationDate, DateTime(2026, 10, 15));
    final b = HiveBoxes.mathMistakes.get('default_m_b')!;
    expect(b.wrongCount, 1);
    expect(b.lastWrongAt, isNull);
    expect(b.consolidationRound, 0);
    expect(b.nextConsolidationDate, isNull);
  });
}
