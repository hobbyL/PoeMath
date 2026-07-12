// test/data/models/formula_test.dart
//
// 单元测试：Formula 模型的 JSON 序列化/反序列化。

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/formula.dart';

void main() {
  group('Formula', () {
    final sampleJson = <String, dynamic>{
      'id': 'formula_area_triangle',
      'category': '几何面积',
      'name': '三角形面积',
      'formula_text': 'S = a × h ÷ 2',
      'formula_latex': r'S = \frac{a h}{2}',
      'grade': 5,
      'params': [
        {'symbol': 'S', 'meaning': '面积'},
        {'symbol': 'a', 'meaning': '底'},
        {'symbol': 'h', 'meaning': '高'},
      ],
      'memory_tip': '底乘高除以二。',
      'example': '底 8 cm、高 5 cm，面积 = 20 cm²。',
      'related_formulas': ['formula_area_parallelogram'],
    };

    test('fromJson 正确解析', () {
      final f = Formula.fromJson(sampleJson);

      expect(f.id, 'formula_area_triangle');
      expect(f.category, '几何面积');
      expect(f.grade, 5);
      expect(f.params.length, 3);
      expect(f.params[0].symbol, 'S');
      expect(f.relatedFormulas, ['formula_area_parallelogram']);
    });

    test('toJson 与 fromJson 互逆', () {
      final f1 = Formula.fromJson(sampleJson);
      final json = f1.toJson();
      final f2 = Formula.fromJson(json);

      expect(f2.id, f1.id);
      expect(f2.params.length, f1.params.length);
      expect(f2.formulaLatex, f1.formulaLatex);
    });
  });
}
