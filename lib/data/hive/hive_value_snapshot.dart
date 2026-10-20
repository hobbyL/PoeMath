// Adapter-backed value snapshots for migration integrity checks.
import 'dart:convert';

import 'package:hive/hive.dart';

/// Uses the same public adapters as persistence, including every written field.
class HiveValueSnapshot {
  HiveValueSnapshot._();
  static final List<
          ({bool Function(Object) matches, Object Function(Object) read})>
      _adapters = [];

  static void registerAdapter<T>(TypeAdapter<T> adapter) {
    _adapters.add(
      (
        matches: (value) => value is T,
        read: (value) {
          final writer = _SnapshotWriter();
          adapter.write(writer, value as T);
          return [adapter.typeId, writer.operations];
        },
      ),
    );
  }

  static String encode(Object? value) => jsonEncode(_value(value));

  static Object? _value(Object? value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is DateTime) {
      return ['date', value.microsecondsSinceEpoch, value.isUtc];
    }
    if (value is List) return value.map(_value).toList();
    if (value is Map) {
      return [
        'map',
        for (final entry in value.entries)
          [_value(entry.key), _value(entry.value)],
      ];
    }
    for (final adapter in _adapters) {
      if (adapter.matches(value)) return adapter.read(value);
    }
    throw StateError('No migration snapshot adapter for ${value.runtimeType}');
  }
}

/// Records adapter writes without using Hive private binary implementations.
class _SnapshotWriter implements BinaryWriter {
  final List<Object?> operations = [];

  @override
  void write<T>(T value, {bool writeTypeId = true}) {
    operations.add(['write', writeTypeId, HiveValueSnapshot._value(value)]);
  }

  @override
  void writeByte(int byte) => operations.add(['byte', byte]);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    operations.add([
      invocation.memberName.toString(),
      invocation.positionalArguments.map(HiveValueSnapshot._value).toList(),
    ]);
  }
}
