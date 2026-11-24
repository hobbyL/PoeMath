import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/domain/english_practice.dart';

class EnglishAttempt {
  EnglishAttempt({
    required this.id,
    required this.lessonId,
    required this.title,
    required this.kind,
    required this.completedAt,
    required this.durationSeconds,
    List<EnglishAnswer> answers = const [],
    List<String> spokenTexts = const [],
    List<String> recordingIds = const [],
    Map<String, String> spokenFingerprints = const {},
  }) : answers = List.unmodifiable(answers),
       spokenTexts = List.unmodifiable(spokenTexts),
       recordingIds = List.unmodifiable(recordingIds),
       spokenFingerprints = Map.unmodifiable(spokenFingerprints);
  final String id, lessonId, title, kind;
  final DateTime completedAt;
  final int durationSeconds;
  final List<EnglishAnswer> answers;
  final List<String> spokenTexts, recordingIds;
  final Map<String, String> spokenFingerprints;
  int get correct =>
      answers.where((a) => !a.hinted && !a.skipped && a.correct == true).length;
  int get graded => answers
      .where((a) => !a.skipped && (a.correct != null || a.parentPassed != null))
      .length;
  Map<String, dynamic> toJson({bool portable = false}) => {
    'id': id, 'lessonId': lessonId, 'title': title, 'kind': kind,
    'completedAt': completedAt.toIso8601String(),
    'durationSeconds': durationSeconds,
    'answers': answers.map((a) => a.toJson()).toList(),
    'spokenTexts': spokenTexts,
    'spokenFingerprints': spokenFingerprints,
    // Opaque ids only; no filesystem path is ever serialized in progress.
    'recordingIds': portable ? <String>[] : recordingIds,
  };
  factory EnglishAttempt.fromJson(Object? raw) {
    final j = englishObject(raw);
    final date = DateTime.tryParse(englishString(j['completedAt'], max: 80));
    final kind = englishString(j['kind'], max: 40);
    if (date == null || !['practice', 'speaking', 'study'].contains(kind)) {
      throw const FormatException('英语记录类型无效');
    }
    final ids = englishList(
      j['recordingIds'],
      (v) => englishString(v, max: 100),
      max: 500,
    );
    if (ids.any((id) => !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id))) {
      throw const FormatException('录音身份无效');
    }
    return EnglishAttempt(
      id: englishString(j['id'], max: 160),
      lessonId: englishString(j['lessonId'], max: 160),
      title: englishString(j['title'], max: 500),
      kind: kind,
      completedAt: date,
      durationSeconds: englishInt(j['durationSeconds'], max: 86400),
      answers: englishList(j['answers'], EnglishAnswer.fromJson, max: 200),
      spokenTexts: englishList(
        j['spokenTexts'],
        (v) => englishString(v),
        max: 500,
      ),
      recordingIds: ids,
      spokenFingerprints:
          englishObject(j['spokenFingerprints'] ?? <String, dynamic>{})
              .map((k, v) {
                if (!Textbook.isValidId(v is String ? v : '')) {
                  throw const FormatException('跟读内容版本无效');
                }
                return MapEntry(englishString(k, max: 160), v as String);
              }),
    );
  }
}

class EnglishProgress {
  EnglishProgress({
    required this.profileId,
    required this.bookId,
    required this.editionId,
    this.lastLessonId,
    this.lastTargetId,
    Map<String, EnglishReviewRecord> reviews = const {},
    List<EnglishAttempt> attempts = const [],
  }) : reviews = Map.unmodifiable(reviews),
       attempts = List.unmodifiable(attempts);
  static const prefix = 'textbook_english_v1:';
  final String profileId, bookId, editionId;
  final String? lastLessonId, lastTargetId;
  final Map<String, EnglishReviewRecord> reviews;
  final List<EnglishAttempt> attempts;
  Map<String, dynamic> toJson({bool portable = false}) => {
    'version': 1,
    'profileId': profileId,
    'bookId': bookId,
    'editionId': editionId,
    'lastLessonId': lastLessonId,
    'lastTargetId': lastTargetId,
    'reviews': reviews.map((k, v) => MapEntry(k, v.toJson())),
    'attempts': attempts.map((a) => a.toJson(portable: portable)).toList(),
  };
  factory EnglishProgress.fromJson(Object? raw) {
    final j = englishObject(raw);
    final id = englishString(j['bookId']);
    if (j['version'] != 1 || !Textbook.isValidId(id)) {
      throw const FormatException('英语进度版本或原书无效');
    }
    final records = englishObject(j['reviews']);
    if (records.length > 20000) throw const FormatException('英语复习记录过多');
    final attempts = englishList(
      j['attempts'],
      EnglishAttempt.fromJson,
      max: 5000,
    );
    if (attempts.map((a) => a.id).toSet().length != attempts.length) {
      throw const FormatException('英语记录重复');
    }
    return EnglishProgress(
      profileId: englishString(j['profileId'], max: 160),
      bookId: id,
      editionId: englishString(j['editionId'], max: 160),
      lastLessonId: j['lastLessonId'] == null
          ? null
          : englishString(j['lastLessonId'], max: 160),
      lastTargetId: j['lastTargetId'] == null
          ? null
          : englishString(j['lastTargetId'], max: 160),
      reviews: records.map(
        (k, v) => MapEntry(
          englishString(k, max: 500),
          EnglishReviewRecord.fromJson(v),
        ),
      ),
      attempts: attempts,
    );
  }
}
