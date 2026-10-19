// lib/data/models/poem.dart
//
// 层级：data/models
// 职责：诗词主模型。对应 assets/data/poems_*.json 结构。

import 'package:hive/hive.dart';

import 'poem_annotation.dart';

part 'poem.g.dart';

@HiveType(typeId: 0)
class Poem extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String author;

  @HiveField(3)
  final String dynasty;

  @HiveField(4)
  final String content;

  @HiveField(5)
  final String pinyin;

  @HiveField(6)
  final String layer; // core / extended / explore

  @HiveField(7)
  final int? grade;

  @HiveField(8)
  final String? semester;

  @HiveField(9)
  final String? textbookUnit;

  @HiveField(10)
  final bool isRequired;

  @HiveField(11)
  final List<PoemAnnotation> annotations;

  @HiveField(12)
  final String translation;

  @HiveField(13)
  final String appreciation;

  @HiveField(14)
  final String background;

  @HiveField(15)
  final List<String> famousLines;

  @HiveField(16)
  final List<String> tags;

  @HiveField(17)
  final int difficulty;

  Poem({
    required this.id,
    required this.title,
    required this.author,
    required this.dynasty,
    required this.content,
    required this.pinyin,
    required this.layer,
    this.grade,
    this.semester,
    this.textbookUnit,
    this.isRequired = false,
    this.annotations = const [],
    this.translation = '',
    this.appreciation = '',
    this.background = '',
    this.famousLines = const [],
    this.tags = const [],
    this.difficulty = 1,
  });

  factory Poem.fromJson(Map<String, dynamic> json) {
    return Poem(
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String,
      dynasty: json['dynasty'] as String,
      content: json['content'] as String,
      pinyin: json['pinyin'] as String? ?? '',
      layer: json['layer'] as String? ?? 'explore',
      grade: json['grade'] as int?,
      semester: json['semester'] as String?,
      textbookUnit: json['textbook_unit'] as String?,
      isRequired: json['is_required'] as bool? ?? false,
      annotations: (json['annotations'] as List<dynamic>?)
              ?.map(
                (e) =>
                    PoemAnnotation.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      translation: json['translation'] as String? ?? '',
      appreciation: json['appreciation'] as String? ?? '',
      background: json['background'] as String? ?? '',
      famousLines: (json['famous_lines'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      difficulty: json['difficulty'] as int? ?? 1,
    );
  }

  /// 这首诗归属的年级集合。
  ///
  /// - **有 `grade`**（教材编排，目前只有 `core` 层）：只属于那一个年级。
  /// - **无 `grade`**（`extended` / `explore` 层）：按 difficulty 映射到
  ///   一个**年级区间**，区间内全部年级都能看到它。
  ///
  /// 之所以是**集合**而非单个值：低难度诗的区间存在重叠（见
  /// [_gradesFromDifficulty]），同一首诗出现在相邻两个年级的推荐里是
  /// 合理的 —— 低年级学生读稍简单的课外诗本就正常。这是刻意允许的
  /// 跨年级重复，不是数据错误。
  Set<int> get effectiveGrades =>
      grade != null ? {grade!} : _gradesFromDifficulty(difficulty);

  /// difficulty → 年级**区间**映射（仅用于无 grade 的诗词）。
  ///
  /// 区间由 core 层的真实 difficulty-grade 分布推得（core 是唯一有教材
  /// 编排依据的层，130 首全部带 `textbook_unit`）：
  ///
  /// | difficulty | core 中的真实年级分布 |
  /// |---|---|
  /// | 1 | grade1×13, grade2×13 |
  /// | 2 | grade2×1, grade3×29, grade4×23, grade5×8, grade6×4 |
  /// | 3 | grade4×8, grade5×17, grade6×13 |
  /// | 4 | grade6×1 |
  ///
  /// 可见同一难度横跨多个年级，因此映射到区间而非单一值。区间刻意重叠：
  /// 低年级样本太少（difficulty 1 只有 26 首），不重叠会让 1、2 年级
  /// 各自只剩十几首。
  ///
  /// **不要**改回「一档难度 = 一个年级」：那正是修正前的缺陷 ——
  /// 505 首 difficulty-3 的诗（从汉乐府到宋词都有）被全算成「5 年级」，
  /// 让 5 年级显示 500+ 首，误导用户以为是教材量。
  static Set<int> _gradesFromDifficulty(int difficulty) {
    return switch (difficulty) {
      1 => const {1, 2},
      2 => const {2, 3, 4},
      3 => const {5, 6},
      _ => const {6},
    };
  }

  /// 层级中文标签：必背(core) / 扩展(extended) / 拓展(explore)。
  String get layerLabel => switch (layer) {
        'core' => '必背',
        'extended' => '扩展',
        _ => '拓展',
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'dynasty': dynasty,
        'content': content,
        'pinyin': pinyin,
        'layer': layer,
        'grade': grade,
        'semester': semester,
        'textbook_unit': textbookUnit,
        'is_required': isRequired,
        'annotations': annotations.map((e) => e.toJson()).toList(),
        'translation': translation,
        'appreciation': appreciation,
        'background': background,
        'famous_lines': famousLines,
        'tags': tags,
        'difficulty': difficulty,
      };
}
