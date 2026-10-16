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

  /// 原始表达式计算结果（仅 findMissing 模式使用）。
  /// 例如 2 - 2 = 0 求第二项，result=2(答案)，expressionResult=0(等号右边)。
  final NumberValue? expressionResult;

  /// 余数（仅 withRemainder 形式使用）。
  final int? remainder;

  /// 比较关系（仅 compare 模式使用）。
  final CompareRelation? compareRelation;

  /// 比较目标值（仅 compare 模式使用）。
  final NumberValue? compareTarget;

  /// 括号范围（包括转换后的比较、挖空和求值题）。
  /// 表示 [start, end) 的操作数索引区间。
  final (int, int)? bracketRange;

  /// 题面显示覆盖（如 '80 × 30% = ?'、'3 : 4 = 24 : ?'、'1/2 + 1/3 = ?'）。
  /// null 时按 mode 自动渲染。内部运算结构（operands/operators/result）不变，
  /// 判分/讲解仍按内部结构运算（与显示语义数学等价）。
  final String? displayText;
  final String? skillId;
  final String? semester;

  const MathProblem({
    required this.operands,
    required this.operators,
    required this.result,
    required this.mode,
    required this.grade,
    this.difficulty = 1,
    this.resultForm = ResultForm.integer,
    this.missingIndex,
    this.expressionResult,
    this.remainder,
    this.compareRelation,
    this.compareTarget,
    this.bracketRange,
    this.displayText,
    this.skillId,
    this.semester,
  });

  MathProblem withContext(
          {required String skillId, required String semester,}) =>
      MathProblem(
        operands: operands,
        operators: operators,
        result: result,
        mode: mode,
        grade: grade,
        difficulty: difficulty,
        resultForm: resultForm,
        missingIndex: missingIndex,
        expressionResult: expressionResult,
        remainder: remainder,
        compareRelation: compareRelation,
        compareTarget: compareTarget,
        bracketRange: bracketRange,
        displayText: displayText,
        skillId: skillId,
        semester: semester,
      );

  static Map<String, int> _encodeNumber(NumberValue n) => {
        'n': n.asFraction.numerator,
        'd': n.asFraction.denominator,
      };

  static NumberValue _decodeNumber(Object? value) {
    final map = value as Map<String, dynamic>;
    final n = map['n'] as int;
    final d = map['d'] as int;
    if (d <= 0 || n.abs() > 9007199254740991 || d > 9007199254740991) {
      throw const FormatException('题目数值无效');
    }
    return NumberValue.fromFraction(n, d);
  }

  Map<String, dynamic> toJson() => {
        'operands': operands.map(_encodeNumber).toList(),
        'operators': operators.map((o) => o.name).toList(),
        'result': _encodeNumber(result),
        'mode': mode.name,
        'grade': grade,
        'difficulty': difficulty,
        'resultForm': resultForm.name,
        'missingIndex': missingIndex,
        'expressionResult':
            expressionResult == null ? null : _encodeNumber(expressionResult!),
        'remainder': remainder,
        'compareRelation': compareRelation?.name,
        'compareTarget':
            compareTarget == null ? null : _encodeNumber(compareTarget!),
        'bracketRange':
            bracketRange == null ? null : [bracketRange!.$1, bracketRange!.$2],
        'displayText': displayText,
        'skillId': skillId,
        'semester': semester,
      };

  factory MathProblem.fromJson(Map<String, dynamic> json) {
    final operands =
        (json['operands'] as List<dynamic>).map(_decodeNumber).toList();
    final operators = (json['operators'] as List<dynamic>)
        .map((v) => Operator.values.byName(v as String))
        .toList();
    final grade = json['grade'] as int;
    final bracket = json['bracketRange'] as List<dynamic>?;
    final missing = json['missingIndex'] as int?;
    final semester = json['semester'] as String?;
    if (operands.length < 2 ||
        operands.length > 8 ||
        operators.length != operands.length - 1 ||
        grade < 1 ||
        grade > 6 ||
        (semester != null && semester != '上' && semester != '下') ||
        (missing != null && (missing < 0 || missing >= operands.length)) ||
        (bracket != null &&
            (bracket.length != 2 ||
                bracket[0] is! int ||
                bracket[1] is! int ||
                (bracket[0] as int) < 0 ||
                (bracket[1] as int) > operands.length ||
                (bracket[0] as int) >= (bracket[1] as int)))) {
      throw const FormatException('题目结构无效');
    }
    return MathProblem(
      operands: operands,
      operators: operators,
      result: _decodeNumber(json['result']),
      mode: ProblemMode.values.byName(json['mode'] as String),
      grade: grade,
      difficulty: json['difficulty'] as int? ?? 1,
      resultForm: ResultForm.values.byName(json['resultForm'] as String),
      missingIndex: missing,
      expressionResult: json['expressionResult'] == null
          ? null
          : _decodeNumber(json['expressionResult']),
      remainder: json['remainder'] as int?,
      compareRelation: json['compareRelation'] == null
          ? null
          : CompareRelation.values.byName(json['compareRelation'] as String),
      compareTarget: json['compareTarget'] == null
          ? null
          : _decodeNumber(json['compareTarget']),
      bracketRange:
          bracket == null ? null : (bracket[0] as int, bracket[1] as int),
      displayText: json['displayText'] as String?,
      skillId: json['skillId'] as String?,
      semester: semester,
    );
  }

  /// 根据实际待答值推导输入形态，模式转换后不能沿用原结果形态。
  static ResultForm formFor(NumberValue value) => value.isInteger
      ? ResultForm.integer
      : value.toString().contains('/')
          ? ResultForm.fraction
          : ResultForm.decimal;

  /// 生成题目文本。
  String get problemText {
    // 显示覆盖优先（百分数/比例/分数等专题形态）
    final override = displayText;
    if (override != null) return override;
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
    return _renderExpression();
  }

  String _missingProblemText() {
    final rhs = expressionResult ?? result;
    return '${_renderExpression(hideMissing: true)} = $rhs';
  }

  String _renderExpression({bool hideMissing = false}) {
    final buffer = StringBuffer();
    for (var i = 0; i < operands.length; i++) {
      if (i > 0) {
        buffer.write(' ${operators[i - 1].symbol} ');
      }
      if (i == bracketRange?.$1) buffer.write('(');
      if (hideMissing && i == missingIndex) {
        buffer.write('?');
      } else {
        buffer.write(operands[i].toString());
      }
      if (i == (bracketRange?.$2 ?? 0) - 1) buffer.write(')');
    }
    return buffer.toString();
  }

  String _bracketExpressionText() {
    return _renderExpression();
  }

  @override
  String toString() => problemText;
}
