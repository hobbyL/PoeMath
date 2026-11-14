import 'dart:math' as math;

import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook_toc.dart';

/// 目录只提供待核区间；不把目录标题等同于已确认的知识点或答案。
MathTextbookCourseOutline planMathTextbookCourse(
  TextbookTocResult toc,
  int pageCount,
) {
  if (pageCount < 1 || pageCount > 10000) throw const FormatException('原书页数无效');
  final entries = toc.entries.where((e) => e.title.trim().isNotEmpty).toList();
  final starts = <({String title, String unit, int page})>[];
  var unit = '';
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final group =
        entry.isGroup ||
        i + 1 < entries.length && entries[i + 1].level > entry.level;
    if (group || entry.level == 0 && entry.lessonNumber != null) {
      unit = entry.title.trim();
    }
    if (entry.page == null || entry.page! < 1 || entry.page! > pageCount) {
      continue;
    }
    final value = (title: entry.title.trim(), unit: unit, page: entry.page!);
    final samePage = starts.indexWhere((s) => s.page == value.page);
    if (samePage >= 0) {
      starts[samePage] = value;
    } else {
      starts.add(value);
    }
  }
  starts.sort((a, b) => a.page.compareTo(b.page));
  final ranges = <MathTextbookCourseRange>[];
  if (starts.isEmpty) {
    for (var start = 1; start <= pageCount; start += 40) {
      final end = math.min(start + 39, pageCount);
      ranges.add(
        MathTextbookCourseRange(
          title: '原书第 $start～$end 页（待确认课时）',
          startPage: start,
          endPage: end,
          needsAlignment: true,
        ),
      );
    }
  } else {
    // 目录可能无法定位第一课；前面的页既可能是封面目录，也可能是正文。
    // 保留原页供家长确认用途，不把未定位等同于非教学内容而丢弃。
    for (var start = 1; start < starts.first.page; start += 40) {
      final end = math.min(start + 39, starts.first.page - 1);
      ranges.add(
        MathTextbookCourseRange(
          title: '原书第 $start～$end 页（待确认用途）',
          startPage: start,
          endPage: end,
          needsAlignment: true,
        ),
      );
    }
    for (var i = 0; i < starts.length; i++) {
      final entry = starts[i],
          end = i + 1 < starts.length ? starts[i + 1].page - 1 : pageCount;
      for (
        var start = entry.page, part = 1;
        start <= end;
        start += 40, part++
      ) {
        final split = end - entry.page >= 40;
        final title = entry.title.length > 175
            ? '${entry.title.substring(0, 175)}…'
            : entry.title;
        ranges.add(
          MathTextbookCourseRange(
            title: split ? '$title（待核区间 $part）' : title,
            unitTitle: entry.unit,
            startPage: start,
            endPage: math.min(start + 39, end),
            needsAlignment: split,
          ),
        );
      }
    }
  }
  return MathTextbookCourseOutline.fromJson(
    MathTextbookCourseOutline(
      source: starts.isEmpty ? 'pages' : toc.source.name,
      ranges: ranges,
      directoryPages: toc.directoryPages,
      warnings: [
        if (starts.isEmpty) '目录无法定位，已保留全部原书页的待核区间，请家长按真实课时调整。',
        if (starts.isNotEmpty && starts.first.page > 1)
          '首个已定位目录条目前的原页已保留为待核区间，请家长确认用途及课时归属。',
        if (starts.isNotEmpty &&
            ranges.any(
              (r) => r.needsAlignment && r.startPage >= starts.first.page,
            ))
          '较长目录小节已拆为不超过 40 页的待核区间，请家长对照原书调整课时。',
      ],
    ).toJson(),
  );
}

MathTextbookLearning seedMathTextbookLearning(
  MathTextbookLesson lesson, {
  String unitTitle = '',
}) {
  final content = lesson.blocks
      .where(
        (b) =>
            b.kind != MathTextbookBlockKind.sourcePage &&
            b.kind != MathTextbookBlockKind.exercise,
      )
      .take(100)
      .toList();
  final references = content.isEmpty
      ? lesson.blocks.take(100).toList()
      : content;
  final summary = content
      .map((b) => b.text)
      .where((s) => s.trim().isNotEmpty)
      .join('\n');
  final knowledgeId = '${lesson.id}-knowledge';
  final exercises = [
    for (final block in lesson.blocks.where(
      (b) => b.kind == MathTextbookBlockKind.exercise,
    ))
      MathTextbookExercise(
        id: '${block.id}-exercise',
        title: block.exerciseNumber == null
            ? '原书题组（待核对）'
            : '原书第 ${block.exerciseNumber} 题',
        number: block.exerciseNumber ?? '',
        blockIds: [block.id],
        knowledgePointIds: [knowledgeId],
        fields: [
          MathTextbookAnswerField(
            id: 'answer',
            label: '你的作答或纸上完成情况',
            rule: MathTextbookAnswerRule(
              kind: MathTextbookAnswerKind.parent,
              reference: '请对照原书核对完整题组、过程和作答。',
            ),
          ),
        ],
      ),
  ];
  return MathTextbookLearning.fromJson(
    MathTextbookLearning(
      unitTitle: unitTitle,
      knowledgePoints: [
        MathTextbookKnowledgePoint(
          id: knowledgeId,
          title: '本课知识',
          summary: summary.length <= 5000 ? summary : '',
          blockIds: references.map((b) => b.id).toList(),
        ),
      ],
      exercises: exercises,
      practicePlans: [
        MathTextbookPracticePlan(
          id: '${lesson.id}-practice',
          knowledgePointId: knowledgeId,
          title: '本课实践',
          kind: MathTextbookPracticeKind.parentTask,
          count: 1,
          task: '选择本课一个例题或活动，在纸上完成并说明方法，请家长对照原书核对。',
        ),
      ],
      coverageConfirmed: false,
    ).toJson(),
  );
}
