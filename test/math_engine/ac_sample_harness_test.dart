import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/math_engine.dart';
import 'package:poemath/math_engine/models/math_problem.dart';
import 'package:poemath/math_engine/presets/grade_presets.dart';
import 'package:poemath/math_engine/validators/constraint_checker.dart';

void main() {
  test('AC3.2 1-6年级各100题约束采样', () {
    var violations = 0;
    final modesSeen = <ProblemMode>{};

    for (var grade = 1; grade <= 6; grade++) {
      for (final semester in ['上', '下']) {
        for (var i = 0; i < 100; i++) {
          final p = MathEngine.generate(
            grade: grade,
            semester: semester,
            random: Random(grade * 1000 + semester.codeUnitAt(0) + i),
          );
          modesSeen.add(p.mode);
          final config = GradePresets.get(grade, semester);
          final v = ConstraintChecker.check(p, config);
          if (v != null) {
            violations++;
            // print first few
            if (violations <= 10) {
              // ignore: avoid_print
              print('VIO g$grade$semester ${p.problemText}=${p.answerText} $v');
            }
          }
          final j = MathEngine.judge(p, p.answerText);
          expect(j.isCorrect, isTrue, reason: '${p.problemText} ans=${p.answerText}');
        }
      }
    }
    expect(violations, 0, reason: 'constraint violations=$violations');
    // ignore: avoid_print
    print('modes seen: $modesSeen');
  }, timeout: const Timeout(Duration(minutes: 2)),);

  test('五年级上 操作数不超过 maxOperand', () {
    for (var i = 0; i < 200; i++) {
      final p = MathEngine.generate(
        grade: 5,
        semester: '上',
        random: Random(50000 + i),
      );
      final config = GradePresets.grade5a;
      for (final op in p.operands) {
        expect(
          op.asDouble,
          inInclusiveRange(config.minOperand, config.maxOperand),
          reason: '${p.problemText} operand ${op.asDouble}',
        );
      }
      expect(ConstraintChecker.check(p, config), isNull);
    }
  });
}
