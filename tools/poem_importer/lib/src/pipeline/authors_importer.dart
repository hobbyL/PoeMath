import '../io/json_writer.dart';
import '../io/yaml_loader.dart';
import '../models/author.dart';
import 'core_importer.dart' show ImportReport;

/// Imports the authors seed YAML and writes `authors.json`.
class AuthorsImporter {
  const AuthorsImporter({required this.sourcePath, required this.outputPath});

  final String sourcePath;
  final String outputPath;

  ImportReport run() {
    final root = loadYamlMap(sourcePath);
    final rawList = root['authors'] as List<dynamic>? ?? const <dynamic>[];
    final authors = <Author>[];
    for (final raw in rawList) {
      final map = raw as Map<String, dynamic>;
      final works = (map['representative_works'] as List<dynamic>? ??
              const <dynamic>[])
          .map((e) => e as String)
          .toList();
      authors.add(Author(
        id: map['id'] as String,
        name: map['name'] as String,
        dynasty: map['dynasty'] as String,
        lifeYears: map['life_years'] as String?,
        title: map['title'] as String?,
        brief: (map['brief'] as String?) ?? '',
        representativeWorks: works,
        avatar: (map['avatar'] as String?) ?? 'default_avatar.png',
      ));
    }
    writeJson(outputPath, authors.map((a) => a.toJson()).toList());
    return ImportReport(recordCount: authors.length, outputPath: outputPath);
  }
}
