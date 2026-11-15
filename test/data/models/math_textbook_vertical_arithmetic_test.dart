import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/domain/math_textbook_editing.dart';

void main() {
  test('竖式编解码保留空位、未填结果、小数点及每一层借位标注', () {
    final expressions = [
      MathTextbookVerticalArithmetic(['35', ' 2', ' 7'], operation: '+'),
      MathTextbookVerticalArithmetic(['48', '36', '  '], operation: '-'),
      MathTextbookVerticalArithmetic(['3.5', '2.7', '6.2'], operation: '+'),
      MathTextbookVerticalArithmetic(['12', ' 3', '36'], operation: '×'),
      MathTextbookVerticalArithmetic(
        ['36', '19', '17'],
        operation: '-',
        annotations: const [
          MathTextbookVerticalAnnotation(
            value: '2',
            row: 0,
            columnFromRight: 1,
          ),
          MathTextbookVerticalAnnotation(
            value: '16',
            row: 0,
            columnFromRight: 0,
          ),
          MathTextbookVerticalAnnotation(
            value: '.',
            row: 0,
            columnFromRight: 1,
            level: 1,
          ),
        ],
      ),
    ];
    for (final expression in expressions) {
      final decoded = MathTextbookExpression.fromJson(expression.toJson());
      expect(decoded.toJson(), expression.toJson());
      expect(decoded.readable, isNot(contains('=')));
      expect(decoded.latex, expression.latex);
    }
    expect(expressions.first.latex, contains(r'&{}&7\end{array}'));
    expect(expressions[1].readable, contains('尚未填写'));
    expect(expressions.last.latex, contains(r'\scriptstyle 16'));
    expect(expressions.last.latex, contains(r'\scriptstyle \cdot'));
  });

  test('竖式拒绝非法运算、空操作数、越界和重复标注，不接受任意LaTeX', () {
    final valid = MathTextbookVerticalArithmetic(
      ['36', '19', '17'],
      operation: '-',
      annotations: const [
        MathTextbookVerticalAnnotation(value: '2', row: 0, columnFromRight: 1),
      ],
    ).toJson();
    final annotation =
        (valid['annotations'] as List).single as Map<String, dynamic>;
    final invalid = [
      {...valid, 'operation': '÷'},
      {
        ...valid,
        'rows': ['36', '', '17'],
      },
      {
        ...valid,
        'rows': ['36', '1 9', '17'],
      },
      {
        ...valid,
        'rows': ['3.6.1', '19', '17'],
      },
      {
        ...valid,
        'rows': ['36', '19', r'\input{x}'],
      },
      {
        ...valid,
        'rows': ['36', '19', '17', '0'],
      },
      {
        ...valid,
        'rows': ['1234567890123', '19', '17'],
      },
      for (final change in [
        {'value': '123'},
        {'value': 'x'},
        {'row': 3},
        {'row': -1},
        {'columnFromRight': 2},
        {'level': 4},
        {'level': -1},
      ])
        {
          ...valid,
          'annotations': [
            {...annotation, ...change},
          ],
        },
      {
        ...valid,
        'annotations': [annotation, annotation],
      },
      MathTextbookSequence([
        MathTextbookExpression.fromJson(valid),
        const MathTextbookAtom('1'),
      ]).toJson(),
    ];
    for (final value in invalid) {
      expect(
        () => MathTextbookExpression.fromJson(value),
        throwsFormatException,
        reason: '$value',
      );
    }
  });

  test('原整数加法的存储、进位位置和排版保持兼容', () {
    final expression = MathTextbookVerticalAddition(
      ['541', '267', '808'],
      [const MathTextbookCarry(1, 1), const MathTextbookCarry(1, 2)],
    );
    expect(expression.toJson(), {
      'kind': 'verticalAddition',
      'rows': ['541', '267', '808'],
      'carries': [
        {'value': 1, 'columnFromRight': 1},
        {'value': 1, 'columnFromRight': 2},
      ],
    });
    expect(expression.readable, '541 + 267 = 808');
    expect(
      expression.latex,
      r'\begin{array}{rrrr}&5&4&1\\+&2&6&7\\&\scriptstyle 1&\scriptstyle 1&{}\\\hline&8&0&8\end{array}',
    );
  });

  test('横式支持原书待填符号，仍拒绝命令和除零', () {
    expect(parseMathTextbookExpression('2+3=□').readable, '2+3=□');
    expect(parseMathTextbookExpression('2+3=?').readable, '2+3=?');
    expect(parseMathTextbookExpression('2+3=□').latex, contains(r'\square'));
    for (final text in [r'\input{x}', '1/0', r'\sin(x)', '2+3=○']) {
      expect(
        () => parseMathTextbookExpression(text),
        throwsFormatException,
        reason: text,
      );
    }
  });
}
