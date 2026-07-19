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

  /// 有效年级：有 grade 取 grade，无 grade 按 difficulty 推算。
  int get effectiveGrade => grade ?? _gradeFromDifficulty(difficulty);

  /// 层级中文标签：必背(core) / 扩展(extended) / 拓展(explore)。
  String get layerLabel => switch (layer) {
        'core' => '必背',
        'extended' => '扩展',
        _ => '拓展',
      };

  /// difficulty → grade 映射（仅用于无 grade 的诗词）。
  ///
  /// 基于核心课标诗词的 difficulty-grade 分布推算：
  /// - difficulty 1 → 低年级（grade 2）
  /// - difficulty 2 → 中年级（grade 3）
  /// - difficulty 3 → 高年级（grade 5）
  /// - difficulty 4 → 高年级（grade 6）
  static int _gradeFromDifficulty(int difficulty) {
    return switch (difficulty) {
      1 => 2,
      2 => 3,
      3 => 5,
      _ => 6,
    };
  }

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
