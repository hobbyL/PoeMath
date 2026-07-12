import 'core_importer.dart';

/// Extended-layer importer shares the YAML schema with the core importer but
/// defaults the [layer] to `extended`.
///
/// Kept as its own class so that future half-automatic filters (Tang 300,
/// Song 100 curated lists) can plug in additional selection logic without
/// touching the core-layer path.
class ExtendedImporter {
  const ExtendedImporter({required this.sourcePath, required this.outputPath});

  final String sourcePath;
  final String outputPath;

  ImportReport run() {
    final importer = CoreImporter(
      sourcePath: sourcePath,
      outputPath: outputPath,
      defaultLayer: 'extended',
    );
    return importer.run();
  }
}
