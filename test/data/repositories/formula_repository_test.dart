// test/data/repositories/formula_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/formula.dart';
import 'package:poemath/data/repositories/formula_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  late FormulaRepository repo;

  setUp(() async {
    await setUpHiveForTesting();
    repo = FormulaRepository();

    await HiveBoxes.formulas.putAll({
      'f_add_1': Formula(
        id: 'f_add_1',
        category: '加法',
        name: '加法交换律',
        formulaText: 'a + b = b + a',
        formulaLatex: r'a + b = b + a',
        grade: 1,
      ),
      'f_add_2': Formula(
        id: 'f_add_2',
        category: '加法',
        name: '加法结合律',
        formulaText: '(a + b) + c = a + (b + c)',
        formulaLatex: r'(a + b) + c = a + (b + c)',
        grade: 2,
      ),
      'f_mul_1': Formula(
        id: 'f_mul_1',
        category: '乘法',
        name: '乘法交换律',
        formulaText: 'a × b = b × a',
        formulaLatex: r'a \times b = b \times a',
        grade: 3,
      ),
    });
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  group('FormulaRepository', () {
    test('getById 返回对应公式', () {
      final f = repo.getById('f_add_1');
      expect(f, isNotNull);
      expect(f!.name, '加法交换律');
    });

    test('getById 不存在返回 null', () {
      expect(repo.getById('nonexistent'), isNull);
    });

    test('getAll 返回全部公式', () {
      expect(repo.getAll().length, 3);
    });

    test('byCategory 按分类筛选', () {
      final add = repo.byCategory('加法');
      expect(add.length, 2);

      final mul = repo.byCategory('乘法');
      expect(mul.length, 1);
    });

    test('byGrade 返回该年级及以下公式', () {
      final g1 = repo.byGrade(1);
      expect(g1.length, 1);

      final g2 = repo.byGrade(2);
      expect(g2.length, 2);

      final g3 = repo.byGrade(3);
      expect(g3.length, 3);
    });

    test('availableCategories 包含所有分类', () {
      expect(repo.availableCategories, containsAll(['加法', '乘法']));
    });

    test('search 按名称匹配', () {
      final results = repo.search('交换律');
      expect(results.length, 2);
    });

    test('search 按公式文本匹配', () {
      final results = repo.search('a + b');
      expect(results.length, 2);
    });

    test('search 按分类匹配', () {
      final results = repo.search('乘法');
      expect(results.length, 1);
    });

    test('search 空字符串返回空列表', () {
      expect(repo.search(''), isEmpty);
    });

    test('totalCount 返回正确数量', () {
      expect(repo.totalCount, 3);
    });
  });
}
