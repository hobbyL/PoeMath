import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

void main() {
  test('各年级题目类型分布', () {
    final rng = Random(42);
    for (final grade in [1, 2, 3, 4, 5, 6]) {
      for (final sem in ['上', '下']) {
        final problems = MathEngine.generateBatch(
          grade: grade, semester: sem, count: 20, random: rng,
        );
        final types = <String, int>{};
        for (final p in problems) {
          final ops = p.operators.map((o) => o.symbol).join('');
          final form = p.resultForm == ResultForm.integer ? '' : '[${p.resultForm.name}]';
          final key = '${p.mode.name}($ops)$form';
          types[key] = (types[key] ?? 0) + 1;
        }
        final config = GradePresets.get(grade, sem);
        // ignore: avoid_print
        print('${config.label}: $types');
      }
    }
  });
}
