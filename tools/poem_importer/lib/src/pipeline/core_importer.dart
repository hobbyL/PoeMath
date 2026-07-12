import '../io/json_writer.dart';
import '../io/yaml_loader.dart';
import '../models/annotation.dart';
import '../models/poem.dart';
import 'pinyin_generator.dart';

/// Imports the curated core-layer poem YAML source and writes the resulting
/// JSON asset.
///
/// The YAML source is expected to be a top-level map:
///
/// ```yaml
/// poems:
///   - id: poem_core_001
///     title: 静夜思
///     author: 李白
///     dynasty: 唐
///     grade: 1
///     semester: 上
///     textbook_unit: 语文一年级上·课文6
///     is_required: true
///     difficulty: 1
///     content: |
///       床前明月光，疑是地上霜。
///       举头望明月，低头思故乡。
///     pinyin: |            # optional; auto-generated if omitted
///       ...
///     annotations:
///       - {word: 疑, meaning: 好像}
///     translation: ...
///     appreciation: ...
///     background: ...
///     famous_lines: ["举头望明月，低头思故乡"]
///     tags: [思乡, 月亮, 五言绝句]
/// ```
class CoreImporter {
  const CoreImporter({
    required this.sourcePath,
    required this.outputPath,
    this.defaultLayer = 'core',
  });

  final String sourcePath;
  final String outputPath;

  /// Fallback value for the `layer` column when a YAML entry omits it. Allows
  /// the Extended/Explore importers to reuse this parser without hardcoding a
  /// per-entry layer field.
  final String defaultLayer;

  ImportReport run() {
    final root = loadYamlMap(sourcePath);
    final rawList = root['poems'] as List<dynamic>? ?? const <dynamic>[];
    final poems = <Poem>[];
    for (final raw in rawList) {
      final map = raw as Map<String, dynamic>;
      poems.add(_buildPoem(map));
    }
    writeJson(outputPath, poems.map((p) => p.toJson()).toList());
    return ImportReport(recordCount: poems.length, outputPath: outputPath);
  }

  Poem _buildPoem(Map<String, dynamic> map) {
    final content = (map['content'] as String).trim();
    final providedPinyin = map['pinyin'] as String?;
    final pinyin = (providedPinyin != null && providedPinyin.trim().isNotEmpty)
        ? providedPinyin.trim()
        : generatePinyin(content);

    final annotationList =
        (map['annotations'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => Annotation.fromMap(e as Map<String, dynamic>))
            .toList();

    final famousLines = (map['famous_lines'] as List<dynamic>? ?? const <dynamic>[])
        .map((e) => e as String)
        .toList();
    final tags = (map['tags'] as List<dynamic>? ?? const <dynamic>[])
        .map((e) => e as String)
        .toList();

    return Poem(
      id: map['id'] as String,
      title: map['title'] as String,
      author: map['author'] as String,
      dynasty: map['dynasty'] as String,
      content: content,
      pinyin: pinyin,
      layer: (map['layer'] as String?) ?? defaultLayer,
      grade: map['grade'] as int?,
      semester: map['semester'] as String?,
      textbookUnit: map['textbook_unit'] as String?,
      isRequired: (map['is_required'] as bool?) ?? false,
      annotations: annotationList,
      translation: (map['translation'] as String?) ?? '',
      appreciation: (map['appreciation'] as String?) ?? '',
      background: (map['background'] as String?) ?? '',
      famousLines: famousLines,
      tags: tags,
      difficulty: (map['difficulty'] as int?) ?? 1,
    );
  }
}

class ImportReport {
  const ImportReport({required this.recordCount, required this.outputPath});

  final int recordCount;
  final String outputPath;
}
