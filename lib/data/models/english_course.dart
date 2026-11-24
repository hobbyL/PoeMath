import 'dart:math';

import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart'
    show textbookContentDigest;

enum EnglishTargetKind {
  vocabulary('单词与短语'),
  sentence('对话与故事'),
  letter('字母'),
  activity('课内活动'),
  exercise('练习与答案');

  const EnglishTargetKind(this.label);
  final String label;
}

enum EnglishExerciseKind { choice, fillBlank, oral }

String newEnglishId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

Map<String, dynamic> englishObject(Object? value) {
  if (value is! Map<String, dynamic>) throw const FormatException('英语数据格式无效');
  return value;
}

String englishString(Object? value, {bool empty = false, int max = 12000}) {
  if (value is! String ||
      (!empty && value.trim().isEmpty) ||
      value.length > max) {
    throw const FormatException('英语文本字段无效');
  }
  return value;
}

List<T> englishList<T>(
  Object? value,
  T Function(Object?) decode, {
  int max = 4000,
}) {
  if (value is! List || value.length > max) {
    throw const FormatException('英语列表无效');
  }
  return List.unmodifiable(value.map(decode));
}

int englishInt(Object? value, {int min = 0, int max = 1000000}) {
  if (value is! int || value < min || value > max) {
    throw const FormatException('英语数值无效');
  }
  return value;
}

/// 原书证据。印刷页不从固定偏移推算，图片区域采用左上角归一化坐标。
class EnglishSource {
  const EnglishSource(
    this.page, {
    this.printedPage,
    this.left = 0,
    this.top = 0,
    this.right = 1,
    this.bottom = 1,
  });
  final int page;
  final String? printedPage;
  final double left, top, right, bottom;
  Map<String, dynamic> toJson() => {
    'page': page,
    'printedPage': printedPage,
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };
  factory EnglishSource.fromJson(Object? raw) {
    final j = englishObject(raw);
    final coordinates = ['left', 'top', 'right', 'bottom'].map((k) {
      final v = j[k];
      if (v is! num || !v.isFinite || v < 0 || v > 1) {
        throw const FormatException('原书区域无效');
      }
      return v.toDouble();
    }).toList();
    if (coordinates[0] >= coordinates[2] || coordinates[1] >= coordinates[3]) {
      throw const FormatException('原书区域为空');
    }
    return EnglishSource(
      englishInt(j['page'], min: 1),
      printedPage: j['printedPage'] == null
          ? null
          : englishString(j['printedPage'], max: 40),
      left: coordinates[0],
      top: coordinates[1],
      right: coordinates[2],
      bottom: coordinates[3],
    );
  }
}

class EnglishTarget {
  EnglishTarget({
    required this.id,
    required this.kind,
    required this.text,
    required List<EnglishSource> sources,
    this.meaning = '',
    this.role = '',
    List<String> options = const [],
    List<String> answers = const [],
    this.exerciseKind = EnglishExerciseKind.oral,
    this.caseSensitive = false,
    this.reviewDigest,
    this.audioReview,
    this.origin = 'textbook',
    this.picture,
    this.pictureReviewed = false,
    this.spellingEnabled = false,
  }) : sources = List.unmodifiable(sources),
       options = List.unmodifiable(options),
       answers = List.unmodifiable(answers);
  final String id, text, meaning, role, origin;
  final EnglishTargetKind kind;
  final List<EnglishSource> sources;
  final EnglishSource? picture;
  final bool pictureReviewed, spellingEnabled, caseSensitive;
  final List<String> options, answers;
  final EnglishExerciseKind exerciseKind;
  final String? reviewDigest, audioReview;
  Map<String, dynamic> get content => {
    'id': id,
    'kind': kind.name,
    'text': text,
    'meaning': meaning,
    'role': role,
    'sources': sources.map((s) => s.toJson()).toList(),
    'origin': origin,
    'picture': picture?.toJson(),
    'pictureReviewed': pictureReviewed,
    'spellingEnabled': spellingEnabled,
    'options': options,
    'answers': answers,
    'exerciseKind': exerciseKind.name,
    'caseSensitive': caseSensitive,
  };
  String get fingerprint => textbookContentDigest(content);
  bool get approved => reviewDigest == fingerprint;
  bool get hasSpeech =>
      kind != EnglishTargetKind.exercise &&
      kind != EnglishTargetKind.activity &&
      RegExp('[A-Za-z]').hasMatch(text);
  bool audioApproved(String voiceKey) =>
      approved &&
      audioReview ==
          textbookContentDigest({'content': fingerprint, 'voice': voiceKey});
  EnglishTarget approve({String? voiceKey}) => EnglishTarget.fromJson({
    ...toJson(),
    'reviewDigest': fingerprint,
    'audioReview': voiceKey == null
        ? audioReview
        : textbookContentDigest({'content': fingerprint, 'voice': voiceKey}),
  });
  EnglishTarget change(Map<String, dynamic> fields) =>
      EnglishTarget.fromJson({...toJson(), ...fields});
  Map<String, dynamic> toJson() => {
    ...content,
    'reviewDigest': reviewDigest,
    'audioReview': audioReview,
  };
  factory EnglishTarget.fromJson(Object? raw) {
    final j = englishObject(raw);
    final sources = englishList(j['sources'], EnglishSource.fromJson, max: 100);
    if (sources.isEmpty) throw const FormatException('学习内容缺少原书来源');
    final options = englishList(
      j['options'],
      (v) => englishString(v, max: 2000),
      max: 20,
    );
    final answers = englishList(
      j['answers'],
      (v) => englishString(v, max: 2000),
      max: 20,
    );
    final kind = EnglishTargetKind.values
        .where((v) => v.name == j['kind'])
        .firstOrNull;
    final exercise = EnglishExerciseKind.values
        .where((v) => v.name == j['exerciseKind'])
        .firstOrNull;
    if (kind == null ||
        exercise == null ||
        options.toSet().length != options.length ||
        j['caseSensitive'] is! bool ||
        j['spellingEnabled'] is! bool ||
        j['pictureReviewed'] is! bool ||
        !['textbook', 'parent', 'rule'].contains(j['origin'])) {
      throw const FormatException('英语内容类型或选项无效');
    }
    if (kind == EnglishTargetKind.exercise &&
        exercise == EnglishExerciseKind.choice &&
        (options.length < 2 ||
            answers.length != 1 ||
            !options.contains(answers.single))) {
      throw const FormatException('选择题需要至少两个选项和一个有效答案');
    }
    if (kind == EnglishTargetKind.exercise &&
        exercise == EnglishExerciseKind.fillBlank &&
        answers.isEmpty) {
      throw const FormatException('填空题需要核对答案');
    }
    String? digest(String key) {
      final value = j[key];
      if (value != null && (value is! String || !Textbook.isValidId(value))) {
        throw const FormatException('英语审核摘要无效');
      }
      return value as String?;
    }

    return EnglishTarget(
      id: englishString(j['id'], max: 160),
      kind: kind,
      text: englishString(j['text']),
      meaning: englishString(j['meaning'], empty: true),
      role: englishString(j['role'], empty: true, max: 100),
      sources: sources,
      options: options,
      answers: answers,
      exerciseKind: exercise,
      caseSensitive: j['caseSensitive'] as bool,
      spellingEnabled: j['spellingEnabled'] as bool,
      pictureReviewed: j['pictureReviewed'] as bool,
      picture: j['picture'] == null
          ? null
          : EnglishSource.fromJson(j['picture']),
      origin: j['origin'] as String,
      reviewDigest: digest('reviewDigest'),
      audioReview: digest('audioReview'),
    );
  }
}

class EnglishLesson {
  EnglishLesson({
    required this.id,
    required this.unitId,
    required this.unitTitle,
    required this.title,
    required this.startPage,
    required this.endPage,
    this.kind = 'lesson',
    this.prepared = false,
    this.edited = false,
    List<EnglishTarget> targets = const [],
    List<String> issues = const [],
  }) : targets = List.unmodifiable(targets),
       issues = List.unmodifiable(issues);
  final String id, unitId, unitTitle, title, kind;
  final int startPage, endPage;
  final bool prepared, edited;
  final List<EnglishTarget> targets;
  final List<String> issues;
  int get approvedCount => targets.where((t) => t.approved).length;
  bool containsPage(int page) => page >= startPage && page <= endPage;
  EnglishLesson change(Map<String, dynamic> fields) =>
      EnglishLesson.fromJson({...toJson(), ...fields});
  Map<String, dynamic> toJson() => {
    'id': id,
    'unitId': unitId,
    'unitTitle': unitTitle,
    'title': title,
    'kind': kind,
    'startPage': startPage,
    'endPage': endPage,
    'prepared': prepared,
    'edited': edited,
    'targets': targets.map((t) => t.toJson()).toList(),
    'issues': issues,
  };
  factory EnglishLesson.fromJson(Object? raw) {
    final j = englishObject(raw);
    final targets = englishList(j['targets'], EnglishTarget.fromJson);
    final start = englishInt(j['startPage'], min: 1),
        end = englishInt(j['endPage'], min: 1);
    if (start > end ||
        end - start > 39 ||
        targets.map((t) => t.id).toSet().length != targets.length ||
        j['prepared'] is! bool ||
        j['edited'] is! bool ||
        ![
          'lesson',
          'intro',
          'story',
          'review',
          'revision',
          'unclassified',
        ].contains(j['kind'])) {
      throw const FormatException('英语课时结构无效');
    }
    return EnglishLesson(
      id: englishString(j['id'], max: 160),
      unitId: englishString(j['unitId'], max: 160),
      unitTitle: englishString(j['unitTitle'], max: 300),
      title: englishString(j['title'], max: 300),
      startPage: start,
      endPage: end,
      kind: j['kind'] as String,
      prepared: j['prepared'] as bool,
      edited: j['edited'] as bool,
      targets: targets,
      issues: englishList(
        j['issues'],
        (v) => englishString(v, max: 1000),
        max: 100,
      ),
    );
  }
}

class EnglishCourse {
  EnglishCourse({
    required this.bookId,
    required this.editionId,
    required this.pageCount,
    required this.fileSize,
    this.revision = 0,
    this.parserVersion = 1,
    List<EnglishLesson> lessons = const [],
    List<EnglishLesson> pending = const [],
    Map<int, String> coverage = const {},
  }) : lessons = List.unmodifiable(lessons),
       pending = List.unmodifiable(pending),
       coverage = Map.unmodifiable(coverage);
  final String bookId, editionId;
  final int pageCount, fileSize, revision, parserVersion;
  final List<EnglishLesson> lessons, pending;
  final Map<int, String> coverage;
  EnglishLesson? lesson(String id) =>
      lessons.where((l) => l.id == id).firstOrNull;
  EnglishTarget? target(String lessonId, String id) =>
      lesson(lessonId)?.targets.where((t) => t.id == id).firstOrNull;
  void matchBook(Textbook book) {
    if (book.subject != TextbookSubject.english ||
        book.pdfSha256 != bookId ||
        book.learningEditionId != editionId ||
        book.pageCount != pageCount ||
        book.fileSize != fileSize) {
      throw const FormatException('英语课程与原书不匹配');
    }
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'bookId': bookId,
    'editionId': editionId,
    'pageCount': pageCount,
    'fileSize': fileSize,
    'revision': revision,
    'parserVersion': parserVersion,
    'lessons': lessons.map((l) => l.toJson()).toList(),
    'pending': pending.map((l) => l.toJson()).toList(),
    'coverage': {for (final e in coverage.entries) '${e.key}': e.value},
  };
  EnglishCourse change(Map<String, dynamic> fields) =>
      EnglishCourse.fromJson({...toJson(), ...fields});
  factory EnglishCourse.fromJson(Object? raw) {
    final j = englishObject(raw);
    final pages = englishInt(j['pageCount'], min: 1, max: 5000);
    final lessons = englishList(
      j['lessons'],
      EnglishLesson.fromJson,
      max: 1000,
    );
    final pending = englishList(
      j['pending'],
      EnglishLesson.fromJson,
      max: 1000,
    );
    final coverage = <int, String>{};
    for (final e in englishObject(j['coverage']).entries) {
      final p = int.tryParse(e.key);
      if (p == null || p < 1 || p > pages) {
        throw const FormatException('英语覆盖页码无效');
      }
      coverage[p] = englishString(e.value, max: 300);
    }
    final book = englishString(j['bookId']);
    if (j['schemaVersion'] != 1 ||
        !Textbook.isValidId(book) ||
        lessons.map((l) => l.id).toSet().length != lessons.length ||
        pending.map((l) => l.id).toSet().length != pending.length) {
      throw const FormatException('英语课程身份或版本无效');
    }
    for (final l in [...lessons, ...pending]) {
      if (l.endPage > pages ||
          l.targets.any(
            (t) =>
                t.sources.any((s) => s.page > pages) ||
                (t.picture?.page ?? 1) > pages,
          )) {
        throw const FormatException('英语来源超出原书页数');
      }
    }
    return EnglishCourse(
      bookId: book,
      editionId: englishString(j['editionId'], max: 160),
      pageCount: pages,
      fileSize: englishInt(j['fileSize'], min: 1, max: 2147483647),
      revision: englishInt(j['revision']),
      parserVersion: englishInt(j['parserVersion'], min: 1),
      lessons: lessons,
      pending: pending,
      coverage: coverage,
    );
  }
}
