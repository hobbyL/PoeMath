// lib/math_engine/models/math_problem.dart
//
// 口算题目模型。

import 'number_value.dart';

/// 题目模式。
enum ProblemMode {
  /// 求结果：25 + 38 = ?
  findResult,

  /// 求未知项：25 + ? = 63
  findMissing,

  /// 比大小：25 + 38 ○ 70
  compare,

  /// 竖式计算
  vertical,

  /// 连续运算：3 + 5 - 2 = ?
  chain,

  /// 带括号运算：(3 + 5) × 2 = ?
  withBrackets,
}

/// 运算符。
enum Operator {
  add('+'),
  subtract('-'),
  multiply('×'),
  divide('÷');

  const Operator(this.symbol);
  final String symbol;

  @override
  String toString() => symbol;
}

/// 比大小的关系。
enum CompareRelation {
  greaterThan('>'),
  lessThan('<'),
  equal('=');

  const CompareRelation(this.symbol);
  final String symbol;
}

/// 结果形式。
enum ResultForm {
  /// 整数
  integer,

  /// 小数
  decimal,

  /// 分数
  fraction,

  /// 带余数（如 17 ÷ 5 = 3…2）
  withRemainder,
}

/// 口算题目。
class MathProblem {
  /// 操作数列表（至少 2 个）。
  final List<NumberValue> operands;

  /// 运算符列表（比操作数少 1）。
  final List<Operator> operators;

  /// 正确答案。
  final NumberValue result;

  /// 题目模式。
  final ProblemMode mode;

  /// 适用年级（1-6）。
  final int grade;

  /// 难度（1-5）。
  final int difficulty;

  /// 结果形式。
  final ResultForm resultForm;

  /// 未知项位置（仅 findMissing 模式使用，0-based 索引指向 operands）。
  final int? missingIndex;

  /// 余数（仅 withRemainder 形式使用）。
  final int? remainder;

  /// 比较关系（仅 compare 模式使用）。
  final CompareRelation? compareRelation;

  /// 比较目标值（仅 compare 模式使用）。
  final NumberValue? compareTarget;

  /// 括号范围（仅 withBrackets 模式使用）。
  /// 表示 [start, end) 的操作数索引区间。
  final (int, int)? bracketRange;

  const MathProblem({
    required this.operands,
    required this.operators,
    required this.result,
    required this.mode,
    required this.grade,
    this.difficulty = 1,
    this.resultForm = ResultForm.integer,
    this.missingIndex,
    this.remainder,
    this.compareRelation,
    this.compareTarget,
    this.bracketRange,
  });

  /// 生成题目文本。
  String get problemText {
    switch (mode) {
      case ProblemMode.findResult:
      case ProblemMode.vertical:
        return '${_expressionText()} = ?';
      case ProblemMode.findMissing:
        return _missingProblemText();
      case ProblemMode.compare:
        return '${_expressionText()} ○ $compareTarget';
      case ProblemMode.chain:
        return '${_expressionText()} = ?';
      case ProblemMode.withBrackets:
        return '${_bracketExpressionText()} = ?';
    }
  }

  /// 生成正确答案文本。
  String get answerText {
    if (mode == ProblemMode.compare) {
      return compareRelation?.symbol ?? '=';
    }
    if (resultForm == ResultForm.withRemainder) {
      return '${result.asInteger}…$remainder';
    }
    if (resultForm == ResultForm.fraction) {
      return result.toFractionString();
    }
    return result.toString();
  }

  String _expressionText() {
    final buffer = StringBuffer(operands[0].toString());
    for (var i = 0; i < operators.length; i++) {
      buffer.write(' ${operators[i].symbol} ${operands[i + 1]}');
    }
    return buffer.toString();
  }

  String _missingProblemText() {
    final buffer = StringBuffer();
    for (var i = 0; i < operands.length; i++) {
      if (i > 0) {
        buffer.write(' ${operators[i - 1].symbol} ');
      }
      if (i == missingIndex) {
        buffer.write('?');
      } else {
        buffer.write(operands[i].toString());
      }
    }
    buffer.write(' = $result');
    return buffer.toString();
  }

  String _bracketExpressionText() {
    final br = bracketRange;
    if (br == null) return _expressionText();

    final buffer = StringBuffer();
    for (var i = 0; i < operands.length; i++) {
      if (i > 0) {
        buffer.write(' ${operators[i - 1].symbol} ');
      }
      if (i == br.$1) buffer.write('(');
      buffer.write(operands[i].toString());
      if (i == br.$2 - 1) buffer.write(')');
    }
    return buffer.toString();
  }

  @override
  String toString() => problemText;
}
