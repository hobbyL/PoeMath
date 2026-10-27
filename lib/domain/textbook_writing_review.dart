import 'package:poemath/data/models/textbook_writing_progress.dart';
import 'package:poemath/domain/textbook_recognition_review.dart';

/// 写一写复习推进：与认一认共用 [RecognitionPolicy] 间隔（1/3/7/14/30 天）。
///
/// 家长确认是唯一权威判定（PRD R3）：确认通过才推进 stage 与下次复习日；
/// 家长判"还没写好"则归零。几何比对只作教练提示，不参与复习日程。
WritingRecord writingRecordParentConfirm(
  WritingRecord r, {
  required bool passed,
  required String day,
}) {
  final delayed = r.lastDay != null &&
      r.lastDay!.compareTo(day) < 0 &&
      (r.nextDay == null || r.nextDay!.compareTo(day) <= 0);
  var stage = r.stage;
  var advancedDay = r.advancedDay;
  if (!passed) stage = 0;
  if (passed && delayed && advancedDay != day) {
    stage = (stage + 1).clamp(0, RecognitionPolicy.intervals.length - 1);
    advancedDay = day;
  }
  return r.copy(
    parentConfirms: r.parentConfirms + (passed ? 1 : 0),
    lastParentDay: day,
    stage: stage,
    advancedDay: advancedDay,
    // 同日通过不拉长日期；判不通过始终缩短到次日。
    nextDay: !passed
        ? writingLaterDay(day, 1)
        : delayed && advancedDay == day
            ? writingLaterDay(day, RecognitionPolicy.intervals[stage])
            : r.nextDay ?? writingLaterDay(day, 1),
    lastDay: day,
  );
}

/// 记录一次阶段完成（描红 / 空格自写），不改变复习日程。
WritingRecord writingRecordStage(WritingRecord r, WritingStageDone stage) =>
    r.copy(
      traceCount: r.traceCount + (stage == WritingStageDone.trace ? 1 : 0),
      freeCount: r.freeCount + (stage == WritingStageDone.free ? 1 : 0),
    );

enum WritingStageDone { trace, free }

String writingLaterDay(String day, int days) {
  final date = DateTime.parse(day);
  return recognitionDay(DateTime(date.year, date.month, date.day + days));
}

/// 今日是否待复习（字卡总览标记）。
bool writingDueToday(WritingRecord? r, String today) =>
    r != null && r.nextDay != null && r.nextDay!.compareTo(today) <= 0;