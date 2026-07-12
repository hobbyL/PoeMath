import 'dart:convert';
import 'dart:io';

/// Writes [payload] to [path] as pretty-printed UTF-8 JSON.
///
/// Creates parent directories as needed. Overwrites existing files.
void writeJson(String path, Object payload) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  file.writeAsStringSync('${encoder.convert(payload)}\n');
}
