// lib/math_engine/diagnostics/mistake_rule.dart
//
// 错因诊断规则接口与 6 类具体规则。

import '../models/answer_judgement.dart';
import '../models/math_problem.dart';
import '../models/number_value.dart';

/// 错因规则抽象接口。
abstract class MistakeRule {
  /// 规则名称。
  String get name;

  /// 判断此规则是否匹配给定的错误。
  bool matches(MathProblem problem, NumberValue wrongAnswer);

  /// 生成诊断描述。
  MistakeDiagnosis describe(MathProblem problem);
}

// ============ 6 类具体规则 ============

/// 进位遗漏：正确答案比学生答案大 10 的倍数。
class CarryOmissionRule implements MistakeRule {
  @override
  String get name => 'carry_omission';

  @override
  bool matches(MathProblem problem, NumberValue wrongAnswer) {
    if (!problem.operators.contains(Operator.add)) return false;
    final correct = problem.result.asInteger;
    final wrong = wrongAnswer.asInteger;
    final diff = correct - wrong;
    return diff > 0 && diff % 10 == 0 && diff <= 100;
  }

  @override
  MistakeDiagnosis describe(MathProblem problem) {
    return const MistakeDiagnosis(
      category: 'carry_omission',
      template: '个位相加超过10，需要向十位进1。记住：满十进一！',
    );
  }
}

/// 退位遗漏：学生答案比正确答案大 10 的倍数。
class BorrowOmissionRule implements MistakeRule {
  @override
  String get name => 'borrow_omission';

  @override
  bool matches(MathProblem problem, NumberValue wrongAnswer) {
    if (!problem.operators.contains(Operator.subtract)) return false;
    final correct = problem.result.asInteger;
    final wrong = wrongAnswer.asInteger;
    final diff = wrong - correct;
    return diff > 0 && diff % 10 == 0 && diff <= 100;
  }

  @override
  MistakeDiagnosis describe(MathProblem problem) {
    return const MistakeDiagnosis(
      category: 'borrow_omission',
      template: '个位不够减，需要从十位借1当10。记住：借一当十！',
    );
  }
}

/// 乘法口诀错误：对比乘法表。
class MultiplicationTableRule implements MistakeRule {
  @override
  String get name => 'multiplication_table';

  @override
  bool matches(MathProblem problem, NumberValue wrongAnswer) {
    if (!problem.operators.contains(Operator.multiply)) return false;
    if (problem.operands.length != 2) return false;

    final a = problem.operands[0].asInteger;
    final b = problem.operands[1].asInteger;

    // 只检查口诀范围（1-9 × 1-9）
    if (a < 1 || a > 9 || b < 1 || b > 9) return false;

    final correct = a * b;
    final wrong = wrongAnswer.asInteger;
    return wrong != correct;
  }

  @override
  MistakeDiagnosis describe(MathProblem problem) {
    final a = problem.operands[0].asInteger;
    final b = problem.operands[1].asInteger;
    final correct = a * b;
    return MistakeDiagnosis(
      category: 'multiplication_table',
      template: '口诀：{a}×{b}={correct}。多背几遍：{small}×{big}={correct}',
      params: {
        'a': '$a',
        'b': '$b',
        'correct': '$correct',
        'small': '${a < b ? a : b}',
        'big': '${a > b ? a : b}',
      },
    );
  }
}

/// 运算顺序错误：混合运算中先加减后乘除。
class OperationOrderRule implements MistakeRule {
  @override
  String get name => 'operation_order';

  @override
  bool matches(MathProblem problem, NumberValue wrongAnswer) {
    if (problem.operators.length < 2) return false;

    final hasMixed = problem.operators.any(
          (op) => op == Operator.multiply || op == Operator.divide,
        ) &&
        problem.operators.any(
          (op) => op == Operator.add || op == Operator.subtract,
        );

    if (!hasMixed) return false;

    // 计算从左到右的结果（不考虑优先级）
    final leftToRight = _evaluateLeftToRight(
      problem.operands.map((o) => o.asInteger).toList(),
      problem.operators,
    );

    return wrongAnswer.asInteger == leftToRight &&
        leftToRight != problem.result.asInteger;
  }

  int _evaluateLeftToRight(List<int> values, List<Operator> ops) {
    var result = values[0];
    for (var i = 0; i < ops.length; i++) {
      switch (ops[i]) {
        case Operator.add:
          result += values[i + 1];
        case Operator.subtract:
          result -= values[i + 1];
        case Operator.multiply:
          result *= values[i + 1];
        case Operator.divide:
          if (values[i + 1] != 0) result ~/= values[i + 1];
      }
    }
    return result;
  }

  @override
  MistakeDiagnosis describe(MathProblem problem) {
    return const MistakeDiagnosis(
      category: 'operation_order',
      template: '混合运算要先算乘除，后算加减。有括号的先算括号里的！',
    );
  }
}

/// 余数错误：余数 ≥ 除数。
class RemainderMistakeRule implements MistakeRule {
  @override
  String get name => 'remainder_mistake';

  @override
  bool matches(MathProblem problem, NumberValue wrongAnswer) {
    if (problem.resultForm != ResultForm.withRemainder) return false;
    // 简化判断：答案不正确即可
    return wrongAnswer.asInteger != problem.result.asInteger;
  }

  @override
  MistakeDiagnosis describe(MathProblem problem) {
    final divisor = problem.operands[1].asInteger;
    return MistakeDiagnosis(
      category: 'remainder_mistake',
      template: '余数必须比除数（{divisor}）小！检查一下商是否正确。',
      params: {'divisor': '$divisor'},
    );
  }
}

/// 小数点位置错误。
class DecimalAlignmentRule implements MistakeRule {
  @override
  String get name => 'decimal_alignment';

  @override
  bool matches(MathProblem problem, NumberValue wrongAnswer) {
    if (problem.resultForm != ResultForm.decimal) return false;

    final correct = problem.result.asDouble;
    final wrong = wrongAnswer.asDouble;

    if (correct == 0 || wrong == 0) return false;

    // 检查是否是 10 倍或 0.1 倍的关系
    final ratio = wrong / correct;
    return (ratio == 10 || ratio == 0.1 || ratio == 100 || ratio == 0.01);
  }

  @override
  MistakeDiagnosis describe(MathProblem problem) {
    return const MistakeDiagnosis(
      category: 'decimal_alignment',
      template: '小数运算要注意小数点的位置！加减法要小数点对齐，乘法要数小数位数。',
    );
  }
}

/// 错因诊断器：遍历所有规则，返回首个匹配的诊断。
class MistakeDiagnoser {
  static final List<MistakeRule> _rules = [
    CarryOmissionRule(),
    BorrowOmissionRule(),
    MultiplicationTableRule(),
    OperationOrderRule(),
    RemainderMistakeRule(),
    DecimalAlignmentRule(),
  ];

  const MistakeDiagnoser._();

  /// 诊断错误原因。
  static MistakeDiagnosis? diagnose(
    MathProblem problem,
    NumberValue wrongAnswer,
  ) {
    for (final rule in _rules) {
      if (rule.matches(problem, wrongAnswer)) {
        return rule.describe(problem);
      }
    }
    return null;
  }
}
