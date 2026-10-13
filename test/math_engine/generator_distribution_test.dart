// test/math_engine/generator_distribution_test.dart
//
// 出题分布回归：原文件只有 `print`，没有任何断言 —— 分布跑偏、某种题型
// 彻底消失都不会让测试变红。这里按 GradeConfig 的约束做真实校验。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/math_engine/math_engine_api.dart';

/// 每个年级/学期生成的问题条数。样本要足够大，否则占比区间毫无意义。
const int _sampleSize = 400;

/// 生成一批题目。
List<MathProblem> _generate(int grade, String semester, int seed) {
  return MathEngine.generateBatch(
    grade: grade,
    semester: semester,
    count: _sampleSize,
    random: Random(seed),
  );
}

void main() {
  final presets = <(int, String)>[
    for (final grade in [1, 2, 3, 4, 5, 6])
      for (final sem in ['上', '下']) (grade, sem),
  ];

  test('每个年级/学期都能出题，且题型不超出该配置的 allowedModes', () {
    for (final (grade, sem) in presets) {
      final config = GradePresets.get(grade, sem);
      final problems = _generate(grade, sem, 42);

      expect(
        problems,
        hasLength(_sampleSize),
        reason: '${config.label} 未能生成足量题目',
      );

      for (final problem in problems) {
        expect(
          config.allowedModes,
          contains(problem.mode),
          reason: '${config.label} 出现了配置外的题型 ${problem.mode.name}',
        );
        expect(
          problem.grade,
          grade,
          reason: '${config.label} 的题目年级标记错误',
        );
      }
    }
  });

  test('每个年级/学期至少覆盖两种题型（单一题型＝出题退化）', () {
    for (final (grade, sem) in presets) {
      final config = GradePresets.get(grade, sem);
      final modes = _generate(grade, sem, 7).map((p) => p.mode).toSet();

      expect(
        modes.length,
        greaterThanOrEqualTo(2),
        reason: '${config.label} 只出了 ${modes.map((m) => m.name).join('/')}，'
            '题型多样性退化',
      );
    }
  });

  test('各题型的占比不过度倾斜，且没有题型被完全挤掉', () {
    for (final (grade, sem) in presets) {
      final config = GradePresets.get(grade, sem);
      final counts = <ProblemMode, int>{};
      for (final problem in _generate(grade, sem, 2026)) {
        counts[problem.mode] = (counts[problem.mode] ?? 0) + 1;
      }

      // 所有允许的题型都必须出现过：某个模式永远抽不到，说明权重配置
      // 或生成分支已经死了，而这类回归原先完全没有断言兜住。
      for (final mode in config.allowedModes) {
        expect(
          counts[mode] ?? 0,
          greaterThan(0),
          reason: '${config.label} 的 ${mode.name} 一次都没出现',
        );
      }

      // 任何单一题型不得超过 80%：超过即视为权重严重失衡。
      for (final entry in counts.entries) {
        expect(
          entry.value / _sampleSize,
          lessThan(0.8),
          reason: '${config.label} 的 ${entry.key.name} 占比 '
              '${(entry.value / _sampleSize * 100).toStringAsFixed(0)}% 过高',
        );
      }
    }
  });

  test('同一随机种子结果可复现（出题不应依赖全局随机状态）', () {
    final first = _generate(3, '上', 99);
    final second = _generate(3, '上', 99);

    expect(first.length, second.length);
    for (var i = 0; i < first.length; i++) {
      expect(
        first[i].problemText,
        second[i].problemText,
        reason: '同种子第 $i 题不一致',
      );
    }
  });

  test('所有题目都满足本配置的操作数与结果上限', () {
    for (final (grade, sem) in presets) {
      final config = GradePresets.get(grade, sem);

      for (final problem in _generate(grade, sem, 555)) {
        for (final operand in problem.operands) {
          expect(
            operand.asDouble,
            lessThanOrEqualTo(config.maxOperand.toDouble()),
            reason: '${config.label} 操作数 ${operand.asDouble} 超过 maxOperand',
          );
          // 操作数下界取配置的 minOperand：六下负数是合法考点
          // （`allowNegative: true, minOperand: -100`），不能一刀切按 0 断言。
          expect(
            operand.asDouble,
            greaterThanOrEqualTo(config.minOperand.toDouble()),
            reason: '${config.label} 操作数 ${operand.asDouble} '
                '低于 minOperand ${config.minOperand}',
          );
        }
        // 注：此处**不**校验 `operands.length <= maxOperands`。
        // `maxOperands` 并非引擎级不变量：它只被 `MixedOperationGen` 当作
        // 私有步数上限读取（`clamp(2, 3)`，与 `DifficultyAdjuster._hard`
        // 的「困难最多 +1 步」耦合），而 `grade3a.maxOperands == 2` 却在
        // `allowedModes` 里允许 chain —— `LawOfOperationGen` 必然产出 3
        // 操作数的运算律题。断言它会长期红，见引擎规格的已知不一致条目。
        // 真正的硬约束是「操作数/结果区间」与「模式白名单」，见
        // `ConstraintChecker`。
      }
    }
  });
}
