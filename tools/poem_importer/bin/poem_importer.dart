// ignore_for_file: avoid_print
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:poem_importer/poem_importer.dart';

Future<void> main(List<String> arguments) async {
  final runner = CommandRunner<int>(
    'poem_importer',
    'PoeMath data pipeline: transforms curated YAML into asset JSON.',
  )
    ..addCommand(_ImportCoreCommand())
    ..addCommand(_ImportExtendedCommand())
    ..addCommand(_ImportExploreCommand())
    ..addCommand(_ImportAuthorsCommand())
    ..addCommand(_ImportFormulasCommand())
    ..addCommand(_ImportAllCommand())
    ..addCommand(_ValidateCommand());

  try {
    final code = await runner.run(arguments);
    exit(code ?? 0);
  } on UsageException catch (e) {
    print(e);
    exit(64);
  }
}

const String _kDefaultSourceDir = 'tools/poem_importer/data/sources';
const String _kDefaultOutputDir = 'assets/data';

abstract class _BaseImportCommand extends Command<int> {
  _BaseImportCommand() {
    argParser
      ..addOption('source',
          abbr: 's',
          help: 'YAML source file path (relative to project root).')
      ..addOption('output',
          abbr: 'o',
          help: 'Output JSON file path (relative to project root).');
  }

  String requiredOption(String name, String fallback) {
    final value = argResults?[name] as String?;
    if (value == null || value.isEmpty) return fallback;
    return value;
  }
}

class _ImportCoreCommand extends _BaseImportCommand {
  @override
  String get name => 'import-core';
  @override
  String get description => 'Import curated core-layer poems (130 first-tier).';

  @override
  int run() {
    final source =
        requiredOption('source', '$_kDefaultSourceDir/poems_core.yaml');
    final output =
        requiredOption('output', '$_kDefaultOutputDir/poems_core.json');
    final report = CoreImporter(sourcePath: source, outputPath: output).run();
    print('[core] wrote ${report.recordCount} poems -> ${report.outputPath}');
    return 0;
  }
}

class _ImportExtendedCommand extends _BaseImportCommand {
  @override
  String get name => 'import-extended';
  @override
  String get description =>
      'Import extended-layer poems (~400 curated classics).';

  @override
  int run() {
    final source =
        requiredOption('source', '$_kDefaultSourceDir/poems_extended.yaml');
    final output =
        requiredOption('output', '$_kDefaultOutputDir/poems_extended.json');
    final report =
        ExtendedImporter(sourcePath: source, outputPath: output).run();
    print(
        '[extended] wrote ${report.recordCount} poems -> ${report.outputPath}');
    return 0;
  }
}

class _ImportExploreCommand extends _BaseImportCommand {
  @override
  String get name => 'import-explore';
  @override
  String get description =>
      'Import explore-layer poems (~500 auto-tagged extras).';

  @override
  int run() {
    final source =
        requiredOption('source', '$_kDefaultSourceDir/poems_explore.yaml');
    final output =
        requiredOption('output', '$_kDefaultOutputDir/poems_explore.json');
    final report =
        ExploreImporter(sourcePath: source, outputPath: output).run();
    print(
        '[explore] wrote ${report.recordCount} poems -> ${report.outputPath}');
    return 0;
  }
}

class _ImportAuthorsCommand extends _BaseImportCommand {
  @override
  String get name => 'import-authors';
  @override
  String get description => 'Import author metadata.';

  @override
  int run() {
    final source =
        requiredOption('source', '$_kDefaultSourceDir/authors_seed.yaml');
    final output = requiredOption('output', '$_kDefaultOutputDir/authors.json');
    final report =
        AuthorsImporter(sourcePath: source, outputPath: output).run();
    print(
        '[authors] wrote ${report.recordCount} entries -> ${report.outputPath}');
    return 0;
  }
}

class _ImportFormulasCommand extends _BaseImportCommand {
  @override
  String get name => 'import-formulas';
  @override
  String get description =>
      'Import math formulas knowledge base (60-80 entries).';

  @override
  int run() {
    final source =
        requiredOption('source', '$_kDefaultSourceDir/formulas.yaml');
    final output =
        requiredOption('output', '$_kDefaultOutputDir/formulas.json');
    final report =
        FormulasImporter(sourcePath: source, outputPath: output).run();
    print(
        '[formulas] wrote ${report.recordCount} entries -> ${report.outputPath}');
    return 0;
  }
}

class _ImportAllCommand extends Command<int> {
  _ImportAllCommand() {
    argParser
      ..addOption('source-dir',
          help: 'Directory containing YAML sources.',
          defaultsTo: _kDefaultSourceDir)
      ..addOption('output-dir',
          help: 'Directory receiving JSON assets.',
          defaultsTo: _kDefaultOutputDir);
  }

  @override
  String get name => 'import-all';
  @override
  String get description =>
      'Run every importer against the standard YAML layout.';

  @override
  int run() {
    final srcDir = argResults!['source-dir'] as String;
    final outDir = argResults!['output-dir'] as String;
    final reports = <ImportReport>[
      CoreImporter(
        sourcePath: '$srcDir/poems_core.yaml',
        outputPath: '$outDir/poems_core.json',
      ).run(),
      ExtendedImporter(
        sourcePath: '$srcDir/poems_extended.yaml',
        outputPath: '$outDir/poems_extended.json',
      ).run(),
      ExploreImporter(
        sourcePath: '$srcDir/poems_explore.yaml',
        outputPath: '$outDir/poems_explore.json',
      ).run(),
      AuthorsImporter(
        sourcePath: '$srcDir/authors_seed.yaml',
        outputPath: '$outDir/authors.json',
      ).run(),
      FormulasImporter(
        sourcePath: '$srcDir/formulas.yaml',
        outputPath: '$outDir/formulas.json',
      ).run(),
    ];
    for (final r in reports) {
      print('wrote ${r.recordCount.toString().padLeft(4)} -> ${r.outputPath}');
    }
    return 0;
  }
}

class _ValidateCommand extends Command<int> {
  _ValidateCommand() {
    argParser
      ..addOption('asset-dir',
          help: 'Directory containing generated JSON assets.',
          defaultsTo: _kDefaultOutputDir)
      ..addOption('report',
          help: 'Optional path to write a text report to.',
          defaultsTo: 'build/data_validation_report.txt');
  }

  @override
  String get name => 'validate';
  @override
  String get description =>
      'Validate generated JSON assets against the PoeMath schema.';

  @override
  int run() {
    final assetDir = argResults!['asset-dir'] as String;
    final reportPath = argResults!['report'] as String;
    final report = SchemaValidator().validateAll(assetDir);
    final rendered = report.render();
    print(rendered);
    final reportFile = File(reportPath);
    reportFile.parent.createSync(recursive: true);
    reportFile.writeAsStringSync(rendered);
    print('report written to $reportPath');
    return report.ok ? 0 : 1;
  }
}
