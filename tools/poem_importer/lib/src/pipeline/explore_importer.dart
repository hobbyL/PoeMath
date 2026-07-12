import 'core_importer.dart';

/// Explore-layer importer: fully automatic, keyed by theme tags. For the MVP
/// data delivery we accept a curated YAML the same shape as the core layer.
///
/// Any YAML entry that omits `layer` will fall back to `explore`, and
/// `is_required` defaults to `false` in the underlying parser.
class ExploreImporter {
  const ExploreImporter({required this.sourcePath, required this.outputPath});

  final String sourcePath;
  final String outputPath;

  ImportReport run() {
    final importer = CoreImporter(
      sourcePath: sourcePath,
      outputPath: outputPath,
      defaultLayer: 'explore',
    );
    return importer.run();
  }
}
