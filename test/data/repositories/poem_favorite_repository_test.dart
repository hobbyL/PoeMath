// test/data/repositories/poem_favorite_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/repositories/poem_favorite_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  late PoemFavoriteRepository repo;

  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
    repo = PoemFavoriteRepository();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  group('PoemFavoriteRepository', () {
    test('isFavorite 默认返回 false', () {
      expect(repo.isFavorite('poem_001'), isFalse);
    });

    test('toggle 收藏返回 true', () async {
      final result = await repo.toggle('poem_001');
      expect(result, isTrue);
      expect(repo.isFavorite('poem_001'), isTrue);
    });

    test('toggle 再次取消收藏返回 false', () async {
      await repo.toggle('poem_001');
      final result = await repo.toggle('poem_001');
      expect(result, isFalse);
      expect(repo.isFavorite('poem_001'), isFalse);
    });

    test('getAll 返回当前 profile 的收藏', () async {
      await repo.toggle('poem_001');
      await repo.toggle('poem_002');

      final all = repo.getAll();
      expect(all.length, 2);
    });

    test('getAll 不包含其他 profile 的收藏', () async {
      await repo.toggle('poem_001');

      ProfileScope.switchTo('kid2');
      final kid2Repo = PoemFavoriteRepository();
      await kid2Repo.toggle('poem_002');

      ProfileScope.reset();
      expect(repo.getAll().length, 1);
      expect(repo.getAll().first.poemId, 'poem_001');
    });

    test('getFavoriteIds 返回 ID 列表', () async {
      await repo.toggle('poem_a');
      await repo.toggle('poem_b');

      final ids = repo.getFavoriteIds();
      expect(ids, containsAll(['poem_a', 'poem_b']));
    });

    test('count 返回正确数量', () async {
      expect(repo.count, 0);
      await repo.toggle('poem_001');
      expect(repo.count, 1);
      await repo.toggle('poem_002');
      expect(repo.count, 2);
      await repo.toggle('poem_001'); // 取消
      expect(repo.count, 1);
    });
  });
}
