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
    '□' => r'\square',
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
  String get latex => _verticalLatex(rows, '+', [
    for (final carry in carries)
      MathTextbookVerticalAnnotation(
        value: '${carry.value}',
        row: 2,
        columnFromRight: carry.columnFromRight,
      ),
  ]);
}

/// Stores the printed grid, including empty positions and intermediate work.
/// A partly written result is never presented as a completed equation.
class MathTextbookVerticalArithmetic extends MathTextbookExpression {
  MathTextbookVerticalArithmetic(
    List<String> rows, {
    required this.operation,
    List<MathTextbookVerticalAnnotation> annotations = const [],
  }) : rows = List.unmodifiable(rows),
       annotations = List.unmodifiable(annotations);

  final List<String> rows;
  final String operation;
  final List<MathTextbookVerticalAnnotation> annotations;
  @override
  Map<String, dynamic> toJson() => {
    'kind': 'verticalArithmetic',
    'operation': operation,
    'rows': rows,
    'annotations': annotations.map((a) => a.toJson()).toList(),
  };
  @override
  String get readable {
    final label = switch (operation) {
      '+' => '加法',
      '-' => '减法',
      _ => '乘法',
    };
    final result = rows[2].trim().isEmpty
        ? '横线下尚未填写'
        : '横线下从左到右为${rows[2].split('').map((c) => c == ' ' ? '空位' : c).join('、')}';
    return [
      '$label竖式',
      '第一行${rows[0].trim()}',
      '第二行${rows[1].trim()}',
      result,
      for (final annotation in annotations)
        '第${annotation.row + 1}行上方，从右数第${annotation.columnFromRight + 1}列标注${annotation.value == '.' ? '圆点' : annotation.value}',
    ].join('，');
  }

  @override
  String get latex => _verticalLatex(rows, operation, annotations);
}

class MathTextbookVerticalAnnotation {
  const MathTextbookVerticalAnnotation({
    required this.value,
    required this.row,
    required this.columnFromRight,
    this.level = 0,
  });
  final String value;
  final int row;
  final int columnFromRight;
  final int level;
  Map<String, dynamic> toJson() => {
    'value': value,
    'row': row,
    'columnFromRight': columnFromRight,
    if (level != 0) 'level': level,
  };
}

String _verticalLatex(
  List<String> rows,
  String operation,
  List<MathTextbookVerticalAnnotation> annotations,
) {
  final width = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
  String cells(String row) =>
      row.padLeft(width).split('').map((c) => c == ' ' ? '{}' : c).join('&');
  String noteRows(int row) {
    final notes = annotations.where((a) => a.row == row).toList();
    if (notes.isEmpty && row != 2) return '';
    final levels = notes.map((a) => a.level).toSet().toList()..sort();
    if (levels.isEmpty) levels.add(0);
    return [
      for (final level in levels)
        '&${List.generate(width, (column) {
          final note = notes.where((a) => a.level == level && a.columnFromRight == width - column - 1).firstOrNull;
          if (note == null) return '{}';
          return '\\scriptstyle ${note.value == '.' ? r'\cdot' : note.value}';
        }).join('&')}\\\\',
    ].join();
  }

  return '\\begin{array}{${List.filled(width + 1, 'r').join()}}'
      '${noteRows(0)}'
      '&${cells(rows[0])}\\\\'
      '${noteRows(1)}'
      '${operation == '×' ? r'\times' : operation}&${cells(rows[1])}\\\\'
      '${noteRows(2)}\\hline'
      '&${cells(rows[2])}\\end{array}';
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
      if (!RegExp(r'^(?:\d+(?:\.\d+)?|[a-zA-Z]{1,8}|[+\-−×÷=<>≤≥()%:?□])$')
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
    case 'verticalArithmetic':
      if (depth != 0) throw const FormatException('竖式须作为独立公式保留');
      final operation = _string(raw['operation'], '竖式运算', max: 1);
      if (!['+', '-', '×'].contains(operation)) {
        throw const FormatException('竖式运算无效');
      }
      final values = _list(raw['rows'], '竖式行', max: 3);
      if (values.length != 3) throw const FormatException('竖式须保留三行');
      final rows = <String>[];
      for (var index = 0; index < values.length; index++) {
        final value = values[index];
        if (value is! String ||
            value.length > 12 ||
            !RegExp(r'^[0-9. ]*$').hasMatch(value) ||
            (index < 2 &&
                !RegExp(r'^(?:\d+(?:\.\d+)?|\.\d+)$').hasMatch(value.trim())) ||
            '.'.allMatches(value).length > 1) {
          throw const FormatException('竖式数字、小数点或空位无效');
        }
        rows.add(value);
      }
      final width = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
      final annotations = _list(raw['annotations'] ?? [], '竖式标注', max: 36).map((
        value,
      ) {
        final data = _object(value, '竖式标注');
        final text = _string(data['value'], '标注数字', max: 2);
        if (!RegExp(r'^(?:\d{1,2}|\.)$').hasMatch(text)) {
          throw const FormatException('竖式标注须为数字或圆点');
        }
        return MathTextbookVerticalAnnotation(
          value: text,
          row: _integer(data['row'], '标注行', max: 2),
          columnFromRight: _integer(
            data['columnFromRight'],
            '标注列',
            max: width - 1,
          ),
          level: _integer(data['level'] ?? 0, '标注层', max: 3),
        );
      }).toList();
      if (annotations
              .map((a) => (a.row, a.columnFromRight, a.level))
              .toSet()
              .length !=
          annotations.length) {
        throw const FormatException('竖式标注位置重复');
      }
      return MathTextbookVerticalArithmetic(
        rows,
        operation: operation,
        annotations: annotations,
      );
    default:
      throw const FormatException('不支持的数学表达式结构');
  }
}
