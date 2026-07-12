import 'dart:convert';
import 'dart:io';

/// Result of a validation pass. `errors` are hard failures, `warnings` are
/// soft issues that should be reported but do not fail the run.
class ValidationReport {
  ValidationReport();
  final List<String> errors = <String>[];
  final List<String> warnings = <String>[];

  bool get ok => errors.isEmpty;

  String render() {
    final buf = StringBuffer();
    buf.writeln('errors: ${errors.length}');
    buf.writeln('warnings: ${warnings.length}');
    if (errors.isNotEmpty) {
      buf.writeln('\n[ERRORS]');
      for (final e in errors) {
        buf.writeln('- $e');
      }
    }
    if (warnings.isNotEmpty) {
      buf.writeln('\n[WARNINGS]');
      for (final w in warnings) {
        buf.writeln('- $w');
      }
    }
    return buf.toString();
  }
}

/// Validates the shape of the generated JSON asset files. Not a strict schema
/// enforcer; catches the mistakes we've historically seen (missing fields,
/// pinyin/content length mismatch, out-of-range grade, duplicate ids).
class SchemaValidator {
  ValidationReport validateAll(String assetDir) {
    final report = ValidationReport();
    _validatePoems('$assetDir/poems_core.json', report, expectRequired: true);
    _validatePoems('$assetDir/poems_extended.json', report,
        expectRequired: false);
    _validatePoems('$assetDir/poems_explore.json', report,
        expectRequired: false);
    _validateAuthors('$assetDir/authors.json', report);
    _validateFormulas('$assetDir/formulas.json', report);
    return report;
  }

  void _validatePoems(
    String path,
    ValidationReport report, {
    required bool expectRequired,
  }) {
    final file = File(path);
    if (!file.existsSync()) {
      report.errors.add('missing file: $path');
      return;
    }
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! List) {
      report.errors.add('$path: root must be a JSON array');
      return;
    }
    final seenIds = <String>{};
    for (var i = 0; i < decoded.length; i++) {
      final entry = decoded[i];
      final loc = '$path[$i]';
      if (entry is! Map<String, dynamic>) {
        report.errors.add('$loc: not an object');
        continue;
      }
      for (final field in const <String>[
        'id',
        'title',
        'author',
        'dynasty',
        'content',
        'pinyin',
        'layer',
      ]) {
        if (!entry.containsKey(field) || entry[field] == null) {
          report.errors.add('$loc: missing required field "$field"');
        }
      }
      final id = entry['id'] as String?;
      if (id != null && !seenIds.add(id)) {
        report.errors.add('$loc: duplicate id "$id"');
      }
      final grade = entry['grade'];
      if (grade is int && (grade < 1 || grade > 6)) {
        report.errors.add('$loc: grade $grade out of range 1..6');
      }
      final content = entry['content'] as String?;
      final pinyin = entry['pinyin'] as String?;
      if (content != null && pinyin != null) {
        final chineseCount = _chineseCharCount(content);
        final syllableCount = _pinyinSyllableCount(pinyin);
        if (chineseCount > 0 && syllableCount != chineseCount) {
          report.warnings.add(
              '$loc: pinyin syllables ($syllableCount) != content chars ($chineseCount)');
        }
      }
      if (expectRequired) {
        final isRequired = entry['is_required'];
        if (isRequired != true && isRequired != false) {
          report.warnings.add('$loc: is_required not set (expected bool)');
        }
      }
    }
  }

  void _validateAuthors(String path, ValidationReport report) {
    final file = File(path);
    if (!file.existsSync()) {
      report.errors.add('missing file: $path');
      return;
    }
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! List) {
      report.errors.add('$path: root must be a JSON array');
      return;
    }
    final seenIds = <String>{};
    for (var i = 0; i < decoded.length; i++) {
      final entry = decoded[i];
      final loc = '$path[$i]';
      if (entry is! Map<String, dynamic>) {
        report.errors.add('$loc: not an object');
        continue;
      }
      for (final field in const <String>['id', 'name', 'dynasty']) {
        if (!entry.containsKey(field) || entry[field] == null) {
          report.errors.add('$loc: missing required field "$field"');
        }
      }
      final id = entry['id'] as String?;
      if (id != null && !seenIds.add(id)) {
        report.errors.add('$loc: duplicate id "$id"');
      }
    }
  }

  void _validateFormulas(String path, ValidationReport report) {
    final file = File(path);
    if (!file.existsSync()) {
      report.errors.add('missing file: $path');
      return;
    }
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! List) {
      report.errors.add('$path: root must be a JSON array');
      return;
    }
    final seenIds = <String>{};
    for (var i = 0; i < decoded.length; i++) {
      final entry = decoded[i];
      final loc = '$path[$i]';
      if (entry is! Map<String, dynamic>) {
        report.errors.add('$loc: not an object');
        continue;
      }
      for (final field in const <String>[
        'id',
        'category',
        'name',
        'formula_text',
        'formula_latex',
        'grade',
      ]) {
        if (!entry.containsKey(field) || entry[field] == null) {
          report.errors.add('$loc: missing required field "$field"');
        }
      }
      final id = entry['id'] as String?;
      if (id != null && !seenIds.add(id)) {
        report.errors.add('$loc: duplicate id "$id"');
      }
      final grade = entry['grade'];
      if (grade is int && (grade < 1 || grade > 6)) {
        report.errors.add('$loc: grade $grade out of range 1..6');
      }
    }
  }

  int _chineseCharCount(String text) {
    var count = 0;
    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code >= 0x4E00 && code <= 0x9FFF) count++;
    }
    return count;
  }

  int _pinyinSyllableCount(String pinyin) {
    // A syllable is a whitespace-separated token that contains at least one
    // ASCII letter. Punctuation-only tokens (「，」etc.) are ignored.
    var count = 0;
    for (final token in pinyin.split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      if (RegExp(r'[a-zA-Züǖǘǚǜāáǎàēéěèīíǐìōóǒòūúǔùńň]').hasMatch(token)) {
        count++;
      }
    }
    return count;
  }
}
