import 'package:poemath/data/models/textbook_recognition_progress.dart';

class RecognitionPolicy {
  static const roundSize = 5;
  static const dailyReviewLimit = 10;
  static const intervals = [1, 3, 7, 14, 30];
  static const interveningQuestions = 2;
}

String recognitionDay(DateTime now) =>
    '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
String _later(String day, int days) {
  final date = DateTime.parse(day);
  return recognitionDay(DateTime(date.year, date.month, date.day + days));
}

RecognitionRecord recognitionRecordResult(
  RecognitionRecord r,
  RecognitionEvidence evidence, {
  required String day,
  required bool hinted,
}) {
  final objective = evidence == RecognitionEvidence.correct ||
      evidence == RecognitionEvidence.parentCorrect;
  final failed = evidence == RecognitionEvidence.incorrect ||
      evidence == RecognitionEvidence.parentAgain ||
      evidence == RecognitionEvidence.selfAgain;
  final delayed = r.lastDay != null &&
      r.lastDay!.compareTo(day) < 0 &&
      (r.nextDay == null || r.nextDay!.compareTo(day) <= 0);
  var stage = r.stage;
  var advancedDay = r.advancedDay;
  if (failed || hinted) stage = 0;
  if (objective && !hinted && delayed && advancedDay != day) {
    stage = (stage + 1).clamp(0, RecognitionPolicy.intervals.length - 1);
    advancedDay = day;
  }
  return RecognitionRecord(
    fingerprint: r.fingerprint,
    studies: r.studies + (evidence == RecognitionEvidence.study ? 1 : 0),
    correct: r.correct +
        (evidence == RecognitionEvidence.correct && !hinted ? 1 : 0),
    incorrect:
        r.incorrect + (evidence == RecognitionEvidence.incorrect ? 1 : 0),
    selfCorrect:
        r.selfCorrect + (evidence == RecognitionEvidence.selfCorrect ? 1 : 0),
    selfAgain:
        r.selfAgain + (evidence == RecognitionEvidence.selfAgain ? 1 : 0),
    hints: r.hints + (hinted ? 1 : 0),
    stage: stage,
    advancedDay: advancedDay,
    // 同日通过不拉长日期；失败/提示始终缩短，曝光/自评不延长客观日程。
    nextDay: failed || hinted || r.nextDay == null
        ? _later(day, 1)
        : objective && delayed && advancedDay == day
            ? _later(day, RecognitionPolicy.intervals[stage])
            : r.nextDay,
    lastDay: objective || failed ? day : r.lastDay ?? day,
    checkedDay: objective || evidence == RecognitionEvidence.incorrect
        ? day
        : r.checkedDay,
    parentDay: evidence == RecognitionEvidence.parentCorrect ||
            evidence == RecognitionEvidence.parentAgain
        ? day
        : r.parentDay,
    parentPassed: evidence == RecognitionEvidence.parentCorrect
        ? (hinted ? null : true)
        : evidence == RecognitionEvidence.parentAgain
            ? false
            : r.parentPassed,
  );
}

String recognitionRecordLabel(RecognitionRecord? r) {
  if (r == null) return '还没练过';
  if (r.parentPassed == false || r.incorrect > 0 && r.stage == 0) return '再练一练';
  if (r.stage >= 3) return '已巩固';
  if (r.parentPassed == true) return '家长确认过';
  if (r.correct > 0) return '辨认通过，待复习';
  return '练习过，待认读确认';
}
