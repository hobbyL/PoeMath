// test/features/math/mistake_consolidation_labels_test.dart
//
// ⑤ 巩固文案单一来源测试：状态 pill、筛选 chip、重练反馈四分支。
// 文案中的天数必须与仓储的 consolidationIntervals 保持一致。

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/features/math/mistake_consolidation_labels.dart';
import 'package:poemath/features/math/providers/math_providers.dart';

MathMistake _mistake({
  bool isResolved = false,
  int consolidationRound = 0,
}) {
  return MathMistake(
    id: 'm1',
    profileId: 'default',
    problemText: '25 + 38 = ?',
    correctAnswer: '63',
    userAnswer: '61',
    problemType: 'addition',
    grade: 2,
    isResolved: isResolved,
    consolidationRound: consolidationRound,
  );
}

void main() {
  group('状态标签', () {
    test('三态分别为未掌握 / 待巩固第 N 关 / 已掌握', () {
      expect(mistakeStatusLabel(_mistake()), '未掌握');
      expect(
        mistakeStatusLabel(_mistake(consolidationRound: 2)),
        '待巩固 第 2 关',
      );
      expect(mistakeStatusLabel(_mistake(isResolved: true)), '已掌握');
    });

    test('筛选 chip 文案与三态一致', () {
      expect(
        mistakeStatusFilterLabel(MistakeStatusFilter.unmastered),
        '未掌握',
      );
      expect(
        mistakeStatusFilterLabel(MistakeStatusFilter.consolidating),
        '待巩固',
      );
      expect(
        mistakeStatusFilterLabel(MistakeStatusFilter.mastered),
        '已掌握',
      );
    });
  });

  group('重练反馈四分支', () {
    test('首次答对提示 1 天后抽查', () {
      expect(
        repracticeOutcomeMessage(
          RepracticeOutcome.enteredConsolidation,
          _mistake(consolidationRound: 1),
        ),
        '答对了！1 天后抽查一次',
      );
    });

    test('通过第 1 关提示 3 天后再抽查', () {
      // 状态机执行后 round 已推进到 2
      expect(
        repracticeOutcomeMessage(
          RepracticeOutcome.advanced,
          _mistake(consolidationRound: 2),
        ),
        '巩固第 1 关通过，3 天后再抽查',
      );
    });

    test('通过第 2 关提示 7 天后再抽查', () {
      expect(
        repracticeOutcomeMessage(
          RepracticeOutcome.advanced,
          _mistake(consolidationRound: 3),
        ),
        '巩固第 2 关通过，7 天后再抽查',
      );
    });

    test('三关全过与打回未掌握', () {
      expect(
        repracticeOutcomeMessage(
          RepracticeOutcome.mastered,
          _mistake(isResolved: true),
        ),
        '三关全过，已彻底掌握',
      );
      expect(
        repracticeOutcomeMessage(RepracticeOutcome.reset, _mistake()),
        '抽查答错，回到未掌握，重新练起来',
      );
    });

    test('文案天数取自 consolidationIntervals（防硬编码漂移）', () {
      expect(MathMistakeRepository.consolidationIntervals, [1, 3, 7]);
    });
  });
}
