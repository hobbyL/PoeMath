// tools/bracket_audit.dart
//
// 口算引擎全学期回归审计脚本（R9）。
//
// 断言内容：
//   1. 每题按「显示语义」独立求值（脚本自带的第二份参考实现，
//      与生产 ExpressionEvaluator 独立编写，双实现互证）== result；
//   2. withBrackets 题逐步除法整除（中间值全整数）；
//   3. 6a/6b 乘除分布不退化（被乘数 ≥ 10 个不同值、商=1 占比 < 10%）；
//   4. 百分数/比例/分数题面形态（含 '%'、' : '、分数斜杠）；
//   5. 全部题目通过 ConstraintChecker。
//
// 任一断言失败输出明细并以非零退出码结束。
//
// 运行：dart run tools/bracket_audit.dart
// （FVM 环境：~/.pub-cache/bin/fvm dart run tools/bracket_audit.dart）

import 'dart:io' show exitCode;
import 'dart:math';

import 'package:poemath/math_engine/math_engine_api.dart';

const sampleCount = 3000;

void main() {
  var failed = false;

  for (final config in GradePresets.all) {
    failed = !_auditSemester(config) || failed;
  }

  if (failed) {
    print('\n==== 审计失败：存在不一致或退化分布 ====');
    exitCode = 1;
  } else {
    print('\n==== 审计通过：12 学期全部 0 一致性错误 ====');
  }
}

bool _auditSemester(GradeConfig config) {
  var consistencyErrors = 0;
  var bracketDivErrors = 0;
  var checkerViolations = 0;
  var bracketCount = 0;
  final samples = <String>[];

  // 分布统计（6a/6b）
  final multiplicands = <int>{};
  var mulTotal = 0;
  var divTotal = 0;
  var quotientOne = 0;

  // 形态统计
  var percentForm = 0;
  var ratioForm = 0;
  var fractionForm = 0;

  for (var i = 0; i < sampleCount; i++) {
    final p = MathEngine.generate(
      grade: config.grade,
      semester: config.semester,
      random: Random(config.grade * 100000 + config.semester.codeUnitAt(0) + i),
    );

    // 5. 约束校验
    final violation = ConstraintChecker.check(p, config);
    if (violation != null) {
      checkerViolations++;
      if (samples.length < 8) {
        samples.add('[checker] ${p.problemText} → $violation');
      }
    }

    // 1. 显示语义独立求值 == result
    //    （findMissing 题 result 是缺失项答案，显示语义对应 expressionResult；
    //     有余数除法按「除数×商+余数=被除数」验算）
    final allIntOperands = p.operands.every((o) => o.isInteger);
    final intermediates = <_Rat>[];
    final expected = _refEvaluate(p.operands, p.operators,
        bracketRange: p.bracketRange, intermediates: intermediates);
    if (p.resultForm == ResultForm.withRemainder) {
      final dividend = p.operands[0].asInteger;
      final divisor = p.operands[1].asInteger;
      final quotient = p.result.asInteger;
      final remainder = p.remainder ?? 0;
      if (divisor * quotient + remainder != dividend ||
          remainder < 0 ||
          remainder >= divisor) {
        consistencyErrors++;
        if (samples.length < 8) {
          samples.add('[余数] ${p.problemText} 验算失败 '
              '($divisor×$quotient+$remainder ≠ $dividend)');
        }
      }
    } else {
      final expectedTarget = (p.expressionResult ?? p.result).asFraction;
      if (expected == null || !expected.equalsFraction(expectedTarget)) {
        consistencyErrors++;
        if (samples.length < 8) {
          samples.add('[一致] ${p.problemText} 参考求值='
              '${expected?.toString() ?? 'null'} 引擎判分=${p.answerText}');
        }
      }
    }

    // 2. withBrackets 除法整除（整数操作数题的中间值全整数）
    if (p.mode == ProblemMode.withBrackets) {
      bracketCount++;
      if (allIntOperands &&
          !intermediates.every((r) => r.denominator == 1)) {
        bracketDivErrors++;
        if (samples.length < 8) {
          samples.add('[括号整除] ${p.problemText} 中间值含分数');
        }
      }
    }

    // 3. 6a/6b 分布
    if (config.grade == 6) {
      if (p.operators.length == 1 && p.operators[0] == Operator.multiply) {
        if (allIntOperands) {
          mulTotal++;
          multiplicands.add(p.operands[0].asInteger);
        }
      } else if (p.operators.length == 1 &&
          p.operators[0] == Operator.divide) {
        divTotal++;
        if (p.result.asInteger == 1) quotientOne++;
      }
    }

    // 4. 形态
    if (p.problemText.contains('%')) percentForm++;
    if (p.problemText.contains(' : ')) ratioForm++;
    if (p.resultForm == ResultForm.fraction) {
      fractionForm++;
      // 分数题面不得混入小数形态（如 1/2 显示为 0.5）；
      // 整数值操作数（如 1/1 简化为 1）显示为整数是正确行为。
      if (RegExp(r'\d\.\d').hasMatch(p.problemText)) {
        consistencyErrors++;
        if (samples.length < 8) {
          samples.add('[分数形态] ${p.problemText} 混入小数形态');
        }
      }
    }
  }

  // 输出统计
  final buf = StringBuffer()
    ..write('${config.label}: 一致性错误=$consistencyErrors'
        ' checker违规=$checkerViolations 括号题=$bracketCount'
        ' 括号整除错误=$bracketDivErrors')
    ..write(' 百分数=$percentForm 比例=$ratioForm 分数=$fractionForm');
  if (config.grade == 6) {
    final q1Rate = divTotal == 0 ? 0.0 : quotientOne / divTotal;
    buf.write(' | 乘法题=$mulTotal 被乘数不同值=${multiplicands.length}'
        ' 除法题=$divTotal 商=1占比=${(q1Rate * 100).toStringAsFixed(1)}%');
  }
  print(buf);

  var ok = true;
  for (final s in samples) {
    print('   $s');
    ok = false;
  }

  if (consistencyErrors > 0 || checkerViolations > 0 || bracketDivErrors > 0) {
    ok = false;
  }

  // 6a/6b 分布退化断言
  if (config.grade == 6) {
    if (mulTotal > 20 && multiplicands.length < 10) {
      print('   [退化] ${config.label} 被乘数仅 ${multiplicands.length} 个不同值');
      ok = false;
    }
    if (multiplicands.length == 1 && multiplicands.contains(10)) {
      print('   [退化] ${config.label} 被乘数恒为 10');
      ok = false;
    }
    if (divTotal > 20 && quotientOne / divTotal >= 0.10) {
      print('   [退化] ${config.label} 除法商=1 占比 ≥ 10%');
      ok = false;
    }
  }

  // 学期专题形态存在性（题量充足时应出现）
  if (config.grade == 6 && config.semester == '上' && percentForm == 0) {
    print('   [形态缺失] 六年级上未出现百分数形态');
    ok = false;
  }
  if (config.grade == 6 && config.semester == '下' && ratioForm == 0) {
    print('   [形态缺失] 六年级下未出现比例形态');
    ok = false;
  }
  if (config.allowFraction && fractionForm == 0) {
    print('   [形态缺失] ${config.label} 未出现分数题');
    ok = false;
  }

  return ok;
}

// ============================================================
// 独立参考实现（与生产 ExpressionEvaluator 分开编写，双实现互证）
// 采用 shunting-yard 双栈即时求值算法（与生产的分阶段折叠不同结构）。
// ============================================================

/// 独立的有理数实现。
class _Rat {
  final int numerator;
  final int denominator;

  _Rat._(this.numerator, this.denominator);

  factory _Rat(int n, int d) {
    if (d == 0) throw const _DivZero();
    if (d < 0) {
      n = -n;
      d = -d;
    }
    var a = n.abs();
    var b = d;
    while (b != 0) {
      final t = a % b;
      a = b;
      b = t;
    }
    final g = a == 0 ? 1 : a;
    return _Rat._(n ~/ g, d ~/ g);
  }

  _Rat plus(_Rat o) => _Rat(numerator * o.denominator + o.numerator * denominator,
      denominator * o.denominator);

  _Rat minus(_Rat o) =>
      _Rat(numerator * o.denominator - o.numerator * denominator,
          denominator * o.denominator);

  _Rat times(_Rat o) => _Rat(numerator * o.numerator, denominator * o.denominator);

  /// 除零抛出，由调用方转为 null。
  _Rat div(_Rat o) => _Rat(numerator * o.denominator, denominator * o.numerator);

  bool equalsFraction(Fraction f) =>
      numerator * f.denominator == f.numerator * denominator;

  @override
  String toString() => denominator == 1
      ? '$numerator'
      : '$numerator/$denominator';
}

class _DivZero implements Exception {
  const _DivZero();
}

_Rat? _refEvaluate(
  List<NumberValue> operands,
  List<Operator> operators, {
  (int, int)? bracketRange,
  required List<_Rat> intermediates,
}) {
  // 构造 token 序列：_Rat / '(' / ')' / 运算符 symbol
  final tokens = <Object>[];
  final br = bracketRange;
  for (var i = 0; i < operands.length; i++) {
    if (br != null && i == br.$1) tokens.add('(');
    final f = operands[i].asFraction;
    tokens.add(_Rat(f.numerator, f.denominator));
    if (br != null && i == br.$2 - 1) tokens.add(')');
    if (i < operators.length) tokens.add(operators[i].symbol);
  }

  final valStack = <_Rat>[];
  final opStack = <String>[];

  try {
    for (final t in tokens) {
      if (t is _Rat) {
        valStack.add(t);
      } else if (t == '(') {
        opStack.add('(');
      } else if (t == ')') {
        while (opStack.isNotEmpty && opStack.last != '(') {
          _reduce(valStack, opStack, intermediates);
        }
        if (opStack.isEmpty) return null;
        opStack.removeLast();
      } else if (t is String) {
        while (opStack.isNotEmpty &&
            opStack.last != '(' &&
            _prec(opStack.last) >= _prec(t)) {
          _reduce(valStack, opStack, intermediates);
        }
        opStack.add(t);
      }
    }
    while (opStack.isNotEmpty) {
      if (opStack.last == '(') return null;
      _reduce(valStack, opStack, intermediates);
    }
  } on _DivZero {
    return null;
  }

  return valStack.length == 1 ? valStack.first : null;
}

void _reduce(List<_Rat> vals, List<String> ops, List<_Rat> intermediates) {
  final op = ops.removeLast();
  final b = vals.removeLast();
  final a = vals.removeLast();
  final r = switch (op) {
    '+' => a.plus(b),
    '-' => a.minus(b),
    '×' => a.times(b),
    _ => a.div(b),
  };
  intermediates.add(r);
  vals.add(r);
}

int _prec(String op) => (op == '×' || op == '÷') ? 2 : 1;
