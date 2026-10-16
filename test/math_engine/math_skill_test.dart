import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

void main() {
  test('全册次所有生成题结构快照精确往返，保留题面与判分语义', () {
    for (var grade = 1; grade <= 6; grade++) {
      for (final semester in ['上', '下']) {
        for (final difficulty in DifficultyLevel.values) {
          for (var seed = 0; seed < 20; seed++) {
            final p = MathEngine.generate(
              grade: grade,
              semester: semester,
              difficulty: difficulty,
              random: Random(seed),
            );
            final restored = MathProblem.fromJson(
                jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>,);
            expect(restored.toJson(), p.toJson());
            expect(restored.problemText, p.problemText);
            expect(restored.answerText, p.answerText);
            expect(MathSkill.fromId(restored.skillId), isNotNull);
            expect(restored.semester, semester);
            expect(MathEngine.judge(restored, restored.answerText).isCorrect,
                isTrue,);
          }
        }
      }
    }
  });

  const cases = [
    (1, '下', MathSkill.additionCarry),
    (2, '上', MathSkill.subtractionBorrow),
    (2, '上', MathSkill.multiplicationTable),
    (2, '下', MathSkill.remainderDivision),
    (3, '下', MathSkill.multiplication),
    (3, '下', MathSkill.division),
    (3, '下', MathSkill.operationOrder),
    (4, '上', MathSkill.operationLaw),
    (4, '下', MathSkill.decimal),
    (5, '下', MathSkill.fraction),
    (5, '下', MathSkill.equation),
    (6, '上', MathSkill.percentage),
    (6, '下', MathSkill.ratio),
    (6, '下', MathSkill.negative),
  ];
  for (final (grade, semester, skill) in cases) {
    test('${skill.label} 多种子专项严格匹配且符合册次约束', () {
      for (var seed = 0; seed < 40; seed++) {
        final p = MathEngine.generate(
          grade: grade,
          semester: semester,
          skillId: skill.id,
          random: Random(seed),
        );
        expect(p.skillId, skill.id);
        expect(ConstraintChecker.check(p, GradePresets.get(grade, semester)),
            isNull,);
        if (skill == MathSkill.additionCarry ||
            skill == MathSkill.subtractionBorrow) {
          expect(p.operators, [
            skill == MathSkill.additionCarry ? Operator.add : Operator.subtract,
          ]);
          expect(MathSkill.hasRegrouping(p), isTrue);
        }
        if (skill == MathSkill.remainderDivision) {
          expect(p.resultForm, ResultForm.withRemainder);
          expect(p.remainder, greaterThan(0));
        }
        if (skill == MathSkill.equation) {
          expect(p.mode, ProblemMode.findMissing);
          expect(p.missingIndex, isNotNull);
          expect(p.expressionResult, isNotNull);
        }
        if (skill == MathSkill.ratio) expect(p.problemText, contains(':'));
        if (skill == MathSkill.percentage) expect(p.problemText, contains('%'));
        if (skill == MathSkill.multiplicationTable) {
          expect(
              p.operands.every(
                  (n) => n.isInteger && n.asInteger >= 1 && n.asInteger <= 81,),
              isTrue,);
          expect(
              p.operators.single, isIn([Operator.multiply, Operator.divide]),);
        }
      }
    });
  }

  test('未知和不支持专项明确拒绝，不走通用加减兜底', () {
    expect(() => MathEngine.generate(grade: 1, semester: '上', skillId: 'typo'),
        throwsArgumentError,);
    expect(
        () => MathEngine.generate(
            grade: 1, semester: '上', skillId: MathSkill.fraction.id,),
        throwsArgumentError,);
    expect(
      () => MathEngine.generate(
        grade: 5,
        semester: '下',
        mode: ProblemMode.findResult,
        skillId: MathSkill.equation.id,
      ),
      throwsStateError,
    );
    expect(
      () => MathEngine.generate(
        grade: 6,
        semester: '下',
        mode: ProblemMode.compare,
        skillId: MathSkill.ratio.id,
      ),
      throwsStateError,
    );
  });
}
