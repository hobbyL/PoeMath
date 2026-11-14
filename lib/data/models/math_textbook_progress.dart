import 'dart:convert';

import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart'
    show textbookTextDigest, textbookContentDigest;
import 'package:poemath/domain/math_textbook_grading.dart';
import 'package:poemath/domain/math_textbook_practice.dart';

class MathTextbookAttempt {
  MathTextbookAttempt({
    required this.id,
    required this.sessionId,
    required this.lessonId,
    required this.lessonTitle,
    required this.lessonDigest,
    required this.scopeDigest,
    required this.item,
    required Map<String, String> answers,
    required this.result,
    required Map<String, bool?> fieldResults,
    required this.createdAt,
    this.planId,
    this.parentReviewer,
    this.parentReviewedAt,
  }) : answers = Map.unmodifiable(answers),
       fieldResults = Map.unmodifiable(fieldResults);
  final String id, sessionId, lessonId, lessonTitle, lessonDigest, scopeDigest;
  final String? planId, parentReviewer;
  final DateTime createdAt;
  final DateTime? parentReviewedAt;
  final MathTextbookPracticeItem item;
  final Map<String, String> answers;
  final MathTextbookResult result;
  final Map<String, bool?> fieldResults;
  String get targetKey =>
      MathTextbookProgress.targetKey(lessonId, planId, item.exercise.id);
  MathTextbookAttempt checked({
    required bool passed,
    required String reviewer,
    required DateTime at,
  }) => MathTextbookAttempt(
    id: id,
    sessionId: sessionId,
    lessonId: lessonId,
    lessonTitle: lessonTitle,
    lessonDigest: lessonDigest,
    scopeDigest: scopeDigest,
    planId: planId,
    item: item,
    answers: answers,
    fieldResults: fieldResults,
    createdAt: createdAt,
    result: passed
        ? MathTextbookResult.parentCorrect
        : MathTextbookResult.parentAgain,
    parentReviewer: reviewer,
    parentReviewedAt: at,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'lessonId': lessonId,
    'lessonTitle': lessonTitle,
    'lessonDigest': lessonDigest,
    'scopeDigest': scopeDigest,
    'planId': planId,
    'item': item.toJson(),
    'answers': answers,
    'result': result.name,
    'fieldResults': fieldResults,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'parentReviewer': parentReviewer,
    'parentReviewedAt': parentReviewedAt?.toUtc().toIso8601String(),
  };
  factory MathTextbookAttempt.fromJson(Object? value) {
    final raw = _map(value),
        item = MathTextbookPracticeItem.fromJson(_map(raw['item']));
    final answers = _map(raw['answers']).map(
      (key, value) =>
          MapEntry(key, _string(value, '作答', max: 10000, empty: true)),
    );
    if (!mathTextbookAnswersComplete(item.exercise, answers)) {
      throw const FormatException('保存的作答缺少完整答案');
    }
    final evaluation = gradeMathTextbookExercise(item.exercise, answers);
    final results = _map(raw['fieldResults']).map((key, value) {
      if (value != null && value is! bool) {
        throw const FormatException('逐项核对结果无效');
      }
      return MapEntry(key, value as bool?);
    });
    if (jsonEncode(results) != jsonEncode(evaluation.fields)) {
      if (results.length != evaluation.fields.length ||
          results.entries.any(
            (e) =>
                evaluation.fields[e.key] != e.value ||
                !evaluation.fields.containsKey(e.key),
          )) {
        throw const FormatException('作答与逐项判分不一致');
      }
    }
    final result = _result(raw['result']);
    final reviewer = raw['parentReviewer'] == null
        ? null
        : _string(raw['parentReviewer'], '核对人', max: 100);
    final reviewed = raw['parentReviewedAt'] == null
        ? null
        : _date(raw['parentReviewedAt']);
    final created = _date(raw['createdAt']);
    if (reviewed != null && reviewed.isBefore(created)) {
      throw const FormatException('家长核对时间早于作答');
    }
    if (result == MathTextbookResult.parentCorrect ||
        result == MathTextbookResult.parentAgain) {
      if (!item.exercise.needsParent ||
          reviewer == null ||
          reviewed == null ||
          result == MathTextbookResult.parentCorrect &&
              evaluation.result == MathTextbookResult.incorrect) {
        throw const FormatException('家长核对记录无效');
      }
    } else if (result != evaluation.result ||
        reviewer != null ||
        reviewed != null) {
      throw const FormatException('答案与数学判分不一致');
    }
    return MathTextbookAttempt(
      id: _string(raw['id'], '作答标识'),
      sessionId: _string(raw['sessionId'], '练习标识'),
      lessonId: _string(raw['lessonId'], '课时标识'),
      lessonTitle: _string(raw['lessonTitle'], '课时名称', max: 200),
      lessonDigest: _hash(raw['lessonDigest']),
      scopeDigest: _hash(raw['scopeDigest']),
      item: item,
      answers: answers,
      fieldResults: results,
      result: result,
      createdAt: created,
      planId: raw['planId'] == null ? null : _string(raw['planId'], '计划标识'),
      parentReviewer: reviewer,
      parentReviewedAt: reviewed,
    );
  }
}

class MathTextbookTargetRecord {
  const MathTextbookTargetRecord({
    required this.scopeDigest,
    required this.sessionId,
    required this.attemptId,
    required this.result,
    this.attempts = 0,
    this.automaticCorrect = 0,
    this.automaticIncorrect = 0,
    this.parentChecks = 0,
  });
  final String scopeDigest, sessionId, attemptId;
  final MathTextbookResult result;
  final int attempts, automaticCorrect, automaticIncorrect, parentChecks;
  bool get passed =>
      result == MathTextbookResult.correct ||
      result == MathTextbookResult.parentCorrect;
  Map<String, dynamic> toJson() => {
    'scopeDigest': scopeDigest,
    'sessionId': sessionId,
    'attemptId': attemptId,
    'result': result.name,
    'attempts': attempts,
    'automaticCorrect': automaticCorrect,
    'automaticIncorrect': automaticIncorrect,
    'parentChecks': parentChecks,
  };
  factory MathTextbookTargetRecord.fromJson(Object? value) {
    final raw = _map(value),
        attempts = _integer(raw['attempts']),
        correct = _integer(raw['automaticCorrect']),
        incorrect = _integer(raw['automaticIncorrect']);
    if (correct + incorrect > attempts) {
      throw const FormatException('数学自动答题计数无效');
    }
    return MathTextbookTargetRecord(
      scopeDigest: _hash(raw['scopeDigest']),
      sessionId: _string(raw['sessionId'], '练习标识'),
      attemptId: _string(raw['attemptId'], '最近作答标识'),
      result: _result(raw['result']),
      attempts: attempts,
      automaticCorrect: correct,
      automaticIncorrect: incorrect,
      parentChecks: _integer(raw['parentChecks']),
    );
  }
}

class MathTextbookProgress {
  MathTextbookProgress({
    required this.profileId,
    required this.bookId,
    required this.editionId,
    this.revision = 0,
    Map<String, String> readLessons = const {},
    Map<String, MathTextbookTargetRecord> targets = const {},
    List<MathTextbookAttempt> history = const [],
    List<String> operations = const [],
  }) : readLessons = Map.unmodifiable(readLessons),
       targets = Map.unmodifiable(targets),
       history = List.unmodifiable(history),
       operations = List.unmodifiable(operations);
  static const prefix = 'textbook_math_v1:';
  static const maxHistory = 300;
  static const maxBytes = 4 * 1024 * 1024;
  final String profileId, bookId, editionId;
  final int revision;
  final Map<String, String> readLessons;
  final Map<String, MathTextbookTargetRecord> targets;
  final List<MathTextbookAttempt> history;
  final List<String> operations;
  static String keyFor(String profileId, String bookId, String editionId) =>
      '$prefix${textbookTextDigest(jsonEncode([profileId, bookId, editionId]))}';
  static String targetKey(String lessonId, String? planId, String exerciseId) =>
      jsonEncode([lessonId, planId, exerciseId]);
  String get key => keyFor(profileId, bookId, editionId);
  MathTextbookProgress copyWith({
    int? revision,
    Map<String, String>? readLessons,
    Map<String, MathTextbookTargetRecord>? targets,
    List<MathTextbookAttempt>? history,
    List<String>? operations,
  }) => MathTextbookProgress(
    profileId: profileId,
    bookId: bookId,
    editionId: editionId,
    revision: revision ?? this.revision,
    readLessons: readLessons ?? this.readLessons,
    targets: targets ?? this.targets,
    history: history ?? this.history,
    operations: operations ?? this.operations,
  );
  Map<String, dynamic> toJson() => {
    'v': 1,
    'profileId': profileId,
    'bookId': bookId,
    'editionId': editionId,
    'revision': revision,
    'readLessons': readLessons,
    'targets': targets.map((key, value) => MapEntry(key, value.toJson())),
    'history': history.map((a) => a.toJson()).toList(),
    'operations': operations,
  };
  factory MathTextbookProgress.fromJson(Object? value) {
    final raw = _map(value);
    if (raw['v'] != 1) throw const FormatException('数学教材进度版本不支持');
    final reads = _map(raw['readLessons']),
        targets = _map(raw['targets']),
        history = _list(raw['history'], maxHistory),
        operations = _list(raw['operations'], 1000);
    if (reads.length > 1000 || targets.length > 20000) {
      throw const FormatException('数学教材进度超过范围');
    }
    for (final key in targets.keys) {
      final values = jsonDecode(key);
      if (values is! List ||
          values.length != 3 ||
          values[0] is! String ||
          (values[1] != null && values[1] is! String) ||
          values[2] is! String ||
          (values[0] as String).isEmpty ||
          (values[2] as String).isEmpty) {
        throw const FormatException('数学学习目标标识无效');
      }
    }
    final records = history.map(MathTextbookAttempt.fromJson).toList();
    final ops = operations.map((v) => _string(v, '操作标识')).toList();
    if (records.map((r) => r.id).toSet().length != records.length ||
        ops.toSet().length != ops.length) {
      throw const FormatException('数学学习操作重复');
    }
    final decoded = targets.map(
      (key, value) => MapEntry(key, MathTextbookTargetRecord.fromJson(value)),
    );
    for (final record in records) {
      final latest = decoded[record.targetKey];
      if (latest?.attemptId == record.id &&
          (latest!.scopeDigest != record.scopeDigest ||
              latest.result != record.result ||
              latest.sessionId != record.sessionId)) {
        throw const FormatException('数学历史与当前记录不一致');
      }
    }
    return MathTextbookProgress(
      profileId: _string(raw['profileId'], '档案标识'),
      bookId: _hash(raw['bookId']),
      editionId: _string(raw['editionId'], '教材版次'),
      revision: _integer(raw['revision']),
      readLessons: reads.map(
        (key, value) => MapEntry(_string(key, '已读课时'), _hash(value)),
      ),
      targets: decoded,
      history: records,
      operations: ops,
    );
  }
}

class MathTextbookPracticeDraft {
  MathTextbookPracticeDraft({
    required this.sessionId,
    required this.profileId,
    required this.bookId,
    required this.editionId,
    required this.lessonId,
    required this.lessonDigest,
    required List<MathTextbookPracticeItem> items,
    required List<String> operationIds,
    required this.startedAt,
    this.planId,
    this.planDigest,
    this.seed,
    this.finishedAt,
    this.index = 0,
    this.elapsedSeconds = 0,
    List<Map<String, String>>? answers,
    List<MathTextbookResult?>? results,
  }) : items = List.unmodifiable(items),
       operationIds = List.unmodifiable(operationIds),
       answers = List.unmodifiable(
         (answers ?? List.generate(items.length, (_) => <String, String>{}))
             .map(Map<String, String>.unmodifiable),
       ),
       results = List.unmodifiable(
         results ?? List<MathTextbookResult?>.filled(items.length, null),
       );
  final String sessionId, profileId, bookId, editionId, lessonId, lessonDigest;
  final String? planId, planDigest;
  final int? seed;
  final List<MathTextbookPracticeItem> items;
  final List<String> operationIds;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int index, elapsedSeconds;
  final List<Map<String, String>> answers;
  final List<MathTextbookResult?> results;
  String get scope => jsonEncode([bookId, lessonId, planId]);
  String get fingerprint => textbookContentDigest({
    'sessionId': sessionId,
    'profileId': profileId,
    'bookId': bookId,
    'editionId': editionId,
    'lessonId': lessonId,
    'lessonDigest': lessonDigest,
    'planId': planId,
    'planDigest': planDigest,
    'seed': seed,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'items': items.map((item) => item.toJson()).toList(),
    'operationIds': operationIds,
  });
  MathTextbookPracticeDraft copyWith({
    int? index,
    int? elapsedSeconds,
    List<Map<String, String>>? answers,
    List<MathTextbookResult?>? results,
    DateTime? finishedAt,
  }) => MathTextbookPracticeDraft(
    sessionId: sessionId,
    profileId: profileId,
    bookId: bookId,
    editionId: editionId,
    lessonId: lessonId,
    lessonDigest: lessonDigest,
    items: items,
    operationIds: operationIds,
    startedAt: startedAt,
    planId: planId,
    planDigest: planDigest,
    seed: seed,
    finishedAt: finishedAt ?? this.finishedAt,
    index: index ?? this.index,
    elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    answers: answers ?? this.answers,
    results: results ?? this.results,
  );
  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'profileId': profileId,
    'bookId': bookId,
    'editionId': editionId,
    'lessonId': lessonId,
    'lessonDigest': lessonDigest,
    'planId': planId,
    'planDigest': planDigest,
    'seed': seed,
    'finishedAt': finishedAt?.toUtc().toIso8601String(),
    'items': items.map((i) => i.toJson()).toList(),
    'operationIds': operationIds,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'index': index,
    'elapsedSeconds': elapsedSeconds,
    'answers': answers,
    'results': results.map((r) => r?.name).toList(),
  };
  factory MathTextbookPracticeDraft.fromJson(Object? value) {
    final raw = _map(value),
        items = _list(
          raw['items'],
          1000,
        ).map((v) => MathTextbookPracticeItem.fromJson(_map(v))).toList();
    final ops = _list(
      raw['operationIds'],
      1000,
    ).map((v) => _string(v, '草稿操作标识')).toList();
    final answers = _list(raw['answers'], 1000)
        .map(
          (v) => _map(v).map(
            (key, value) =>
                MapEntry(key, _string(value, '草稿答案', max: 10000, empty: true)),
          ),
        )
        .toList();
    final results = _list(
      raw['results'],
      1000,
    ).map((v) => v == null ? null : _result(v)).toList();
    final index = _integer(raw['index']),
        elapsed = _integer(raw['elapsedSeconds']);
    if (items.isEmpty ||
        ops.length != items.length ||
        answers.length != items.length ||
        results.length != items.length ||
        index > items.length ||
        items.map((item) => item.exercise.id).toSet().length != items.length ||
        ops.toSet().length != ops.length) {
      throw const FormatException('数学练习草稿缺少题目或位置无效');
    }
    if (raw['planId'] != null &&
            (raw['seed'] == null || raw['planDigest'] == null) ||
        raw['planId'] == null &&
            (raw['seed'] != null || raw['planDigest'] != null) ||
        raw['finishedAt'] != null &&
            (index != items.length ||
                results.any((result) => result == null))) {
      throw const FormatException('数学练习草稿计划或结束状态无效');
    }
    for (var i = 0; i < items.length; i++) {
      final fields = items[i].exercise.fields.map((field) => field.id).toSet();
      if (answers[i].keys.any((key) => !fields.contains(key)) ||
          i < index && results[i] == null ||
          i > index && results[i] != null) {
        throw const FormatException('草稿作答项或提交位置无效');
      }
      if (results[i] != null &&
          (!mathTextbookAnswersComplete(items[i].exercise, answers[i]) ||
              gradeMathTextbookExercise(items[i].exercise, answers[i]).result !=
                  results[i])) {
        throw const FormatException('草稿答案与结果不一致');
      }
    }
    final started = _date(raw['startedAt']);
    final finished = raw['finishedAt'] == null
        ? null
        : _date(raw['finishedAt']);
    if (finished != null && finished.isBefore(started)) {
      throw const FormatException('草稿结束时间早于开始时间');
    }
    return MathTextbookPracticeDraft(
      sessionId: _string(raw['sessionId'], '草稿练习'),
      profileId: _string(raw['profileId'], '草稿档案'),
      bookId: _hash(raw['bookId']),
      editionId: _string(raw['editionId'], '草稿版次'),
      lessonId: _string(raw['lessonId'], '草稿课时'),
      lessonDigest: _hash(raw['lessonDigest']),
      planId: raw['planId'] == null ? null : _string(raw['planId'], '草稿计划'),
      planDigest: raw['planDigest'] == null ? null : _hash(raw['planDigest']),
      seed: raw['seed'] == null ? null : _integer(raw['seed']),
      finishedAt: finished,
      items: items,
      operationIds: ops,
      startedAt: started,
      index: index,
      elapsedSeconds: elapsed,
      answers: answers,
      results: results,
    );
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map<String, dynamic>) throw const FormatException('数学学习记录须为对象');
  return value;
}

List<dynamic> _list(Object? value, int max) {
  if (value is! List || value.length > max) {
    throw const FormatException('数学学习列表超过范围');
  }
  return value;
}

String _string(
  Object? value,
  String label, {
  int max = 160,
  bool empty = false,
}) {
  if (value is! String ||
      value.length > max ||
      !empty && value.trim().isEmpty) {
    throw FormatException('$label无效');
  }
  return value;
}

String _hash(Object? value) {
  final hash = _string(value, '数学学习摘要');
  if (!Textbook.isValidId(hash)) throw const FormatException('数学学习摘要无效');
  return hash;
}

int _integer(Object? value) {
  if (value is! int || value < 0 || value > 2147483647) {
    throw const FormatException('数学学习计数无效');
  }
  return value;
}

MathTextbookResult _result(Object? value) {
  final result = MathTextbookResult.values
      .where((r) => r.name == value)
      .firstOrNull;
  if (result == null) throw const FormatException('数学学习结果无效');
  return result;
}

DateTime _date(Object? value) {
  final date = DateTime.tryParse(_string(value, '数学学习时间', max: 40));
  if (date == null) throw const FormatException('数学学习时间无效');
  return date;
}
