import 'dart:math';

import 'package:poemath/data/models/english_course.dart';

enum EnglishPracticeKind {
  meaning('词义练习'),
  listening('听音辨认'),
  sentence('句子排序'),
  letters('大小写配对'),
  spelling('拼写练习'),
  original('课本原题');

  const EnglishPracticeKind(this.label);
  final String label;
}

String normalizeEnglishAnswer(String value, {bool caseSensitive = false}) {
  final normalized = value
      .trim()
      .replaceAll('’', "'")
      .replaceAll('‘', "'")
      .replaceAll(RegExp(r'\s+'), ' ');
  return caseSensitive ? normalized : normalized.toLowerCase();
}

class EnglishQuestion {
  EnglishQuestion({
    required this.id,
    required this.lessonId,
    required this.target,
    required this.kind,
    required this.prompt,
    required List<String> options,
    required List<String> answers,
    this.audioText,
    this.voiceKey,
    this.parentCheck = false,
    this.caseSensitive = false,
    this.pictureOptions = const [],
  }) : options = List.unmodifiable(options),
       answers = List.unmodifiable(answers);
  final String id, lessonId, prompt;
  final EnglishTarget target;
  final EnglishPracticeKind kind;
  final List<String> options, answers;
  final List<EnglishSource> pictureOptions;
  final String? audioText, voiceKey;
  final bool parentCheck, caseSensitive;
  String get recordKey => '$lessonId/${target.id}/${kind.name}';
  bool accepts(String answer) =>
      !parentCheck &&
      answers.any(
        (a) =>
            normalizeEnglishAnswer(a, caseSensitive: caseSensitive) ==
            normalizeEnglishAnswer(answer, caseSensitive: caseSensitive),
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'lessonId': lessonId,
    'target': target.toJson(),
    'kind': kind.name,
    'prompt': prompt,
    'options': options,
    'answers': answers,
    'audioText': audioText,
    'voiceKey': voiceKey,
    'parentCheck': parentCheck,
    'caseSensitive': caseSensitive,
    'pictureOptions': pictureOptions.map((s) => s.toJson()).toList(),
  };
  factory EnglishQuestion.fromJson(Object? raw) {
    final j = englishObject(raw);
    final kind = EnglishPracticeKind.values
        .where((k) => k.name == j['kind'])
        .firstOrNull;
    if (kind == null ||
        j['parentCheck'] is! bool ||
        j['caseSensitive'] is! bool) {
      throw const FormatException('英语题型无效');
    }
    return EnglishQuestion(
      id: englishString(j['id'], max: 500),
      lessonId: englishString(j['lessonId'], max: 160),
      target: EnglishTarget.fromJson(j['target']),
      kind: kind,
      prompt: englishString(j['prompt']),
      options: englishList(j['options'], (v) => englishString(v), max: 100),
      answers: englishList(j['answers'], (v) => englishString(v), max: 20),
      audioText: j['audioText'] == null ? null : englishString(j['audioText']),
      voiceKey: j['voiceKey'] == null ? null : englishString(j['voiceKey']),
      parentCheck: j['parentCheck'] as bool,
      caseSensitive: j['caseSensitive'] as bool,
      pictureOptions: englishList(
        j['pictureOptions'],
        EnglishSource.fromJson,
        max: 20,
      ),
    );
  }
}

List<EnglishQuestion> buildEnglishQuestions(
  EnglishCourse course,
  EnglishPracticeKind kind, {
  String? lessonId,
  String? voiceKey,
  Set<String>? targetKeys,
  int seed = 0,
}) {
  final random = Random(seed), questions = <EnglishQuestion>[];
  final pool = [
    for (final l in course.lessons)
      for (final t in l.targets)
        if (t.isLearnableVocabulary) t,
  ];
  for (final lesson in course.lessons) {
    if (lessonId != null && lesson.id != lessonId) continue;
    for (final t in lesson.targets) {
      if (!t.isAvailableForChild) continue;
      final key = '${lesson.id}/${t.id}/${kind.name}';
      if (targetKeys != null && !targetKeys.contains(key)) continue;
      final options = <String>[], answers = <String>[];
      var prompt = '', parent = false;
      String? audio;
      switch (kind) {
        case EnglishPracticeKind.meaning:
        case EnglishPracticeKind.listening:
          if (!t.isLearnableVocabulary) continue;
          if (kind == EnglishPracticeKind.listening &&
              (voiceKey == null || !t.audioApproved(voiceKey))) {
            continue;
          }
          final listening = kind == EnglishPracticeKind.listening;
          final correct = listening ? t.text : t.meaning;
          final distractors =
              pool
                  .where(
                    (v) =>
                        v.id != t.id &&
                        normalizeEnglishAnswer(v.text) !=
                            normalizeEnglishAnswer(t.text) &&
                        v.meaning != t.meaning,
                  )
                  .map((v) => listening ? v.text : v.meaning)
                  .toSet()
                  .toList()
                ..shuffle(random);
          options.addAll([correct, ...distractors.take(3)]);
          if (options.length < 2) continue;
          options.shuffle(random);
          answers.add(correct);
          prompt = listening ? '听一听，选出听到的词语' : t.text;
          if (listening) audio = t.text;
        case EnglishPracticeKind.sentence:
          if (t.kind != EnglishTargetKind.sentence) continue;
          final words = t.text.trim().split(RegExp(r'\s+'));
          if (words.length < 2 || words.length > 18) continue;
          options.addAll(words..shuffle(random));
          answers.add(t.text);
          prompt = t.meaning.isEmpty ? '把词块组成课本中的句子' : t.meaning;
        case EnglishPracticeKind.letters:
          if (t.kind != EnglishTargetKind.letter ||
              !RegExp(r'^[A-Za-z]$').hasMatch(t.text)) {
            continue;
          }
          final upper = t.text == t.text.toUpperCase();
          final answer = upper ? t.text.toLowerCase() : t.text.toUpperCase();
          options.add(answer);
          for (final offset in [1, 3, 7]) {
            options.add(
              String.fromCharCode(
                (answer.codeUnitAt(0) - (upper ? 97 : 65) + offset) % 26 +
                    (upper ? 97 : 65),
              ),
            );
          }
          options.shuffle(random);
          answers.add(answer);
          prompt = '${t.text} 对应的${upper ? '小写' : '大写'}字母';
        case EnglishPracticeKind.spelling:
          if (!t.isSpellingLearnable) continue;
          prompt = t.meaning;
          answers.add(t.text);
          options.addAll(t.text.split('')..shuffle(random));
        case EnglishPracticeKind.original:
          if (t.picture != null && !t.pictureReviewed) continue;
          if (t.kind != EnglishTargetKind.exercise &&
              t.kind != EnglishTargetKind.activity) {
            continue;
          }
          prompt = t.text;
          options.addAll(t.options);
          answers.addAll(t.answers);
          parent =
              t.kind == EnglishTargetKind.activity ||
              t.exerciseKind == EnglishExerciseKind.oral;
          if (!parent && answers.isEmpty) continue;
      }
      questions.add(
        EnglishQuestion(
          id: key,
          lessonId: lesson.id,
          target: t,
          kind: kind,
          prompt: prompt,
          options: options,
          answers: answers,
          audioText: audio,
          voiceKey: audio == null ? null : voiceKey,
          parentCheck: parent,
          caseSensitive: kind == EnglishPracticeKind.letters || t.caseSensitive,
        ),
      );
    }
  }
  return questions;
}

/// 写入边界重新检查题目依据，不能由页面传入的答案自证正确。
void validateEnglishQuestion(EnglishCourse course, EnglishQuestion question) {
  final expected = buildEnglishQuestions(
    course,
    question.kind,
    lessonId: question.lessonId,
    voiceKey: question.voiceKey,
  ).where((q) => q.target.id == question.target.id).firstOrNull;
  bool same(List<String> a, List<String> b) =>
      a.length == b.length && a.indexed.every((e) => b[e.$1] == e.$2);
  if (expected == null ||
      expected.id != question.id ||
      expected.target.fingerprint != question.target.fingerprint ||
      expected.prompt != question.prompt ||
      expected.audioText != question.audioText ||
      expected.parentCheck != question.parentCheck ||
      expected.caseSensitive != question.caseSensitive ||
      !same(expected.answers, question.answers) ||
      question.pictureOptions.isNotEmpty) {
    throw const FormatException('练习材料或答案已变化');
  }
  final a = [...expected.options]..sort(), b = [...question.options]..sort();
  if (question.kind == EnglishPracticeKind.meaning ||
      question.kind == EnglishPracticeKind.listening) {
    final pool = {
      for (final l in course.lessons)
        for (final t in l.targets)
          if (t.isLearnableVocabulary)
            question.kind == EnglishPracticeKind.meaning ? t.meaning : t.text,
    };
    if (b.length < 2 ||
        b.length > 4 ||
        b.toSet().length != b.length ||
        !b.contains(expected.answers.single) ||
        b.any((s) => !pool.contains(s))) {
      throw const FormatException('练习选项不再有效');
    }
  } else if (!same(a, b)) {
    throw const FormatException('练习选项不再有效');
  }
}

class EnglishAnswer {
  const EnglishAnswer({
    required this.question,
    required this.answer,
    required this.correct,
    this.hinted = false,
    this.skipped = false,
    this.parentPassed,
  });
  final EnglishQuestion question;
  final String answer;
  final bool? correct, parentPassed;
  final bool hinted, skipped;
  bool get objectiveCorrect =>
      !hinted && !skipped && (correct == true || parentPassed == true);
  Map<String, dynamic> toJson() => {
    'question': question.toJson(),
    'answer': answer,
    'correct': correct,
    'hinted': hinted,
    'skipped': skipped,
    'parentPassed': parentPassed,
  };
  factory EnglishAnswer.fromJson(Object? raw) {
    final j = englishObject(raw);
    if (j['hinted'] is! bool ||
        j['skipped'] is! bool ||
        j['correct'] != null && j['correct'] is! bool ||
        j['parentPassed'] != null && j['parentPassed'] is! bool) {
      throw const FormatException('英语作答状态无效');
    }
    return EnglishAnswer(
      question: EnglishQuestion.fromJson(j['question']),
      answer: englishString(j['answer'], empty: true),
      correct: j['correct'] as bool?,
      hinted: j['hinted'] as bool,
      skipped: j['skipped'] as bool,
      parentPassed: j['parentPassed'] as bool?,
    );
  }
}

class EnglishReviewRecord {
  const EnglishReviewRecord({
    required this.fingerprint,
    this.stage = 0,
    this.correct = 0,
    this.incorrect = 0,
    this.selfCorrect = 0,
    this.selfAgain = 0,
    this.lastSelfRating,
    this.nextDay,
    this.lastDay,
    this.advancedDay,
  });
  final String fingerprint;
  final int stage, correct, incorrect, selfCorrect, selfAgain;
  final String? lastSelfRating;
  final String? nextDay, lastDay, advancedDay;
  Map<String, dynamic> toJson() => {
    'fingerprint': fingerprint,
    'stage': stage,
    'correct': correct,
    'incorrect': incorrect,
    if (selfCorrect > 0) 'selfCorrect': selfCorrect,
    if (selfAgain > 0) 'selfAgain': selfAgain,
    if (lastSelfRating != null) 'lastSelfRating': lastSelfRating,
    'nextDay': nextDay,
    'lastDay': lastDay,
    'advancedDay': advancedDay,
  };
  factory EnglishReviewRecord.fromJson(Object? raw) {
    final j = englishObject(raw);
    String? day(String key) {
      final v = j[key];
      if (v != null &&
          (v is! String ||
              !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) ||
              DateTime.tryParse(v) == null)) {
        throw const FormatException('复习日期无效');
      }
      return v as String?;
    }

    final lastSelfRating = j['lastSelfRating'];
    if (lastSelfRating != null &&
        lastSelfRating != 'mastered' &&
        lastSelfRating != 'again') {
      throw const FormatException('单词自评状态无效');
    }
    return EnglishReviewRecord(
      fingerprint: englishString(j['fingerprint'], max: 64),
      stage: englishInt(j['stage'], max: 4),
      correct: englishInt(j['correct']),
      incorrect: englishInt(j['incorrect']),
      selfCorrect: j.containsKey('selfCorrect')
          ? englishInt(j['selfCorrect'])
          : 0,
      selfAgain: j.containsKey('selfAgain') ? englishInt(j['selfAgain']) : 0,
      lastSelfRating: lastSelfRating as String?,
      nextDay: day('nextDay'),
      lastDay: day('lastDay'),
      advancedDay: day('advancedDay'),
    );
  }
}

String englishDay(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
EnglishReviewRecord updateEnglishReview(
  EnglishReviewRecord? old,
  EnglishAnswer answer,
  DateTime now,
) {
  final t = answer.question.target;
  final record = old?.fingerprint == t.fingerprint
      ? old!
      : EnglishReviewRecord(fingerprint: t.fingerprint);
  if (answer.skipped || answer.correct == null && answer.parentPassed == null) {
    return record;
  }
  final day = englishDay(now),
      delayed =
          record.lastDay != null &&
          record.lastDay!.compareTo(day) < 0 &&
          (record.nextDay == null || record.nextDay!.compareTo(day) <= 0);
  var stage = record.stage, advanced = record.advancedDay;
  final failed = !answer.objectiveCorrect;
  if (failed) {
    stage = 0;
  } else if (delayed && advanced != day) {
    stage = (stage + 1).clamp(0, 4);
    advanced = day;
  }
  final interval = failed || record.nextDay == null
      ? 1
      : const [1, 3, 7, 14, 30][stage];
  return EnglishReviewRecord(
    fingerprint: t.fingerprint,
    stage: stage,
    correct: record.correct + (answer.objectiveCorrect ? 1 : 0),
    incorrect:
        record.incorrect +
        (answer.correct == false || answer.parentPassed == false ? 1 : 0),
    selfCorrect: record.selfCorrect,
    selfAgain: record.selfAgain,
    lastSelfRating: record.lastSelfRating,
    lastDay: day,
    advancedDay: advanced,
    nextDay: failed || record.nextDay == null || delayed
        ? englishDay(DateTime(now.year, now.month, now.day + interval))
        : record.nextDay,
  );
}
