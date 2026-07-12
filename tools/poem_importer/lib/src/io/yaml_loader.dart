import 'dart:io';

import 'package:yaml/yaml.dart';

/// Reads a YAML file from [path] and converts the top-level structure into
/// plain Dart primitives (`Map<String, dynamic>` / `List<dynamic>`).
///
/// Throws [FileSystemException] if the file does not exist and [FormatException]
/// if the YAML root is neither a map nor a list.
Object loadYamlFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw FileSystemException('YAML source not found', path);
  }
  final raw = file.readAsStringSync();
  final parsed = loadYaml(raw);
  return _unwrap(parsed);
}

/// Recursively converts [YamlMap] / [YamlList] into standard Dart collections
/// so downstream code can use `Map<String, dynamic>` / `List<dynamic>` idioms.
Object _unwrap(Object? node) {
  if (node is YamlMap) {
    final result = <String, dynamic>{};
    node.forEach((key, value) {
      result[key.toString()] = _unwrap(value as Object?);
    });
    return result;
  }
  if (node is YamlList) {
    return node.map((e) => _unwrap(e as Object?)).toList();
  }
  return node ?? '';
}

/// Convenience: expects the file's root to be a Map.
Map<String, dynamic> loadYamlMap(String path) {
  final value = loadYamlFile(path);
  if (value is! Map<String, dynamic>) {
    throw FormatException('Expected YAML map at root of $path');
  }
  return value;
}

/// Convenience: expects the file's root to be a List.
List<dynamic> loadYamlList(String path) {
  final value = loadYamlFile(path);
  if (value is! List<dynamic>) {
    throw FormatException('Expected YAML list at root of $path');
  }
  return value;
}
