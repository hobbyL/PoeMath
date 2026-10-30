import 'dart:convert';

import 'package:poemath/domain/textbook_exercise.dart';

class TextbookExerciseRecord {
  const TextbookExerciseRecord({
    required this.fingerprint,
    this.attempts = 0,
    this.automaticCorrect = 0,
    this.automaticIncorrect = 0,
    this.parentConfirms = 0,
    this.parentAgain = 0,
    this.lastAnswer,
    this.lastResult,
    this.lastItemResults = const [],
    this.lastDay,
    this.lastParentDay,
  });

  final String fingerprint;
  final int attempts;
  final int automaticCorrect;
  final int automaticIncorrect;
  final int parentConfirms;
  final int parentAgain;
  final TextbookExerciseAnswer? lastAnswer;
  final TextbookExerciseResult? lastResult;
  final List<bool> lastItemResults;
  final String? lastDay;
  final String? lastParentDay;

  TextbookExerciseRecord copyWith({
    int? attempts,
    int? automaticCorrect,
    int? automaticIncorrect,
    int? parentConfirms,
    int? parentAgain,
    TextbookExerciseAnswer? lastAnswer,
    TextbookExerciseResult? lastResult,
    List<bool>? lastItemResults,
    String? lastDay,
    String? lastParentDay,
  }) =>
      TextbookExerciseRecord(
        fingerprint: fingerprint,
        attempts: attempts ?? this.attempts,
        automaticCorrect: automaticCorrect ?? this.automaticCorrect,
        automaticIncorrect: automaticIncorrect ?? this.automaticIncorrect,
        parentConfirms: parentConfirms ?? this.parentConfirms,
        parentAgain: parentAgain ?? this.parentAgain,
        lastAnswer: lastAnswer ?? this.lastAnswer,
        lastResult: lastResult ?? this.lastResult,
        lastItemResults: lastItemResults ?? this.lastItemResults,
        lastDay: lastDay ?? this.lastDay,
        lastParentDay: lastParentDay ?? this.lastParentDay,
      );

  Map<String, dynamic> toJson() => {
        'fingerprint': fingerprint,
        'attempts': attempts,
        'automaticCorrect': automaticCorrect,
        'automaticIncorrect': automaticIncorrect,
        'parentConfirms': parentConfirms,
        'parentAgain': parentAgain,
        'lastAnswer': lastAnswer?.toJson(),
        'lastResult': lastResult?.name,
        'lastItemResults': lastItemResults,
        'lastDay': lastDay,
        'lastParentDay': lastParentDay,
      };

  factory TextbookExerciseRecord.fromJson(Map<String, dynamic> json) {
    final result = json['lastResult'];
    if (result != null &&
        (result is! String ||
            !TextbookExerciseResult.values
                .any((item) => item.name == result))) {
      throw const FormatException('习题最近结果损坏');
    }
    final itemResults = json['lastItemResults'];
    if (itemResults is! List || itemResults.any((item) => item is! bool)) {
      throw const FormatException('习题逐项结果损坏');
    }
    return TextbookExerciseRecord(
      fingerprint: _string(json, 'fingerprint'),
      attempts: _integer(json, 'attempts'),
      automaticCorrect: _integer(json, 'automaticCorrect'),
      automaticIncorrect: _integer(json, 'automaticIncorrect'),
      parentConfirms: _integer(json, 'parentConfirms'),
      parentAgain: _integer(json, 'parentAgain'),
      lastAnswer: json['lastAnswer'] == null
          ? null
          : TextbookExerciseAnswer.fromJson(_map(json['lastAnswer'])),
      lastResult: result == null
          ? null
          : TextbookExerciseResult.values.byName(result as String),
      lastItemResults: List.unmodifiable(itemResults.cast<bool>()),
      lastDay: _day(json['lastDay']),
      lastParentDay: _day(json['lastParentDay']),
    );
  }
}

class TextbookExerciseProgress {
  const TextbookExerciseProgress({
    required this.profileId,
    required this.bookId,
    required this.editionId,
    this.revision = 0,
    this.records = const {},
    this.operations = const [],
  });

  final String profileId;
  final String bookId;
  final String editionId;
  final int revision;
  final Map<String, TextbookExerciseRecord> records;
  final List<String> operations;

  static String targetKey(String lessonId, String exerciseId) =>
      jsonEncode([lessonId, exerciseId]);

  TextbookExerciseProgress copyWith({
    int? revision,
    Map<String, TextbookExerciseRecord>? records,
    List<String>? operations,
  }) =>
      TextbookExerciseProgress(
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
        'records': records.map((key, value) => MapEntry(key, value.toJson())),
        'operations': operations,
      };

  factory TextbookExerciseProgress.fromJson(Map<String, dynamic> json) {
    if (json['v'] != 1) throw const FormatException('习题记录版本不支持');
    final rawRecords = _map(json['records']);
    final operations = _strings(json, 'operations');
    if (rawRecords.length > 20000 || operations.length > 200) {
      throw const FormatException('习题记录超过范围');
    }
    for (final key in rawRecords.keys) {
      final identity = jsonDecode(key);
      if (identity is! List ||
          identity.length != 2 ||
          identity.any((value) => value is! String || value.isEmpty)) {
        throw const FormatException('习题记录目标归属损坏');
      }
    }
    return TextbookExerciseProgress(
      profileId: _string(json, 'profileId'),
      bookId: _string(json, 'bookId'),
      editionId: _string(json, 'editionId'),
      revision: _integer(json, 'revision'),
      records: rawRecords.map(
        (key, value) =>
            MapEntry(key, TextbookExerciseRecord.fromJson(_map(value))),
      ),
      operations: operations,
    );
  }
}

int _integer(Map<String, dynamic> json, String key, [int? max]) {
  final value = json[key];
  if (value is! int || value < 0 || max != null && value > max) {
    throw FormatException('习题记录 $key 损坏');
  }
  return value;
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('习题记录 $key 损坏');
  }
  return value;
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('习题记录对象损坏');
  }
  return value;
}

List<String> _strings(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('习题记录 $key 损坏');
  }
  return List.unmodifiable(value.cast<String>());
}

String? _day(Object? value) {
  if (value == null) return null;
  if (value is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
      DateTime.tryParse(value) == null ||
      DateTime.parse(value).toIso8601String().substring(0, 10) != value) {
    throw const FormatException('习题日期损坏');
  }
  return value;
}
