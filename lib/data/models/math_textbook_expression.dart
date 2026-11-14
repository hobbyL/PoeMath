part of 'math_textbook_course.dart';

/// 保存确定的数学结构；未识别的公式保留原书区域，不伪造表达式。
sealed class MathTextbookExpression {
  const MathTextbookExpression();
  Map<String, dynamic> toJson();
  String get latex;
  String get readable;

  factory MathTextbookExpression.fromJson(Object? value) =>
      _expression(value, 0);
}

class MathTextbookAtom extends MathTextbookExpression {
  const MathTextbookAtom(this.value);
  final String value;
  @override
  Map<String, dynamic> toJson() => {'kind': 'atom', 'value': value};
  @override
  String get readable => value;
  @override
  String get latex => switch (value) {
    '×' => r'\times ',
    '÷' => r'\div ',
    '≤' => r'\le ',
    '≥' => r'\ge ',
    '%' => r'\%',
    '−' => '-',
    _ => RegExp(r'^[a-zA-Z]+$').hasMatch(value) ? '\\mathrm{$value}' : value,
  };
}

class MathTextbookFraction extends MathTextbookExpression {
  const MathTextbookFraction(this.numerator, this.denominator);
  final String numerator;
  final String denominator;
  @override
  Map<String, dynamic> toJson() => {
    'kind': 'fraction',
    'numerator': numerator,
    'denominator': denominator,
  };
  @override
  String get latex => '\\frac{$numerator}{$denominator}';
  @override
  String get readable => '$numerator/$denominator';
}

class MathTextbookMixedNumber extends MathTextbookExpression {
  const MathTextbookMixedNumber(this.integer, this.fraction);
  final String integer;
  final MathTextbookFraction fraction;
  @override
  Map<String, dynamic> toJson() => {
    'kind': 'mixedNumber',
    'integer': integer,
    'fraction': fraction.toJson(),
  };
  @override
  String get latex => '$integer${fraction.latex}';
  @override
  String get readable => '$integer 又 ${fraction.readable}';
}

class MathTextbookPower extends MathTextbookExpression {
  const MathTextbookPower(this.base, this.exponent);
  final String base;
  final int exponent;
  @override
  Map<String, dynamic> toJson() => {
    'kind': 'power',
    'base': base,
    'exponent': exponent,
  };
  @override
  String get latex => '\\mathrm{$base}^{$exponent}';
  @override
  String get readable => '$base${exponent == 2 ? '²' : '³'}';
}

class MathTextbookSequence extends MathTextbookExpression {
  MathTextbookSequence(List<MathTextbookExpression> parts)
    : parts = List.unmodifiable(parts);
  final List<MathTextbookExpression> parts;
  @override
  Map<String, dynamic> toJson() => {
    'kind': 'sequence',
    'parts': parts.map((p) => p.toJson()).toList(),
  };
  @override
  String get latex => parts.map((p) => p.latex).join(' ');
  @override
  String get readable => parts.map((p) => p.readable).join();
}

class MathTextbookCarry {
  const MathTextbookCarry(this.value, this.columnFromRight);
  final int value;
  final int columnFromRight;
  Map<String, dynamic> toJson() => {
    'value': value,
    'columnFromRight': columnFromRight,
  };
}

class MathTextbookVerticalAddition extends MathTextbookExpression {
  MathTextbookVerticalAddition(
    List<String> rows,
    List<MathTextbookCarry> carries,
  ) : rows = List.unmodifiable(rows),
      carries = List.unmodifiable(carries);
  final List<String> rows;
  final List<MathTextbookCarry> carries;
  @override
  Map<String, dynamic> toJson() => {
    'kind': 'verticalAddition',
    'rows': rows,
    'carries': carries.map((c) => c.toJson()).toList(),
  };
  @override
  String get readable => '${rows[0]} + ${rows[1]} = ${rows[2]}';
  @override
  String get latex {
    final width = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    String cells(String row) =>
        row.padLeft(width).split('').map((c) => c == ' ' ? '{}' : c).join('&');
    final carryCells = List.filled(width, '{}');
    for (final carry in carries) {
      carryCells[width - carry.columnFromRight - 1] =
          '\\scriptstyle ${carry.value}';
    }
    return '\\begin{array}{${List.filled(width + 1, 'r').join()}}'
        '&${cells(rows[0])}\\\\'
        '+&${cells(rows[1])}\\\\'
        '&${carryCells.join('&')}\\\\\\hline'
        '&${cells(rows[2])}\\end{array}';
  }
}

String _digits(Object? value, String label) {
  final text = _string(value, label, max: 12);
  if (!RegExp(r'^\d+$').hasMatch(text)) throw FormatException('$label须为整数');
  return text;
}

MathTextbookExpression _expression(Object? value, int depth) {
  if (depth > 8) throw const FormatException('数学表达式层级过深');
  final raw = _object(value, '数学表达式');
  switch (raw['kind']) {
    case 'atom':
      final value = _string(raw['value'], '数学符号', max: 32);
      if (!RegExp(r'^(?:\d+(?:\.\d+)?|[a-zA-Z]{1,8}|[+\-−×÷=<>≤≥()%:])$')
          .hasMatch(value)) {
        throw const FormatException('不支持的数学符号');
      }
      return MathTextbookAtom(value);
    case 'fraction':
      final numerator = _digits(raw['numerator'], '分子');
      final denominator = _digits(raw['denominator'], '分母');
      if (BigInt.parse(denominator) == BigInt.zero) {
        throw const FormatException('分母不能为零');
      }
      return MathTextbookFraction(numerator, denominator);
    case 'mixedNumber':
      final integer = _digits(raw['integer'], '整数部分');
      final fraction = _expression(raw['fraction'], depth + 1);
      if (fraction is! MathTextbookFraction ||
          BigInt.parse(fraction.numerator) >=
              BigInt.parse(fraction.denominator)) {
        throw const FormatException('带分数的分数部分须为真分数');
      }
      return MathTextbookMixedNumber(integer, fraction);
    case 'power':
      final base = _string(raw['base'], '上标底数', max: 8);
      if (!RegExp(r'^[a-zA-Z]+$').hasMatch(base)) {
        throw const FormatException('上标底数无效');
      }
      return MathTextbookPower(
        base,
        _integer(raw['exponent'], '指数', min: 2, max: 3),
      );
    case 'sequence':
      final parts = _list(raw['parts'], '算式', max: 128);
      if (parts.length < 2) throw const FormatException('算式片段不足');
      return MathTextbookSequence(
        parts.map((p) => _expression(p, depth + 1)).toList(),
      );
    case 'verticalAddition':
      if (depth != 0) throw const FormatException('竖式须作为独立公式保留');
      final rows = _list(
        raw['rows'],
        '竖式行',
        max: 3,
      ).map((r) => _digits(r, '竖式数字')).toList();
      if (rows.length != 3) throw const FormatException('加法竖式须保留三行');
      final width = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
      final carries = _list(raw['carries'], '进位', max: 12).map((value) {
        final carry = _object(value, '进位');
        return MathTextbookCarry(
          _integer(carry['value'], '进位数字', min: 1, max: 9),
          _integer(carry['columnFromRight'], '进位列', max: width - 1),
        );
      }).toList();
      if (carries.map((c) => c.columnFromRight).toSet().length !=
          carries.length) {
        throw const FormatException('进位列重复');
      }
      return MathTextbookVerticalAddition(rows, carries);
    default:
      throw const FormatException('不支持的数学表达式结构');
  }
}
