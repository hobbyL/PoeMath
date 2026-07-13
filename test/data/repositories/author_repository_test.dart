// test/data/repositories/author_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/author.dart';
import 'package:poemath/data/repositories/author_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  late AuthorRepository repo;

  setUp(() async {
    await setUpHiveForTesting();
    repo = AuthorRepository();

    await HiveBoxes.authors.putAll({
      'author_li_bai': Author(
        id: 'author_li_bai',
        name: '李白',
        dynasty: '唐',
        title: '诗仙',
        brief: '浪漫主义诗人',
      ),
      'author_du_fu': Author(
        id: 'author_du_fu',
        name: '杜甫',
        dynasty: '唐',
        title: '诗圣',
        brief: '现实主义诗人',
      ),
      'author_su_shi': Author(
        id: 'author_su_shi',
        name: '苏轼',
        dynasty: '宋',
        title: '文豪',
        brief: '豪放派词人',
      ),
    });
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  group('AuthorRepository', () {
    test('getById 返回对应作者', () {
      final author = repo.getById('author_li_bai');
      expect(author, isNotNull);
      expect(author!.name, '李白');
      expect(author.title, '诗仙');
    });

    test('getById 不存在返回 null', () {
      expect(repo.getById('nonexistent'), isNull);
    });

    test('getByName 按名字精确匹配', () {
      final author = repo.getByName('杜甫');
      expect(author, isNotNull);
      expect(author!.id, 'author_du_fu');
      expect(author.dynasty, '唐');
    });

    test('getByName 不存在返回 null', () {
      expect(repo.getByName('白居易'), isNull);
    });

    test('getAll 返回全部作者', () {
      final all = repo.getAll();
      expect(all.length, 3);
    });

    test('byDynasty 按朝代筛选', () {
      final tang = repo.byDynasty('唐');
      expect(tang.length, 2);
      expect(tang.map((a) => a.name), containsAll(['李白', '杜甫']));

      final song = repo.byDynasty('宋');
      expect(song.length, 1);
      expect(song.first.name, '苏轼');
    });

    test('byDynasty 无匹配返回空列表', () {
      expect(repo.byDynasty('清'), isEmpty);
    });

    test('totalCount 返回正确数量', () {
      expect(repo.totalCount, 3);
    });
  });
}
