import '../io/json_writer.dart';
import '../io/yaml_loader.dart';
import '../models/formula.dart';
import 'core_importer.dart' show ImportReport;

/// Imports the formulas YAML source and writes `formulas.json`.
class FormulasImporter {
  const FormulasImporter({required this.sourcePath, required this.outputPath});

  final String sourcePath;
  final String outputPath;

  ImportReport run() {
    final root = loadYamlMap(sourcePath);
    final rawList = root['formulas'] as List<dynamic>? ?? const <dynamic>[];
    final formulas = <Formula>[];
    for (final raw in rawList) {
      final map = raw as Map<String, dynamic>;
      final params =
          (map['params'] as List<dynamic>? ?? const <dynamic>[]).map((p) {
        final pm = p as Map<String, dynamic>;
        return FormulaParam(
          symbol: pm['symbol'] as String,
          meaning: pm['meaning'] as String,
        );
      }).toList();
      final related = (map['related_formulas'] as List<dynamic>? ??
              const <dynamic>[])
          .map((e) => e as String)
          .toList();
      formulas.add(Formula(
        id: map['id'] as String,
        category: map['category'] as String,
        name: map['name'] as String,
        formulaText: map['formula_text'] as String,
        formulaLatex: map['formula_latex'] as String,
        grade: map['grade'] as int,
        params: params,
        memoryTip: (map['memory_tip'] as String?) ?? '',
        example: (map['example'] as String?) ?? '',
        relatedFormulas: related,
      ));
    }
    writeJson(outputPath, formulas.map((f) => f.toJson()).toList());
    return ImportReport(recordCount: formulas.length, outputPath: outputPath);
  }
}
