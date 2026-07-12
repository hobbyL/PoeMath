// lib/data/models/poem_annotation.dart
//
// 层级：data/models
// 职责：诗词注释子模型（嵌入 Poem 内）。

import 'package:hive/hive.dart';

part 'poem_annotation.g.dart';

@HiveType(typeId: 3)
class PoemAnnotation extends HiveObject {
  @HiveField(0)
  final String word;

  @HiveField(1)
  final String meaning;

  PoemAnnotation({
    required this.word,
    required this.meaning,
  });

  factory PoemAnnotation.fromJson(Map<String, dynamic> json) {
    return PoemAnnotation(
      word: json['word'] as String,
      meaning: json['meaning'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'word': word,
        'meaning': meaning,
      };
}
