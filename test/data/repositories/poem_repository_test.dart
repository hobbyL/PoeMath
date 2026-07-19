// test/data/repositories/poem_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/repositories/poem_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  late PoemRepository repo;

  setUp(() async {
    await setUpHiveForTesting();
    repo = PoemRepository();

    // 准备测试数据
    await HiveBoxes.poems.putAll({
      'poem_core_001': Poem(
        id: 'poem_core_001',
        title: '静夜思',
        author: '李白',
        dynasty: '唐',
        content: '床前明月光，疑是地上霜。',
        pinyin: 'chuáng qián míng yuè guāng',
        layer: 'core',
        grade: 1,
        tags: ['思乡', '月亮'],
        difficulty: 1,
      ),
      'poem_core_002': Poem(
        id: 'poem_core_002',
        title: '春晓',
        author: '孟浩然',
        dynasty: '唐',
        content: '春眠不觉晓，处处闻啼鸟。',
        pinyin: 'chūn mián bù jué xiǎo',
        layer: 'core',
        grade: 1,
        tags: ['春天', '自然'],
        difficulty: 1,
      ),
      'poem_core_003': Poem(
        id: 'poem_core_003',
        title: '望庐山瀑布',
        author: '李白',
        dynasty: '唐',
        content: '日照香炉生紫烟，遥看瀑布挂前川。',
        pinyin: 'rì zhào xiāng lú shēng zǐ yān',
        layer: 'core',
        grade: 2,
        tags: ['山水', '自然'],
        difficulty: 2,
      ),
      'poem_ext_001': Poem(
        id: 'poem_ext_001',
        title: '登鹳雀楼',
        author: '王之涣',
        dynasty: '唐',
        content: '白日依山尽，黄河入海流。',
        pinyin: 'bái rì yī shān jìn',
        layer: 'extended',
        tags: ['登高', '哲理'],
        difficulty: 2,
      ),
      'poem_exp_001': Poem(
        id: 'poem_exp_001',
        title: '水调歌头',
        author: '苏轼',
        dynasty: '宋',
        content: '明月几时有，把酒问青天。',
        pinyin: 'míng yuè jǐ shí yǒu',
        layer: 'explore',
        tags: ['月亮', '思乡'],
        difficulty: 3,
      ),
    });

    await repo.buildIndices();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  group('PoemRepository', () {
    group('基础查询', () {
      test('totalCount 返回正确数量', () {
        expect(repo.totalCount, 5);
      });

      test('getById 返回对应诗词', () {
        final poem = repo.getById('poem_core_001');
        expect(poem, isNotNull);
        expect(poem!.title, '静夜思');
        expect(poem.author, '李白');
      });

      test('getById 不存在返回 null', () {
        expect(repo.getById('nonexistent'), isNull);
      });

      test('getAll 返回全部诗词', () {
        final all = repo.getAll();
        expect(all.length, 5);
      });
    });

    group('索引查询', () {
      test('byGrade 按年级筛选', () {
        final grade1 = repo.byGrade(1);
        expect(grade1.length, 2);
        expect(grade1.map((p) => p.title), containsAll(['静夜思', '春晓']));
      });

      test('byGrade 包含 difficulty 推算的诗词', () {
        // poem_ext_001: difficulty=2 → effectiveGrade=3
        final grade3 = repo.byGrade(3);
        expect(grade3.length, 1);
        expect(grade3.first.id, 'poem_ext_001');

        // poem_exp_001: difficulty=3 → effectiveGrade=5
        final grade5 = repo.byGrade(5);
        expect(grade5.length, 1);
        expect(grade5.first.id, 'poem_exp_001');
      });

      test('byGrade 无匹配返回空列表', () {
        expect(repo.byGrade(6), isEmpty);
      });

      test('byAuthor 按作者筛选', () {
        final liBai = repo.byAuthor('李白');
        expect(liBai.length, 2);
        expect(liBai.map((p) => p.id),
            containsAll(['poem_core_001', 'poem_core_003']),);
      });

      test('byDynasty 按朝代筛选', () {
        final tang = repo.byDynasty('唐');
        expect(tang.length, 4);

        final song = repo.byDynasty('宋');
        expect(song.length, 1);
        expect(song.first.author, '苏轼');
      });

      test('byTag 按标签筛选', () {
        final moon = repo.byTag('月亮');
        expect(moon.length, 2);
        expect(moon.map((p) => p.title), containsAll(['静夜思', '水调歌头']));
      });

      test('byLayer 按层级筛选', () {
        final core = repo.byLayer('core');
        expect(core.length, 3);

        final extended = repo.byLayer('extended');
        expect(extended.length, 1);

        final explore = repo.byLayer('explore');
        expect(explore.length, 1);
      });

      test('availableGrades 已排序（含 difficulty 推算）', () {
        // poem_ext_001: grade=null, difficulty=2 → effectiveGrade=3
        // poem_exp_001: grade=null, difficulty=3 → effectiveGrade=5
        expect(repo.availableGrades, [1, 2, 3, 5]);
      });

      test('availableAuthors 已排序', () {
        final authors = repo.availableAuthors;
        expect(authors, contains('李白'));
        expect(authors, contains('苏轼'));
        // 验证排序
        for (var i = 1; i < authors.length; i++) {
          expect(authors[i].compareTo(authors[i - 1]) >= 0, isTrue);
        }
      });

      test('availableDynasties 包含所有朝代', () {
        expect(repo.availableDynasties, containsAll(['唐', '宋']));
      });

      test('availableTags 包含所有标签', () {
        expect(repo.availableTags,
            containsAll(['思乡', '月亮', '春天', '自然', '山水', '登高', '哲理']),);
      });
    });

    group('搜索', () {
      test('search 按标题匹配', () {
        final results = repo.search('静夜');
        expect(results.length, 1);
        expect(results.first.title, '静夜思');
      });

      test('search 按内容匹配', () {
        final results = repo.search('明月');
        expect(results.length, 2); // 静夜思 + 水调歌头
      });

      test('search 按作者匹配', () {
        final results = repo.search('苏轼');
        expect(results.length, 1);
        expect(results.first.title, '水调歌头');
      });

      test('search 空字符串返回空列表', () {
        expect(repo.search(''), isEmpty);
      });

      test('search 无匹配返回空列表', () {
        expect(repo.search('不存在的诗'), isEmpty);
      });
    });

    group('buildIndices', () {
      test('多次调用不会重复构建', () async {
        // 第二次调用应该直接返回
        await repo.buildIndices();
        expect(repo.totalCount, 5);
        expect(repo.byGrade(1).length, 2);
      });
    });
  });
}
