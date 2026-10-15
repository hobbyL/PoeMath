// test/data/repositories/poem_repository_index_test.dart
//
// 审计问题 14（C3）专项测试：`PoemRepository` 的索引曾挂在实例上，
// `Provider`（非 keepAlive）在页面销毁后重建新实例时，新实例的
// `_indexBuilt` 为 false 而 `late final` 索引字段未初始化 —— 任何索引
// getter 都会抛 `LateInitializationError`（不是返回空列表）。
//
// 索引静态化后：
//   1. 未调用 `buildIndices()` 也能查询（getter 内部同步兜底构建）
//   2. 任一实例构建后，其他实例立即可读
//   3. `resetIndices()` 能丢弃索引（备份恢复后重建）

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/repositories/poem_repository.dart';

import '../../helpers/hive_test_helper.dart';

Future<void> _seed() async {
  await HiveBoxes.poems.putAll({
    'p1': Poem(
      id: 'p1',
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
    'p2': Poem(
      id: 'p2',
      title: '春晓',
      author: '孟浩然',
      dynasty: '唐',
      content: '春眠不觉晓，处处闻啼鸟。',
      pinyin: 'chūn mián bù jué xiǎo',
      layer: 'core',
      grade: 2,
      tags: ['春天'],
      difficulty: 1,
    ),
  });
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
    await _seed();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  group('PoemRepository 索引与实例解耦', () {
    test('全新实例未调 buildIndices 直接查 byGrade 不抛异常', () {
      final fresh = PoemRepository();

      // 修复前：`late final _byGrade` 未初始化 → LateInitializationError。
      expect(() => fresh.byGrade(1), returnsNormally);
      expect(fresh.byGrade(1).map((p) => p.id), ['p1']);
    });

    test('全新实例未调 buildIndices 直接读 availableAuthors 不抛异常', () {
      final fresh = PoemRepository();

      expect(() => fresh.availableAuthors, returnsNormally);
      expect(fresh.availableAuthors, ['孟浩然', '李白']);
    });

    test('所有索引 getter 在未构建时都可用', () {
      final fresh = PoemRepository();

      expect(fresh.byAuthor('李白').map((p) => p.id), ['p1']);
      expect(fresh.byDynasty('唐').map((p) => p.id).toSet(), {'p1', 'p2'});
      expect(fresh.byTag('月亮').map((p) => p.id), ['p1']);
      expect(fresh.byLayer('core').map((p) => p.id).toSet(), {'p1', 'p2'});
      expect(fresh.availableGrades, [1, 2]);
      expect(fresh.availableDynasties, ['唐']);
      expect(fresh.availableTags.toSet(), {'思乡', '月亮', '春天'});
    });

    test('A 实例构建后 B 实例立即可读（索引全局生效）', () async {
      final a = PoemRepository();
      await a.buildIndices();

      final b = PoemRepository();
      expect(b.byGrade(2).map((p) => p.id), ['p2']);
    });

    test('resetIndices 丢弃索引，之后重新按当前 box 内容构建', () async {
      final repo = PoemRepository();
      await repo.buildIndices();
      expect(repo.byGrade(1).map((p) => p.id), ['p1']);

      await HiveBoxes.poems.put(
        'p3',
        Poem(
          id: 'p3',
          title: '咏鹅',
          author: '骆宾王',
          dynasty: '唐',
          content: '鹅鹅鹅，曲项向天歌。',
          pinyin: 'é é é',
          layer: 'core',
          grade: 1,
          tags: ['动物'],
          difficulty: 1,
        ),
      );

      // 未 reset：索引仍是旧快照。
      expect(repo.byGrade(1).map((p) => p.id), ['p1']);

      PoemRepository.resetIndices();
      expect(repo.byGrade(1).map((p) => p.id).toSet(), {'p1', 'p3'});
    });

    test('buildIndices 幂等：重复调用不改变结果', () async {
      final repo = PoemRepository();
      await repo.buildIndices();
      await repo.buildIndices();

      expect(repo.byGrade(1).map((p) => p.id), ['p1']);
    });
  });
}
