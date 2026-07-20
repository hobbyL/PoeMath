// lib/data/repositories/poem_repository.dart
//
// 层级：data/repositories
// 职责：诗词数据仓储。提供按 ID、年级、作者、朝代、标签、层级筛选功能。
//       内部维护应用层索引 Map（启动时一次性构建）。

import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem.dart';

class PoemRepository {
  // ============ 应用层索引 ============
  late final Map<int, List<String>> _byGrade;
  late final Map<String, List<String>> _byAuthor;
  late final Map<String, List<String>> _byDynasty;
  late final Map<String, List<String>> _byTag;
  late final Map<String, List<String>> _byLayer;

  bool _indexBuilt = false;

  /// 构建内存索引。调用一次即可。
  Future<void> buildIndices() async {
    if (_indexBuilt) return;

    final byGrade = <int, List<String>>{};
    final byAuthor = <String, List<String>>{};
    final byDynasty = <String, List<String>>{};
    final byTag = <String, List<String>>{};
    final byLayer = <String, List<String>>{};

    for (final poem in HiveBoxes.poems.values) {
      // 年级索引（无 grade 的诗词按 difficulty 推算）
      byGrade.putIfAbsent(poem.effectiveGrade, () => []).add(poem.id);
      // 作者索引
      byAuthor.putIfAbsent(poem.author, () => []).add(poem.id);
      // 朝代索引
      byDynasty.putIfAbsent(poem.dynasty, () => []).add(poem.id);
      // 标签索引
      for (final tag in poem.tags) {
        byTag.putIfAbsent(tag, () => []).add(poem.id);
      }
      // 层级索引
      byLayer.putIfAbsent(poem.layer, () => []).add(poem.id);
    }

    _byGrade = byGrade;
    _byAuthor = byAuthor;
    _byDynasty = byDynasty;
    _byTag = byTag;
    _byLayer = byLayer;
    _indexBuilt = true;
  }

  // ============ 基础查询 ============

  /// 总诗词数
  int get totalCount => HiveBoxes.poems.length;

  /// 按 ID 获取单首诗词
  Poem? getById(String id) => HiveBoxes.poems.get(id);

  /// 获取所有诗词
  List<Poem> getAll() => HiveBoxes.poems.values.toList();

  // ============ 索引查询 ============

  /// 按年级筛选
  List<Poem> byGrade(int grade) {
    return _byGrade[grade]
            ?.map((id) => HiveBoxes.poems.get(id))
            .whereType<Poem>()
            .toList() ??
        [];
  }

  /// 按作者筛选
  List<Poem> byAuthor(String author) {
    return _byAuthor[author]
            ?.map((id) => HiveBoxes.poems.get(id))
            .whereType<Poem>()
            .toList() ??
        [];
  }

  /// 按朝代筛选
  List<Poem> byDynasty(String dynasty) {
    return _byDynasty[dynasty]
            ?.map((id) => HiveBoxes.poems.get(id))
            .whereType<Poem>()
            .toList() ??
        [];
  }

  /// 按标签筛选
  List<Poem> byTag(String tag) {
    return _byTag[tag]
            ?.map((id) => HiveBoxes.poems.get(id))
            .whereType<Poem>()
            .toList() ??
        [];
  }

  /// 按层级筛选
  List<Poem> byLayer(String layer) {
    return _byLayer[layer]
            ?.map((id) => HiveBoxes.poems.get(id))
            .whereType<Poem>()
            .toList() ??
        [];
  }

  /// 获取所有可用年级
  List<int> get availableGrades =>
      (_byGrade.keys.toList()..sort());

  /// 获取所有作者名
  List<String> get availableAuthors =>
      _byAuthor.keys.toList()..sort();

  /// 获取所有朝代
  List<String> get availableDynasties => _byDynasty.keys.toList();

  /// 获取所有标签
  List<String> get availableTags => _byTag.keys.toList();

  /// 搜索（标题或内容包含关键词）
  List<Poem> search(String keyword) {
    if (keyword.isEmpty) return [];
    final lower = keyword.toLowerCase();
    return HiveBoxes.poems.values
        .where((p) =>
            p.title.toLowerCase().contains(lower) ||
            p.content.toLowerCase().contains(lower) ||
            p.author.toLowerCase().contains(lower),)
        .toList();
  }
}
