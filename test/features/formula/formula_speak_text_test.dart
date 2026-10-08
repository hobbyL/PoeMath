// test/features/formula/formula_speak_text_test.dart
//
// formulaSpeakText / replaceFormulaSymbols 纯函数单测（任务 10-07-formula-tts AC1）。

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/data/models/formula.dart';
import 'package:poemath/data/models/formula_param.dart';
import 'package:poemath/features/formula/formula_speak_text.dart';

Formula _formula({
  String name = '长方形周长',
  List<FormulaParam> params = const [],
}) {
  return Formula(
    id: 'test',
    category: '图形',
    name: name,
    formulaText: 'C = (a + b) × 2',
    formulaLatex: 'C = (a + b) \\times 2',
    grade: 3,
    params: params,
    memoryTip: '',
    example: '',
    relatedFormulas: const [],
  );
}

void main() {
  group('formulaSpeakText（AC1）', () {
    test('含 params 的公式输出「名称。符号读音，释义。」序列', () {
      final formula = _formula(
        params: [
          FormulaParam(symbol: 'C', meaning: '周长'),
          FormulaParam(symbol: 'a', meaning: '长'),
          FormulaParam(symbol: 'b', meaning: '宽'),
        ],
      );

      expect(
        formulaSpeakText(formula),
        '长方形周长。C，周长。a，长。b，宽。',
      );
    });

    test('无 params 只输出名称', () {
      expect(formulaSpeakText(_formula()), '长方形周长。');
    });

    test('param 符号过读音表：π 读作「派」', () {
      final formula = _formula(
        params: [FormulaParam(symbol: 'π', meaning: '圆周率')],
      );

      expect(formulaSpeakText(formula), '长方形周长。派，圆周率。');
    });
  });

  group('replaceFormulaSymbols（AC1）', () {
    test('m² → m的平方、π → 派、× → 乘', () {
      expect(replaceFormulaSymbols('m²'), 'm的平方');
      expect(replaceFormulaSymbols('π'), '派');
      expect(replaceFormulaSymbols('×'), '乘');
    });

    test('未收录符号原样保留（不报错、不吞字符）', () {
      expect(replaceFormulaSymbols('η'), 'η');
      expect(replaceFormulaSymbols('…'), '…');
      // 未收录的任意 Unicode 字符透传。
      expect(replaceFormulaSymbols('a√b'), 'a√b');
    });

    test('例题文本：× 变乘、其余不变（PRD AC1 实例）', () {
      const example = '长 5 cm、宽 3 cm，周长 = (5+3)×2 = 16 cm。';

      expect(
        replaceFormulaSymbols(example),
        '长 5 cm、宽 3 cm，周长 = (5+3)乘2 = 16 cm。',
      );
    });

    test('混合替换：cm²、÷、→', () {
      expect(replaceFormulaSymbols('36 cm²'), '36 cm的平方');
      expect(replaceFormulaSymbols('8×5÷2'), '8乘5除以2');
      expect(replaceFormulaSymbols('x → 8'), 'x 到 8');
    });

    test('空文本原样返回', () {
      expect(replaceFormulaSymbols(''), '');
    });
  });
}
