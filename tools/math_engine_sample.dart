
// ignore_for_file: avoid_print
import 'dart:math';
import 'package:poemath/math_engine/math_engine.dart';
import 'package:poemath/math_engine/models/math_problem.dart';
import 'package:poemath/math_engine/presets/grade_presets.dart';
import 'package:poemath/math_engine/validators/constraint_checker.dart';

void main() {
  var total = 0;
  var violations = 0;
  final modesSeen = <ProblemMode>{};
  final formsSeen = <ResultForm>{};

  for (var grade = 1; grade <= 6; grade++) {
    for (final semester in ['上', '下']) {
      var localVio = 0;
      for (var i = 0; i < 100; i++) {
        final p = MathEngine.generate(
          grade: grade,
          semester: semester,
          random: Random(grade * 1000 + semester.codeUnitAt(0) + i),
        );
        total++;
        modesSeen.add(p.mode);
        formsSeen.add(p.resultForm);
        final config = GradePresets.get(grade, semester);
        final v = ConstraintChecker.check(p, config);
        if (v != null) {
          localVio++;
          violations++;
          if (localVio <= 3) {
            print('VIOLATION g$grade$semester: ${p.expressionText} => ${p.answerText} | $v');
          }
        }
        // sanity: answer judge correct path
        final j = MathEngine.judge(p, p.answerText);
        if (!j.isCorrect) {
          print('JUDGE_FAIL g$grade$semester: ${p.expressionText} ans=${p.answerText}');
          violations++;
        }
      }
      print('grade $grade $semester: 100 ok, violations=$localVio');
    }
  }

  print('TOTAL=$total violations=$violations');
  print('modes=$modesSeen');
  print('forms=$formsSeen');
  // try each mode explicitly where possible
  for (final mode in ProblemMode.values) {
    var ok = 0;
    for (var i = 0; i < 30 && ok == 0; i++) {
      try {
        final p = MathEngine.generate(
          grade: 3,
          semester: '下',
          mode: mode,
          random: Random(9000 + i),
        );
        if (p.mode == mode) ok++;
      } catch (e) {
        print('mode $mode error: $e');
      }
    }
    print('mode $mode sample_ok=$ok');
  }
}
