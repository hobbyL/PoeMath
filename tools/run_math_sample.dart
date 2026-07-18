import 'dart:math';
import 'package:poemath/math_engine/math_engine.dart';
import 'package:poemath/math_engine/models/math_problem.dart';
import 'package:poemath/math_engine/presets/grade_presets.dart';
import 'package:poemath/math_engine/validators/constraint_checker.dart';

void main() {
  var total = 0;
  var violations = 0;
  var judgeFails = 0;
  final modesSeen = <String>{};

  for (var grade = 1; grade <= 6; grade++) {
    for (final semester in ['上', '下']) {
      var local = 0;
      for (var i = 0; i < 100; i++) {
        final p = MathEngine.generate(
          grade: grade,
          semester: semester,
          random: Random(grade * 1000 + semester.codeUnitAt(0) + i),
        );
        total++;
        modesSeen.add(p.mode.name);
        final config = GradePresets.get(grade, semester);
        final v = ConstraintChecker.check(p, config);
        if (v != null) {
          local++;
          violations++;
          if (violations <= 15) {
            print('VIO g$grade$semester ${p.problemText}=${p.answerText} | $v');
          }
        }
        final j = MathEngine.judge(p, p.answerText);
        if (!j.isCorrect) {
          judgeFails++;
          if (judgeFails <= 10) {
            print('JUDGE_FAIL g$grade$semester ${p.problemText} ans=${p.answerText}');
          }
        }
      }
      print('grade $grade $semester done localVio=$local');
    }
  }
  print('TOTAL=$total violations=$violations judgeFails=$judgeFails modes=$modesSeen');

  for (final mode in ProblemMode.values) {
    var hits = 0;
    for (var i = 0; i < 40; i++) {
      final p = MathEngine.generate(
        grade: 3,
        semester: '下',
        mode: mode,
        random: Random(8000 + mode.index * 100 + i),
      );
      if (p.mode == mode) hits++;
    }
    print('mode ${mode.name} hits=$hits/40');
  }
}
