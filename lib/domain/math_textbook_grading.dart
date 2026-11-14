import 'dart:convert';

import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

class MathTextbookEvaluation {
  MathTextbookEvaluation(this.result, Map<String, bool?> fields)
    : fields = Map.unmodifiable(fields);
  final MathTextbookResult result;
  final Map<String, bool?> fields;
  String get message => switch (result) {
    MathTextbookResult.correct => '答对了',
    MathTextbookResult.incorrect => '再核对一下答案和单位',
    MathTextbookResult.pendingParent => '作答已保存，请家长核对',
    MathTextbookResult.parentCorrect => '家长已确认完成',
    MathTextbookResult.parentAgain => '家长建议再练一次',
  };
}

bool mathTextbookAnswersComplete(
  MathTextbookExercise exercise,
  Map<String, String> answers,
) {
  if (answers.length != exercise.fields.length) return false;
  for (final field in exercise.fields) {
    final text = answers[field.id]?.trim() ?? '';
    if (text.isEmpty) return false;
    if (field.rule.kind == MathTextbookAnswerKind.remainder) {
      final values = text.replaceAll('余数', '…').replaceAll('余', '…').split('…');
      if (values.length != 2 || values.any((value) => value.trim().isEmpty)) {
        return false;
      }
    }
    if (field.rule.kind == MathTextbookAnswerKind.choice &&
        !field.rule.options.contains(text)) {
      try {
        final values = jsonDecode(text);
        if (values is! List ||
            values.isEmpty ||
            values.any((value) => value is! String || value.trim().isEmpty)) {
          return false;
        }
      } on FormatException {
        return false;
      }
    }
  }
  return true;
}

MathTextbookEvaluation gradeMathTextbookExercise(
  MathTextbookExercise exercise,
  Map<String, String> answers,
) {
  if (answers.length != exercise.fields.length ||
      exercise.fields.any((field) => !answers.containsKey(field.id))) {
    throw const FormatException('请完成本题全部作答项');
  }
  final fields = <String, bool?>{};
  for (final field in exercise.fields) {
    fields[field.id] = gradeMathTextbookAnswer(field.rule, answers[field.id]!);
  }
  return MathTextbookEvaluation(
    fields.values.any((v) => v == false)
        ? MathTextbookResult.incorrect
        : fields.values.any((v) => v == null)
        ? MathTextbookResult.pendingParent
        : MathTextbookResult.correct,
    fields,
  );
}

({String number, String unit}) splitMathTextbookNumberUnit(String input) {
  final text = input.trim();
  final suffixes = {
    ...MathTextbookUnits.values.keys,
    ...MathTextbookUnits.labels.values,
    for (final unit in MathTextbookUnits.values.keys)
      unit.replaceAll('²', '2').replaceAll('³', '3'),
  }.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final suffix in suffixes) {
    if (text.endsWith(suffix)) {
      return (
        number: text.substring(0, text.length - suffix.length).trim(),
        unit: MathTextbookUnits.normalize(suffix),
      );
    }
  }
  return (number: text, unit: '');
}

bool? gradeMathTextbookAnswer(MathTextbookAnswerRule rule, String input) {
  final answer = input.trim().replaceAll('−', '-');
  switch (rule.kind) {
    case MathTextbookAnswerKind.parent:
      return null;
    case MathTextbookAnswerKind.comparison:
      return answer == rule.expected;
    case MathTextbookAnswerKind.remainder:
      final parts = answer
          .replaceAll('余数', '…')
          .replaceAll('余', '…')
          .replaceAll(' ', '')
          .split('…');
      final correct = rule.expected.split('…');
      if (parts.length != 2 || correct.length != 2) return false;
      final q = int.tryParse(parts[0]), r = int.tryParse(parts[1]);
      return q != null &&
          r != null &&
          q >= 0 &&
          r >= 0 &&
          r < rule.divisor! &&
          q == int.parse(correct[0]) &&
          r == int.parse(correct[1]);
    case MathTextbookAnswerKind.choice:
      List<String> values;
      if (rule.options.contains(answer)) {
        values = [answer];
      } else {
        try {
          final raw = jsonDecode(answer);
          if (raw is! List || raw.any((v) => v is! String)) return false;
          values = raw.cast<String>();
        } on Object {
          return false;
        }
      }
      return values.toSet().length == values.length &&
          values.length == rule.correctChoices.length &&
          values.every(rule.correctChoices.contains);
    case MathTextbookAnswerKind.number:
    case MathTextbookAnswerKind.expression:
      final parts = splitMathTextbookNumberUnit(answer);
      if (!_representation(parts.number, rule.form)) return false;
      final actual = rule.kind == MathTextbookAnswerKind.expression
          ? evaluateMathTextbookExpression(parts.number)
          : MathTextbookAnswerRule.numberValue(parts.number);
      final expected = MathTextbookAnswerRule.numberValue(rule.expected);
      if (actual == null || expected == null) return false;
      if (rule.unit.isEmpty) return parts.unit.isEmpty && actual == expected;
      final from = MathTextbookUnits.values[parts.unit],
          to = MathTextbookUnits.values[rule.unit];
      if (from == null ||
          to == null ||
          from.dimension != to.dimension ||
          !rule.allowUnitConversion && parts.unit != rule.unit) {
        return false;
      }
      final a = actual.asFraction, e = expected.asFraction;
      return BigInt.from(a.numerator) *
              BigInt.from(from.n) *
              BigInt.from(e.denominator) *
              BigInt.from(to.d) ==
          BigInt.from(e.numerator) *
              BigInt.from(to.n) *
              BigInt.from(a.denominator) *
              BigInt.from(from.d);
  }
}

bool _representation(String value, MathTextbookNumberForm form) {
  final text = value.trim();
  switch (form) {
    case MathTextbookNumberForm.any:
      return true;
    case MathTextbookNumberForm.integer:
      return RegExp(r'^[+-]?\d+$').hasMatch(text);
    case MathTextbookNumberForm.decimal:
      return RegExp(r'^[+-]?(?:\d+\.\d+|\.\d+)$').hasMatch(text);
    case MathTextbookNumberForm.percentage:
      return text.endsWith('%') || text.endsWith('％');
    case MathTextbookNumberForm.mixedNumber:
      final match = RegExp(r'^([+-]?\d+)\s+(\d+)/(\d+)$').firstMatch(text);
      if (match == null) return false;
      final whole = BigInt.parse(match.group(1)!),
          n = BigInt.parse(match.group(2)!),
          d = BigInt.parse(match.group(3)!);
      return whole != BigInt.zero &&
          n > BigInt.zero &&
          n < d &&
          n.gcd(d) == BigInt.one;
    case MathTextbookNumberForm.fraction:
    case MathTextbookNumberForm.simplestFraction:
      final match = RegExp(r'^([+-]?\d+)\s*/\s*(\d+)$').firstMatch(text);
      if (match == null) return false;
      final n = BigInt.parse(match.group(1)!),
          d = BigInt.parse(match.group(2)!);
      return d > BigInt.zero &&
          (form != MathTextbookNumberForm.simplestFraction ||
              n.gcd(d) == BigInt.one);
  }
}

/// 有界的四则、括号、百分数、平方/立方及 x=数值输入，不执行字符串代码。
NumberValue? evaluateMathTextbookExpression(String input) {
  if (input.length > 512) return null;
  final direct = MathTextbookAnswerRule.numberValue(input);
  if (direct != null) return direct;
  final text = input
      .trim()
      .replaceAll('×', '*')
      .replaceAll('÷', '/')
      .replaceAll('−', '-');
  final equation = text.split('=');
  if (equation.length > 2) return null;
  try {
    final result = _ExpressionParser(equation.last).parse();
    if (equation.length == 2 &&
        !const ['x', 'X', '□'].contains(equation.first.trim())) {
      final left = _ExpressionParser(equation.first).parse();
      if (left.n * result.d != result.n * left.d) return null;
    }
    final max = BigInt.from(9007199254740991);
    if (result.n.abs() > max || result.d > max) return null;
    return NumberValue.fromFraction(result.n.toInt(), result.d.toInt());
  } on Object {
    return null;
  }
}

class _Rational {
  _Rational(BigInt numerator, BigInt denominator) {
    if (denominator == BigInt.zero) throw const FormatException('除数为零');
    final gcd = numerator.gcd(denominator);
    n = numerator ~/ gcd;
    d = denominator ~/ gcd;
    if (d < BigInt.zero) {
      n = -n;
      d = -d;
    }
    if (n.bitLength > 256 || d.bitLength > 256) {
      throw const FormatException('算式超出范围');
    }
  }
  late BigInt n, d;
  _Rational add(_Rational b) => _Rational(n * b.d + b.n * d, d * b.d);
  _Rational subtract(_Rational b) => _Rational(n * b.d - b.n * d, d * b.d);
  _Rational multiply(_Rational b) => _Rational(n * b.n, d * b.d);
  _Rational divide(_Rational b) => _Rational(n * b.d, d * b.n);
}

class _ExpressionParser {
  _ExpressionParser(String input) : text = _expressionText(input);
  final String text;
  int index = 0, depth = 0, nodes = 0;
  _Rational parse() {
    final value = _sum();
    if (index != text.length) throw const FormatException('算式有未支持内容');
    return value;
  }

  bool _take(String token) {
    if (text.startsWith(token, index)) {
      index += token.length;
      return true;
    }
    return false;
  }

  _Rational _sum() {
    var value = _product();
    while (index < text.length) {
      if (_take('+')) {
        value = value.add(_product());
      } else if (_take('-')) {
        value = value.subtract(_product());
      } else {
        break;
      }
    }
    return value;
  }

  _Rational _product() {
    var value = _atom();
    while (index < text.length) {
      if (_take('*')) {
        value = value.multiply(_atom());
      } else if (_take('/')) {
        value = value.divide(_atom());
      } else {
        break;
      }
    }
    return value;
  }

  _Rational _atom() {
    if (++depth > 16 || ++nodes > 128) throw const FormatException('算式过长');
    try {
      if (_take('+')) return _atom();
      if (_take('-')) {
        final v = _atom();
        return _Rational(-v.n, v.d);
      }
      _Rational value;
      if (_take('(')) {
        value = _sum();
        if (!_take(')')) throw const FormatException('括号不完整');
      } else {
        final match = RegExp(r'(?:\d+(?:\.\d+)?|\.\d+)')
            .matchAsPrefix(text, index);
        if (match == null) throw const FormatException('缺少数值');
        index = match.end;
        final parsed = MathEngine.parseAnswer(match.group(0)!);
        if (parsed == null) throw const FormatException('数值超出范围');
        final f = parsed.asFraction;
        value = _Rational(BigInt.from(f.numerator), BigInt.from(f.denominator));
      }
      if (_take('%') || _take('％')) {
        value = value.divide(_Rational(BigInt.from(100), BigInt.one));
      }
      if (_take('²')) {
        value = value.multiply(value);
      } else if (_take('³')) {
        value = value.multiply(value).multiply(value);
      } else if (_take('^')) {
        if (_take('2')) {
          value = value.multiply(value);
        } else if (_take('3')) {
          value = value.multiply(value).multiply(value);
        } else {
          throw const FormatException('仅支持平方或立方');
        }
      }
      return value;
    } finally {
      depth--;
    }
  }
}

String _expressionText(String input) {
  // 空格可分隔带分数，不能直接删掉后把 1 1/2 解释为 11/2。
  final mixed = input.replaceAllMapped(
    RegExp(r'(?<![\d.])([+-]?\d+)\s+(\d+)\s*/\s*(\d+)'),
    (match) {
      final number = MathEngine.parseAnswer(
        '${match[1]} ${match[2]}/${match[3]}',
      );
      if (number == null) throw const FormatException('带分数无效');
      final fraction = number.asFraction;
      return '(${fraction.numerator}/${fraction.denominator})';
    },
  );
  if (RegExp(r'\d\s+\d').hasMatch(mixed)) {
    throw const FormatException('数值之间缺少运算符');
  }
  return mixed.replaceAll(RegExp(r'\s+'), '');
}
