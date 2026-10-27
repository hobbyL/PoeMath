import 'dart:convert';

/// 写一写单字记录与整册进度。
///
/// 与认一认（`textbook_recognition_progress.dart`）同构：整册一个 JSON 对象
/// 存在加密 settings box 的单键里，`revision` + `operations` 提供乐观并发与
/// 幂等。字段语义见任务 design.md 2.3。
class WritingRecord {
  const WritingRecord({
    required this.fingerprint,
    this.traceCount = 0,
    this.freeCount = 0,
    this.geometryPasses = 0,
    this.parentConfirms = 0,
    this.stage = 0,
    this.lastParentDay,
    this.nextDay,
    this.lastDay,
    this.advancedDay,
  });
  final String fingerprint;

  /// 已完成描红 / 空格自写的次数（事实记录，不做闯关拦截）。
  final int traceCount, freeCount;

  /// 几何比对通过次数、家长确认通过次数。
  final int geometryPasses, parentConfirms;
  final int stage;
  final String? lastParentDay, nextDay, lastDay, advancedDay;

  /// 总览小标（design 2.3）：未练 → 已描红 → 已自写通过。
  WritingBadge get badge {
    if (geometryPasses > 0 || parentConfirms > 0) return WritingBadge.written;
    if (traceCount > 0 || freeCount > 0) return WritingBadge.traced;
    return WritingBadge.none;
  }

  WritingRecord copy({
    int? traceCount,
    int? freeCount,
    int? geometryPasses,
    int? parentConfirms,
    int? stage,
    String? lastParentDay,
    String? nextDay,
    String? lastDay,
    String? advancedDay,
  }) =>
      WritingRecord(
        fingerprint: fingerprint,
        traceCount: traceCount ?? this.traceCount,
        freeCount: freeCount ?? this.freeCount,
        geometryPasses: geometryPasses ?? this.geometryPasses,
        parentConfirms: parentConfirms ?? this.parentConfirms,
        stage: stage ?? this.stage,
        lastParentDay: lastParentDay ?? this.lastParentDay,
        nextDay: nextDay ?? this.nextDay,
        lastDay: lastDay ?? this.lastDay,
        advancedDay: advancedDay ?? this.advancedDay,
      );

  Map<String, dynamic> toJson() => {
        'fingerprint': fingerprint,
        'traceCount': traceCount,
        'freeCount': freeCount,
        'geometryPasses': geometryPasses,
        'parentConfirms': parentConfirms,
        'stage': stage,
        'lastParentDay': lastParentDay,
        'nextDay': nextDay,
        'lastDay': lastDay,
        'advancedDay': advancedDay,
      };

  factory WritingRecord.fromJson(Map<String, dynamic> j) => WritingRecord(
        fingerprint: _string(j, 'fingerprint'),
        traceCount: _integer(j, 'traceCount'),
        freeCount: _integer(j, 'freeCount'),
        geometryPasses: _integer(j, 'geometryPasses'),
        parentConfirms: _integer(j, 'parentConfirms'),
        stage: _integer(j, 'stage', 4),
        lastParentDay: _day(j['lastParentDay']),
        nextDay: _day(j['nextDay']),
        lastDay: _day(j['lastDay']),
        advancedDay: _day(j['advancedDay']),
      );
}

enum WritingBadge { none, traced, written }

class WritingProgress {
  const WritingProgress({
    required this.profileId,
    required this.bookId,
    required this.editionId,
    this.revision = 0,
    this.records = const {},
    this.operations = const [],
  });
  final String profileId, bookId, editionId;
  final int revision;

  /// 键为 `writingProgressKey(lessonId, targetId)` 的 JSON 编码组合。
  final Map<String, WritingRecord> records;
  final List<String> operations;

  static String targetKey(String lesson, String target) =>
      jsonEncode([lesson, target]);

  WritingProgress copy({
    Map<String, WritingRecord>? records,
    int? revision,
    List<String>? operations,
  }) =>
      WritingProgress(
        profileId: profileId,
        bookId: bookId,
        editionId: editionId,
        revision: revision ?? this.revision,
        records: records ?? this.records,
        operations: operations ?? this.operations,
      );

  Map<String, dynamic> toJson() => {
        'v': 1,
        'profileId': profileId,
        'bookId': bookId,
        'editionId': editionId,
        'revision': revision,
        'records': records.map((k, v) => MapEntry(k, v.toJson())),
        'operations': operations,
      };

  factory WritingProgress.fromJson(Map<String, dynamic> j) {
    if (j['v'] != 1) throw const FormatException('写字记录版本不支持');
    final raw = _map(j['records']);
    if (raw.length > 20000 ||
        _list(j['operations'], (v) => v as String).length > 200) {
      throw const FormatException('写字记录超过范围');
    }
    for (final k in raw.keys) {
      final identity = jsonDecode(k);
      if (identity is! List ||
          identity.length != 2 ||
          identity.any((v) => v is! String || v.isEmpty)) {
        throw const FormatException('写字记录目标归属损坏');
      }
    }
    return WritingProgress(
      profileId: _string(j, 'profileId'),
      bookId: _string(j, 'bookId'),
      editionId: _string(j, 'editionId'),
      revision: _integer(j, 'revision'),
      records:
          raw.map((k, v) => MapEntry(k, WritingRecord.fromJson(_map(v)))),
      operations: _list(j['operations'], (v) => v as String),
    );
  }
}

int _integer(Map<String, dynamic> j, String key, [int? max]) {
  final v = j[key];
  if (v is! int || v < 0 || (max != null && v > max)) {
    throw const FormatException('写字记录数值损坏');
  }
  return v;
}

String _string(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v is! String || v.isEmpty) throw const FormatException('写字记录标识损坏');
  return v;
}

Map<String, dynamic> _map(Object? v) {
  if (v is! Map<String, dynamic>) throw const FormatException('写字记录格式损坏');
  return v;
}

List<T> _list<T>(Object? v, T Function(Object?) decode) {
  if (v is! List || v.length > 20000) throw const FormatException('写字记录列表损坏');
  return v.map(decode).toList();
}

String? _day(Object? v) {
  if (v == null) return null;
  if (v is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) ||
      DateTime.tryParse(v) == null) {
    throw const FormatException('写字复习日期损坏');
  }
  if (DateTime.parse(v).toIso8601String().substring(0, 10) != v) {
    throw const FormatException('写字复习日期损坏');
  }
  return v;
}