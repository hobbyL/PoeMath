import 'dart:convert';

import 'package:poemath/core/services/tts/narration_audio_identity.dart';

enum RecognitionQuestionKind { study, read, listen, context }

enum RecognitionEvidence {
  study,
  selfCorrect,
  selfAgain,
  correct,
  incorrect,
  parentCorrect,
  parentAgain,
  oralCorrect,
  oralAgain,
}

int _integer(Map<String, dynamic> j, String key, [int? max]) {
  final v = j[key];
  if (v is! int || v < 0 || (max != null && v > max)) {
    throw const FormatException('认字记录数值损坏');
  }
  return v;
}

String _string(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v is! String || v.isEmpty) throw const FormatException('认字记录标识损坏');
  return v;
}

Map<String, dynamic> _map(Object? v) {
  if (v is! Map<String, dynamic>) throw const FormatException('认字记录格式损坏');
  return v;
}

List<T> _list<T>(Object? v, T Function(Object?) decode) {
  if (v is! List || v.length > 20000) throw const FormatException('认字记录列表损坏');
  return v.map(decode).toList();
}

class RecognitionRecord {
  const RecognitionRecord({
    required this.fingerprint,
    this.studies = 0,
    this.correct = 0,
    this.incorrect = 0,
    this.selfCorrect = 0,
    this.selfAgain = 0,
    this.hints = 0,
    this.oralCorrect = 0,
    this.oralAgain = 0,
    this.stage = 0,
    this.lastDay,
    this.nextDay,
    this.advancedDay,
    this.parentDay,
    this.parentPassed,
    this.checkedDay,
  });
  final String fingerprint;
  final int studies, correct, incorrect, selfCorrect, selfAgain, hints, stage;
  final int oralCorrect, oralAgain;
  final String? lastDay, nextDay, advancedDay, parentDay, checkedDay;
  final bool? parentPassed;
  Map<String, dynamic> toJson() => {
        'fingerprint': fingerprint,
        'studies': studies,
        'correct': correct,
        'incorrect': incorrect,
        'selfCorrect': selfCorrect,
        'selfAgain': selfAgain,
        'hints': hints,
        'oralCorrect': oralCorrect,
        'oralAgain': oralAgain,
        'stage': stage,
        'lastDay': lastDay,
        'nextDay': nextDay,
        'advancedDay': advancedDay,
        'parentDay': parentDay,
        'parentPassed': parentPassed,
        'checkedDay': checkedDay,
      };
  factory RecognitionRecord.fromJson(Map<String, dynamic> j) =>
      RecognitionRecord(
        fingerprint: _string(j, 'fingerprint'),
        studies: _integer(j, 'studies'),
        correct: _integer(j, 'correct'),
        incorrect: _integer(j, 'incorrect'),
        selfCorrect: _integer(j, 'selfCorrect'),
        selfAgain: _integer(j, 'selfAgain'),
        hints: _integer(j, 'hints'),
        oralCorrect:
            j.containsKey('oralCorrect') ? _integer(j, 'oralCorrect') : 0,
        oralAgain: j.containsKey('oralAgain') ? _integer(j, 'oralAgain') : 0,
        stage: _integer(j, 'stage', 4),
        lastDay: _day(j['lastDay']),
        nextDay: _day(j['nextDay']),
        advancedDay: _day(j['advancedDay']),
        parentDay: _day(j['parentDay']),
        checkedDay: _day(j['checkedDay']),
        parentPassed: j['parentPassed'] as bool?,
      );
}

String? _day(Object? v) {
  if (v == null) return null;
  if (v is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) ||
      DateTime.tryParse(v) == null) {
    throw const FormatException('认字复习日期损坏');
  }
  if (DateTime.parse(v).toIso8601String().substring(0, 10) != v) {
    throw const FormatException('认字复习日期损坏');
  }
  return v;
}

class RecognitionQuestion {
  const RecognitionQuestion({
    required this.id,
    required this.targetId,
    required this.kind,
    this.cueKey,
    this.options = const [],
    this.positions = const [],
    this.repeat = false,
  });
  final String id, targetId;
  final RecognitionQuestionKind kind;
  final String? cueKey;
  final List<String> options;
  final List<int> positions;
  final bool repeat;
  Map<String, dynamic> toJson() => {
        'id': id,
        'targetId': targetId,
        'kind': kind.name,
        'cueKey': cueKey,
        'options': options,
        'positions': positions,
        'repeat': repeat,
      };
  factory RecognitionQuestion.fromJson(Map<String, dynamic> j) =>
      RecognitionQuestion(
        id: _string(j, 'id'),
        targetId: _string(j, 'targetId'),
        kind: RecognitionQuestionKind.values.byName(_string(j, 'kind')),
        cueKey: j['cueKey'] as String?,
        options: _list(j['options'], (v) => v as String),
        positions: _list(j['positions'], (v) {
          if (v is! int || v < 0 || v > 40) {
            throw const FormatException('认字位置损坏');
          }
          return v;
        }),
        repeat: j['repeat'] as bool,
      );
}

class RecognitionSession {
  const RecognitionSession({
    required this.id,
    required this.lessonId,
    required this.fingerprint,
    required this.epoch,
    required this.startedAt,
    required this.questions,
    this.index = 0,
    this.hinted = false,
    this.feedback,
    this.repeated = const [],
    this.recognitionFirst = false,
  });
  final String id, lessonId, fingerprint, startedAt;
  final int epoch, index;
  final List<RecognitionQuestion> questions;
  final bool hinted;
  final bool recognitionFirst;
  final RecognitionEvidence? feedback;
  final List<String> repeated;
  bool get finished => index >= questions.length;
  RecognitionQuestion get question => questions[index];
  RecognitionSession copy({
    List<RecognitionQuestion>? questions,
    int? index,
    bool? hinted,
    RecognitionEvidence? feedback,
    bool clearFeedback = false,
    List<String>? repeated,
  }) =>
      RecognitionSession(
        id: id,
        lessonId: lessonId,
        fingerprint: fingerprint,
        epoch: epoch,
        startedAt: startedAt,
        questions: questions ?? this.questions,
        index: index ?? this.index,
        hinted: hinted ?? this.hinted,
        feedback: clearFeedback ? null : feedback ?? this.feedback,
        repeated: repeated ?? this.repeated,
        recognitionFirst: recognitionFirst,
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'lessonId': lessonId,
        'fingerprint': fingerprint,
        'epoch': epoch,
        'startedAt': startedAt,
        'questions': questions.map((q) => q.toJson()).toList(),
        'index': index,
        'hinted': hinted,
        'feedback': feedback?.name,
        'repeated': repeated,
        'recognitionFirst': recognitionFirst,
      };
  factory RecognitionSession.fromJson(Map<String, dynamic> j) {
    final questions =
        _list(j['questions'], (v) => RecognitionQuestion.fromJson(_map(v)));
    final index = _integer(j, 'index', questions.length);
    if (questions.isEmpty ||
        questions.length > 40 ||
        questions.map((q) => q.id).toSet().length != questions.length ||
        DateTime.tryParse(_string(j, 'startedAt')) == null) {
      throw const FormatException('认字轮次损坏');
    }
    return RecognitionSession(
      id: _string(j, 'id'),
      lessonId: _string(j, 'lessonId'),
      fingerprint: _string(j, 'fingerprint'),
      epoch: _integer(j, 'epoch'),
      startedAt: _string(j, 'startedAt'),
      questions: questions,
      index: index,
      hinted: j['hinted'] as bool,
      feedback: j['feedback'] == null
          ? null
          : RecognitionEvidence.values.byName(j['feedback'] as String),
      repeated: _list(j['repeated'], (v) => v as String),
      recognitionFirst: j['recognitionFirst'] as bool? ?? false,
    );
  }
}

class RecognitionAudioApproval {
  const RecognitionAudioApproval({
    required this.fingerprint,
    required this.cueKey,
    required this.identity,
  });
  final String fingerprint, cueKey;
  final NarrationAudioIdentity identity;
  Map<String, dynamic> toJson() => {
        'fingerprint': fingerprint,
        'cueKey': cueKey,
        'identity': identity.toJson(),
      };
  factory RecognitionAudioApproval.fromJson(Map<String, dynamic> j) =>
      RecognitionAudioApproval(
        fingerprint: _string(j, 'fingerprint'),
        cueKey: _string(j, 'cueKey'),
        identity: NarrationAudioIdentity.fromJson(_map(j['identity'])),
      );
}

class RecognitionProgress {
  const RecognitionProgress({
    required this.profileId,
    required this.bookId,
    required this.editionId,
    this.revision = 0,
    this.records = const {},
    this.audio = const {},
    this.session,
    this.operations = const [],
  });
  final String profileId, bookId, editionId;
  final int revision;
  // 课目 ID/目标 ID 的 JSON 编码组合，字形不参与身份。
  final Map<String, RecognitionRecord> records;
  final Map<String, RecognitionAudioApproval> audio;
  final RecognitionSession? session;
  final List<String> operations;
  static String targetKey(String lesson, String target) =>
      jsonEncode([lesson, target]);
  RecognitionProgress copy({
    Map<String, RecognitionRecord>? records,
    Map<String, RecognitionAudioApproval>? audio,
    RecognitionSession? session,
    bool clearSession = false,
    int? revision,
    List<String>? operations,
  }) =>
      RecognitionProgress(
        profileId: profileId,
        bookId: bookId,
        editionId: editionId,
        revision: revision ?? this.revision,
        records: records ?? this.records,
        audio: audio ?? this.audio,
        session: clearSession ? null : session ?? this.session,
        operations: operations ?? this.operations,
      );
  Map<String, dynamic> toJson() => {
        'v': 1,
        'profileId': profileId,
        'bookId': bookId,
        'editionId': editionId,
        'revision': revision,
        'records': records.map((k, v) => MapEntry(k, v.toJson())),
        'audio': audio.map((k, v) => MapEntry(k, v.toJson())),
        'session': session?.toJson(),
        'operations': operations,
      };
  factory RecognitionProgress.fromJson(Map<String, dynamic> j) {
    if (j['v'] != 1) throw const FormatException('认字记录版本不支持');
    if (_map(j['records']).length > 20000 ||
        _map(j['audio']).length > 20000 ||
        _list(j['operations'], (v) => v as String).length > 200) {
      throw const FormatException('认字记录超过范围');
    }
    for (final k in _map(j['records']).keys) {
      final identity = jsonDecode(k);
      if (identity is! List ||
          identity.length != 2 ||
          identity.any((v) => v is! String || v.isEmpty)) {
        throw const FormatException('认字记录目标归属损坏');
      }
    }
    for (final entry in _map(j['audio']).entries) {
      if (_map(entry.value)['cueKey'] != entry.key) {
        throw const FormatException('认字示范引用损坏');
      }
    }
    return RecognitionProgress(
      profileId: _string(j, 'profileId'),
      bookId: _string(j, 'bookId'),
      editionId: _string(j, 'editionId'),
      revision: _integer(j, 'revision'),
      records: _map(j['records'])
          .map((k, v) => MapEntry(k, RecognitionRecord.fromJson(_map(v)))),
      audio: _map(j['audio']).map(
        (k, v) => MapEntry(k, RecognitionAudioApproval.fromJson(_map(v))),
      ),
      session: j['session'] == null
          ? null
          : RecognitionSession.fromJson(_map(j['session'])),
      operations: _list(j['operations'], (v) => v as String),
    );
  }
}
