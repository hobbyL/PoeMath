// lib/math_engine/step_solver/step_solver.dart
//
// 分步解答生成器：为每道题生成面向小学生的自然语言解题步骤。

import '../models/answer_judgement.dart';
import '../models/math_problem.dart';

/// 分步解答生成器。
class StepSolver {
  const StepSolver._();

  /// 为给定题目生成分步解答。
  static List<SolutionStep> solve(MathProblem problem) {
    if (problem.operators.length == 1) {
      return _solveSingleOp(problem);
    }
    return _solveMultiOp(problem);
  }

  static List<SolutionStep> _solveSingleOp(MathProblem problem) {
    final a = problem.operands[0];
    final b = problem.operands[1];
    final op = problem.operators[0];
    final result = problem.result;
    final steps = <SolutionStep>[];

    switch (op) {
      case Operator.add:
        final aInt = a.asInteger;
        final bInt = b.asInteger;
        if (aInt < 100 && bInt < 100) {
          // 个位相加
          final unitsSum = (aInt % 10) + (bInt % 10);
          if (unitsSum >= 10) {
            steps.add(
              SolutionStep(
                description:
                    '个位：${aInt % 10} + ${bInt % 10} = $unitsSum，写${unitsSum % 10}进1',
                expression: '${aInt % 10} + ${bInt % 10} = $unitsSum',
                resultHint: '写${unitsSum % 10}，进1',
              ),
            );
          } else {
            steps.add(
              SolutionStep(
                description: '个位：${aInt % 10} + ${bInt % 10} = $unitsSum',
                expression: '${aInt % 10} + ${bInt % 10} = $unitsSum',
              ),
            );
          }
          // 十位相加
          final tensSum =
              (aInt ~/ 10) + (bInt ~/ 10) + (unitsSum >= 10 ? 1 : 0);
          steps.add(
            SolutionStep(
              description:
                  '十位：${aInt ~/ 10} + ${bInt ~/ 10}${unitsSum >= 10 ? " + 进位1" : ""} = $tensSum',
              expression: '十位 = $tensSum',
            ),
          );
        }
        steps.add(
          SolutionStep(
            description: '所以 $a + $b = $result',
            expression: '$a + $b = $result',
            resultHint: '$result',
          ),
        );

      case Operator.subtract:
        final aInt = a.asInteger;
        final bInt = b.asInteger;
        if (aInt < 100 && bInt < 100 && aInt >= 0 && bInt >= 0) {
          final aUnits = aInt % 10;
          final bUnits = bInt % 10;
          if (aUnits < bUnits) {
            steps.add(
              SolutionStep(
                description: '个位：$aUnits < $bUnits，不够减，从十位借1当10',
                expression:
                    '${aUnits + 10} - $bUnits = ${aUnits + 10 - bUnits}',
                resultHint: '写${aUnits + 10 - bUnits}',
              ),
            );
            final aTens = aInt ~/ 10 - 1;
            final bTens = bInt ~/ 10;
            steps.add(
              SolutionStep(
                description: '十位：$aTens - $bTens = ${aTens - bTens}',
                expression: '十位 = ${aTens - bTens}',
              ),
            );
          } else {
            steps.add(
              SolutionStep(
                description: '个位：$aUnits - $bUnits = ${aUnits - bUnits}',
                expression: '$aUnits - $bUnits = ${aUnits - bUnits}',
              ),
            );
          }
        }
        steps.add(
          SolutionStep(
            description: '所以 $a - $b = $result',
            expression: '$a - $b = $result',
            resultHint: '$result',
          ),
        );

      case Operator.multiply:
        steps.add(
          SolutionStep(
            description: '计算 $a × $b',
            expression: '$a × $b = $result',
            resultHint: '$result',
          ),
        );

      case Operator.divide:
        if (problem.resultForm == ResultForm.withRemainder) {
          final dividend = a.asInteger;
          final divisor = b.asInteger;
          final quotient = result.asInteger;
          final remainder = problem.remainder ?? 0;
          steps.add(
            SolutionStep(
              description: '$dividend ÷ $divisor = $quotient…$remainder',
              expression: '$divisor × $quotient = ${divisor * quotient}',
              resultHint: '余 $remainder',
            ),
          );
          steps.add(
            SolutionStep(
              description: '验算：$divisor × $quotient + $remainder = $dividend',
              expression: '${divisor * quotient} + $remainder = $dividend',
            ),
          );
        } else {
          steps.add(
            SolutionStep(
              description: '计算 $a ÷ $b',
              expression: '$a ÷ $b = $result',
              resultHint: '$result',
            ),
          );
        }
    }

    return steps;
  }

  static List<SolutionStep> _solveMultiOp(MathProblem problem) {
    final steps = <SolutionStep>[];
    final hasHighPriority = problem.operators.any(
      (op) => op == Operator.multiply || op == Operator.divide,
    );
    final hasLowPriority = problem.operators.any(
      (op) => op == Operator.add || op == Operator.subtract,
    );

    if (problem.mode == ProblemMode.withBrackets &&
        problem.bracketRange != null) {
      steps.add(
        const SolutionStep(
          description: '先算括号里的',
          expression: '先算括号',
        ),
      );
    } else if (hasHighPriority && hasLowPriority) {
      steps.add(
        const SolutionStep(
          description: '先算乘除，后算加减',
          expression: '先乘除后加减',
        ),
      );
    }

    // 逐步计算
    final values = problem.operands.map((o) => o.asDouble).toList();
    final ops = List<Operator>.from(problem.operators);

    // 处理括号或优先级
    if (problem.bracketRange != null) {
      final br = problem.bracketRange!;
      var bracketResult = values[br.$1];
      for (var i = br.$1; i < br.$2 - 1 && i < ops.length; i++) {
        bracketResult = _applyOp(bracketResult, values[i + 1], ops[i]);
      }
      steps.add(
        SolutionStep(
          description: '括号内结果',
          expression: '= ${_formatNum(bracketResult)}',
          resultHint: _formatNum(bracketResult),
        ),
      );
    }

    steps.add(
      SolutionStep(
        description: '最终结果',
        expression: problem.problemText,
        resultHint: problem.answerText,
      ),
    );

    return steps;
  }

  static double _applyOp(double a, double b, Operator op) {
    switch (op) {
      case Operator.add:
        return a + b;
      case Operator.subtract:
        return a - b;
      case Operator.multiply:
        return a * b;
      case Operator.divide:
        return b != 0 ? a / b : 0;
    }
  }

  static String _formatNum(double n) {
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(2);
  }
}
