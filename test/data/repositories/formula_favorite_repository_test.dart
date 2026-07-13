// test/data/repositories/formula_favorite_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/repositories/formula_favorite_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  late FormulaFavoriteRepository repo;

  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
    repo = FormulaFavoriteRepository();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  group('FormulaFavoriteRepository', () {
    test('isFavorite 默认返回 false', () {
      expect(repo.isFavorite('f_001'), isFalse);
    });

    test('toggle 收藏返回 true', () async {
      final result = await repo.toggle('f_001');
      expect(result, isTrue);
      expect(repo.isFavorite('f_001'), isTrue);
    });

    test('toggle 再次取消返回 false', () async {
      await repo.toggle('f_001');
      final result = await repo.toggle('f_001');
      expect(result, isFalse);
      expect(repo.isFavorite('f_001'), isFalse);
    });

    test('getFavoriteIds 返回收藏的公式 ID', () async {
      await repo.toggle('f_001');
      await repo.toggle('f_002');

      final ids = repo.getFavoriteIds();
      expect(ids, containsAll(['f_001', 'f_002']));
    });

    test('getFavoriteIds 不包含其他 profile 的收藏', () async {
      await repo.toggle('f_001');

      ProfileScope.switchTo('kid2');
      final kid2Repo = FormulaFavoriteRepository();
      await kid2Repo.toggle('f_002');

      ProfileScope.reset();
      expect(repo.getFavoriteIds(), ['f_001']);
    });

    test('count 返回正确数量', () async {
      expect(repo.count, 0);
      await repo.toggle('f_001');
      expect(repo.count, 1);
      await repo.toggle('f_002');
      expect(repo.count, 2);
      await repo.toggle('f_001'); // 取消
      expect(repo.count, 1);
    });
  });
}
