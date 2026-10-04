// lib/math_engine/step_solver/step_solver.dart
//
// 分步解答生成器：为每道题生成面向小学生的自然语言解题步骤。

import '../models/answer_judgement.dart';
import '../models/math_problem.dart';
import '../models/number_value.dart';
import '../validators/expression_evaluator.dart';

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
    // findMissing 模式下 result 是答案(缺失项)，需要用 expressionResult 做解题步骤
    final exprResult = problem.expressionResult ?? problem.result;
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
            description: '所以 $a + $b = $exprResult',
            expression: '$a + $b = $exprResult',
            resultHint: '$exprResult',
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
            description: '所以 $a - $b = $exprResult',
            expression: '$a - $b = $exprResult',
            resultHint: '$exprResult',
          ),
        );

      case Operator.multiply:
        steps.add(
          SolutionStep(
            description: '计算 $a × $b',
            expression: '$a × $b = $exprResult',
            resultHint: '$exprResult',
          ),
        );

      case Operator.divide:
        if (problem.resultForm == ResultForm.withRemainder) {
          final dividend = a.asInteger;
          final divisor = b.asInteger;
          final quotient = exprResult.asInteger;
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
              expression: '$a ÷ $b = $exprResult',
              resultHint: '$exprResult',
            ),
          );
        }
    }

    return steps;
  }

  static List<SolutionStep> _solveMultiOp(MathProblem problem) {
    final steps = <SolutionStep>[];
    final isBracket = problem.mode == ProblemMode.withBrackets &&
        problem.bracketRange != null;
    final hasHighPriority = problem.operators.any(
      (op) => op == Operator.multiply || op == Operator.divide,
    );
    final hasLowPriority = problem.operators.any(
      (op) => op == Operator.add || op == Operator.subtract,
    );

    if (isBracket) {
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

    // 逐步计算（复用 ExpressionEvaluator 的精确折叠序列，
    // 中间值为 Fraction 精确数值，无 double 截断）
    final trace = ExpressionEvaluator.evaluateWithSteps(
      problem.operands,
      problem.operators,
      bracketRange: problem.bracketRange,
    );
    if (trace == null) {
      // 除零等极端情况：至少给出最终结果
      steps.add(
        SolutionStep(
          description: '最终结果',
          expression: problem.problemText,
          resultHint: problem.answerText,
        ),
      );
      return steps;
    }

    for (final step in trace.steps) {
      final text = _formatFraction(step.value);
      steps.add(
        SolutionStep(
          description: '${step.expression} = $text',
          expression: '${step.expression} = $text',
          resultHint: text,
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

  /// 精确数值格式化：整数直接输出，分数用假分数形态。
  static String _formatFraction(Fraction v) =>
      v.isInteger ? v.asInteger.toString() : v.toImproperString();
}
