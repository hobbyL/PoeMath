import 'annotation.dart';

/// A single poem entry consumed by the PoeMath app.
///
/// Field names intentionally use snake_case in JSON to match the schema declared
/// in the parent task design document; Dart-side we keep camelCase.
class Poem {
  const Poem({
    required this.id,
    required this.title,
    required this.author,
    required this.dynasty,
    required this.content,
    required this.pinyin,
    required this.layer,
    required this.grade,
    required this.semester,
    required this.textbookUnit,
    required this.isRequired,
    required this.annotations,
    required this.translation,
    required this.appreciation,
    required this.background,
    required this.famousLines,
    required this.tags,
    required this.difficulty,
  });

  final String id;
  final String title;
  final String author;
  final String dynasty;
  final String content;
  final String pinyin;

  /// core | extended | explore
  final String layer;

  final int? grade;
  final String? semester;
  final String? textbookUnit;
  final bool isRequired;

  final List<Annotation> annotations;
  final String translation;
  final String appreciation;
  final String background;
  final List<String> famousLines;
  final List<String> tags;
  final int difficulty;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
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
      'annotations': annotations.map((a) => a.toJson()).toList(),
      'translation': translation,
      'appreciation': appreciation,
      'background': background,
      'famous_lines': famousLines,
      'tags': tags,
      'difficulty': difficulty,
    };
  }
}
