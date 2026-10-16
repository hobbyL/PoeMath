import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/math_engine/presets/difficulty_adjuster.dart';

void main() {
  for (var grade = 1; grade <= 6; grade++) {
    for (final semester in ['上', '下']) {
      for (final difficulty in DifficultyLevel.values) {
        test('$grade$semester/${difficulty.name} 方案开放与实际出题一致', () {
          final base = GradePresets.get(grade, semester);
          final config = DifficultyAdjuster.adjust(base, difficulty);
          final supportsVertical = grade != 1 &&
              !(grade == 5 && semester == '下') &&
              difficulty != DifficultyLevel.easy;
          expect(
            MathEngine.supportedModes(
              grade: grade,
              semester: semester,
              difficulty: difficulty,
            ).contains(ProblemMode.vertical),
            supportsVertical,
          );
          if (!supportsVertical) {
            expect(
              () => MathEngine.generate(
                grade: grade,
                semester: semester,
                difficulty: difficulty,
                mode: ProblemMode.vertical,
              ),
              throwsArgumentError,
            );
          }
          for (var seed = 0; seed < 40; seed++) {
            final normal = MathEngine.generate(
              grade: grade,
              semester: semester,
              difficulty: difficulty,
              random: Random(seed),
            );
            expect(normal.mode, isNot(ProblemMode.vertical));
            expect(ConstraintChecker.check(normal, config), isNull);
            if (!supportsVertical) continue;
            final vertical = MathEngine.generate(
              grade: grade,
              semester: semester,
              difficulty: difficulty,
              mode: ProblemMode.vertical,
              random: Random(seed),
            );
            expect(vertical.mode, ProblemMode.vertical);
            expect(vertical.grade, grade);
            expect(vertical.semester, semester);
            expect(vertical.operands, hasLength(2));
            expect(vertical.operators, hasLength(1));
            expect(vertical.operators.single, isNot(Operator.divide));
            expect(vertical.operands.every((n) => !n.isNegative), isTrue);
            expect(vertical.displayText, isNull);
            expect(vertical.resultForm, isNot(ResultForm.withRemainder));
            expect(vertical.resultForm, isNot(ResultForm.fraction));
            expect(ConstraintChecker.check(vertical, config), isNull);
            expect(
              MathEngine.judge(vertical, vertical.answerText).isCorrect,
              isTrue,
            );
          }
        });
      }
    }
  }
}
