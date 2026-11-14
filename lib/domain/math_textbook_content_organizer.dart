import 'dart:math' as math;

import 'package:lpinyin/lpinyin.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/domain/textbook_pinyin_font.dart';

final _practiceHeading = RegExp(r'^(?:练习[一二三四五六七八九十百0-9]+|做一做|想一想|说一说|试一试)$');
final _subquestion = RegExp(r'^(?:[（(]\d+[）)]|[①-⑳])');

/// Keep each example/question with its explanation and drawing. The original
/// page remains an independent anchor; an uncertain diagram is never flattened.
MathTextbookLesson organizeMathTextbookLesson(MathTextbookLesson lesson) {
  // An explicitly joined cross-page question already owns its complete sources.
  if (lesson.blocks.any(
    (b) => b.sources.map((s) => s.page).toSet().length > 1,
  )) {
    return lesson;
  }
  final organized = <MathTextbookBlock>[];
  for (var page = lesson.startPage; page <= lesson.endPage; page++) {
    final originals = lesson.blocks
        .where(
          (b) =>
              b.kind == MathTextbookBlockKind.sourcePage &&
              b.sources.first.page == page,
        )
        .toList();
    final blocks = lesson.blocks
        .where(
          (b) =>
              b.kind != MathTextbookBlockKind.sourcePage &&
              b.sources.first.page == page &&
              !isMathTextbookFooter(b),
        )
        .toList();
    if (blocks.isEmpty) {
      organized.addAll(originals);
      continue;
    }
    final anchors =
        blocks
            .where(
              (b) =>
                  b.kind == MathTextbookBlockKind.heading ||
                  b.kind == MathTextbookBlockKind.example ||
                  b.kind == MathTextbookBlockKind.exercise &&
                      !_subquestion.hasMatch(b.text.trim()),
            )
            .toList()
          ..sort((a, b) {
            final top = a.sources.first.top.compareTo(b.sources.first.top);
            return top == 0
                ? a.sources.first.left.compareTo(b.sources.first.left)
                : top;
          });
    final groups = <List<MathTextbookBlock>>[];
    for (final anchor in anchors) {
      // Parallel questions share a band. Keep them together instead of cutting
      // a drawing or pairing the left question with the right question's text.
      if (groups.isNotEmpty &&
          anchor.kind == MathTextbookBlockKind.exercise &&
          groups.last.first.kind == MathTextbookBlockKind.exercise &&
          (anchor.sources.first.top - groups.last.first.sources.first.top)
                  .abs() <
              .018) {
        groups.last.add(anchor);
      } else {
        groups.add([anchor]);
      }
    }
    final top = blocks.map((b) => b.sources.first.top).reduce(math.min);
    final firstHeading = groups.firstOrNull?.firstOrNull;
    final startsWithBanner =
        firstHeading?.kind == MathTextbookBlockKind.heading &&
        blocks
            .where((b) => b.sources.first.top < firstHeading!.sources.first.top)
            .every((b) => _isHeadingBackdrop(b, firstHeading!));
    if (groups.isEmpty ||
        !startsWithBanner &&
            groups.first.first.sources.first.top - top > .025) {
      groups.insert(0, []);
    }
    final starts = [
      for (final group in groups)
        group.isEmpty
            ? top
            : math.max(0.0, group.first.sources.first.top - .004),
    ];
    if (startsWithBanner) starts[0] = top;
    // A ruler, table, or drawing can start just above its question number.
    // Move the boundary into that gap instead of cutting the top of the image.
    for (var index = 1; index < groups.length; index++) {
      final anchor = groups[index].firstOrNull;
      if (anchor == null) continue;
      final earlierBottom = blocks
          .where(
            (b) =>
                b.kind != MathTextbookBlockKind.illustration &&
                b.sources.first.bottom < anchor.sources.first.top,
          )
          .map((b) => b.sources.first.bottom)
          .fold(starts[index - 1], math.max);
      for (final block in blocks) {
        final source = block.sources.first;
        if (block.kind == MathTextbookBlockKind.illustration &&
            source.top < starts[index] &&
            source.bottom > anchor.sources.first.bottom &&
            anchor.sources.first.top - source.top < .06 &&
            source.top > earlierBottom + .004) {
          starts[index] = math.max(earlierBottom, source.top - .004);
        }
      }
    }
    final pageBottom = blocks
        .map((b) => b.sources.first.bottom)
        .reduce(math.max);
    for (var index = 0; index < groups.length; index++) {
      final group = groups[index];
      final start = starts[index];
      final end = index + 1 < groups.length ? starts[index + 1] : pageBottom;
      if (end <= start) continue;
      final members = blocks
          .where(
            (b) =>
                group.contains(b) ||
                !anchors.contains(b) &&
                    b.sources.first.centerY >= start &&
                    b.sources.first.centerY < end,
          )
          .toList();
      final intersecting = blocks
          .where(
            (b) => b.sources.first.bottom > start && b.sources.first.top < end,
          )
          .toList();
      if (intersecting.isEmpty) continue;
      final anchor = group.firstOrNull;
      final titleOnly =
          anchor?.kind == MathTextbookBlockKind.heading &&
          !members.any(
            (b) =>
                b != anchor &&
                !_isHeadingBackdrop(b, anchor!) &&
                b.sources.first.bottom > anchor.sources.first.bottom + .018 &&
                (b.spans.isNotEmpty ||
                    b.kind == MathTextbookBlockKind.illustration),
          );
      final visual = !titleOnly && intersecting.any((b) => b.needsSource);
      final spans = <MathTextbookSpan>[];
      // Labels inside an illustration stay in the image. Only the ordered
      // prose and supported expressions contribute to the reading summary.
      for (final block in members.where(
        (b) =>
            b.kind != MathTextbookBlockKind.illustration &&
            b.spans.isNotEmpty &&
            !(visual && !group.contains(b) && _isLayoutLabel(b)),
      )) {
        if (spans.isNotEmpty) spans.add(const MathTextbookSpan.text('\n'));
        spans.addAll(
          block.spans.map(
            (span) => span.text == null
                ? span
                : MathTextbookSpan.text(_decodePrintedAnnotation(span.text!)),
          ),
        );
      }
      final practice =
          anchor?.kind == MathTextbookBlockKind.heading &&
          _practiceHeading.hasMatch(anchor!.text.replaceAll(RegExp(r'\s'), ''));
      final keptSpans = spans.length <= 1000
          ? spans
          : anchor?.spans ?? <MathTextbookSpan>[];
      final kind = keptSpans.isEmpty
          ? MathTextbookBlockKind.illustration
          : titleOnly
          ? MathTextbookBlockKind.heading
          : practice || anchor?.kind == MathTextbookBlockKind.exercise
          ? MathTextbookBlockKind.exercise
          : anchor?.kind == MathTextbookBlockKind.example
          ? MathTextbookBlockKind.example
          : MathTextbookBlockKind.text;
      final region = MathTextbookRegion(
        page: page,
        left: intersecting.map((b) => b.sources.first.left).reduce(math.min),
        top: start,
        right: intersecting.map((b) => b.sources.first.right).reduce(math.max),
        bottom: end,
        printedPage: originals.firstOrNull?.sources.first.printedPage,
      );
      final numbers = group
          .map((b) => b.exerciseNumber)
          .whereType<String>()
          .toList();
      organized.add(
        MathTextbookBlock(
          id: anchor?.id ?? '${lesson.id}-p$page-intro',
          kind: kind,
          spans: keptSpans,
          sources: [region],
          exerciseNumber: numbers.isEmpty ? null : numbers.join('、'),
          sourceLayout: visual || spans.length > 1000,
          warnings: [
            if (visual || spans.length > 1000) '图形、表格与二维算式按原书版面保留，请对照核对',
          ],
          parentNote: members
              .map((b) => b.parentNote)
              .where((note) => note.isNotEmpty)
              .join('\n'),
        ),
      );
    }
    organized.addAll(originals);
  }
  return MathTextbookLesson.fromJson(lesson.edit(blocks: organized).toJson());
}

bool _isHeadingBackdrop(MathTextbookBlock block, MathTextbookBlock heading) {
  if (block.kind != MathTextbookBlockKind.illustration) return false;
  final source = block.sources.first, title = heading.sources.first;
  return source.left <= title.left &&
      source.right >= title.right &&
      source.top <= title.top &&
      source.bottom <= title.bottom + .06 &&
      source.height < .18;
}

bool _isLayoutLabel(MathTextbookBlock block) =>
    block.kind == MathTextbookBlockKind.text &&
    block.parentNote.isEmpty &&
    block.sources.first.width < .35 &&
    block.spans.every((span) => span.expression == null) &&
    !RegExp(r'[。！？!?：:，,；;…]').hasMatch(block.text) &&
    RegExp(r'[\u3400-\u9fff]').allMatches(block.text).length <= 12;

String _decodePrintedAnnotation(String text) => text.replaceAllMapped(
  RegExp(r'([\u3400-\u9fff])([（(])([a-z]+[A-Z][a-z]*)([）)])'),
  (match) {
    final decoded = decodeTextbookPinyinFont(match[3]!);
    // The source font's mapping alone cannot distinguish pinyin from units
    // such as mA or mL. Require a dictionary reading of the annotated Han.
    if (decoded == null ||
        !PinyinHelper.convertToPinyinArray(
          match[1]!,
          PinyinFormat.WITH_TONE_MARK,
        ).contains(decoded)) {
      return match[0]!;
    }
    return '${match[1]}${match[2]}$decoded${match[4]}';
  },
);

bool isMathTextbookFooter(MathTextbookBlock block) {
  if (block.parentNote.isNotEmpty ||
      block.sources.length != 1 ||
      block.kind != MathTextbookBlockKind.text ||
      !RegExp(r'^\d{1,3}$').hasMatch(block.text.trim())) {
    return false;
  }
  final source = block.sources.single;
  return source.top > .92 &&
      source.height < .045 &&
      source.width < .13 &&
      (source.right < .25 || source.left > .75);
}

/// Source anchors are available through the original-book action, not repeated
/// underneath every extracted fragment. A source-only page remains visible.
List<MathTextbookBlock> mathTextbookReadingBlocks(
  List<MathTextbookBlock> blocks,
) {
  final contentPages = blocks
      .where(
        (b) =>
            b.kind != MathTextbookBlockKind.sourcePage &&
            !isMathTextbookFooter(b),
      )
      .expand((b) => b.sources.map((s) => s.page))
      .toSet();
  return blocks
      .where(
        (b) =>
            !isMathTextbookFooter(b) &&
            (b.kind != MathTextbookBlockKind.sourcePage ||
                b.sources.any((s) => !contentPages.contains(s.page))),
      )
      .toList();
}

String mathTextbookSectionTitle(MathTextbookBlock block) {
  final title = switch (block.kind) {
    MathTextbookBlockKind.example => '例 ${block.exerciseNumber ?? ''}'.trim(),
    MathTextbookBlockKind.exercise =>
      block.exerciseNumber != null
          ? '第 ${block.exerciseNumber} 题'
          : block.text.split('\n').firstOrNull?.trim() ?? '原书练习',
    MathTextbookBlockKind.heading => block.text.trim(),
    MathTextbookBlockKind.formula => '公式与方法',
    MathTextbookBlockKind.illustration => '图形与活动',
    MathTextbookBlockKind.sourcePage => '原书内容',
    MathTextbookBlockKind.text => '知识讲解',
  };
  if (title.isEmpty) return '原书练习';
  return title.length > 200 ? '${title.substring(0, 199)}…' : title;
}

String _knowledgeSummary(MathTextbookBlock block) {
  var text = block.text.trim();
  if (block.exerciseNumber != null) {
    text = text.replaceFirst(
      RegExp('^${RegExp.escape(block.exerciseNumber!)}[.、\\s]*'),
      '',
    );
  }
  text = text.replaceAll(
    RegExp(r'(?<=[\u3400-\u9fff，、；：])\s*\n\s*(?=[\u3400-\u9fff])'),
    '',
  );
  final sentences = RegExp(r'[^。！？!?]+[。！？!?]')
      .allMatches(text)
      .map((match) => match[0]!.trim())
      .where(
        (sentence) =>
            sentence.length <= 400 &&
            RegExp(r'[\u3400-\u9fff]').allMatches(sentence).length >= 6 &&
            !RegExp(r'[（(]\s*[）)]|_{2,}').hasMatch(sentence),
      )
      .toSet()
      .toList();
  final statements = sentences.where(
    (sentence) => !sentence.endsWith('？') && !sentence.endsWith('?'),
  );
  return (statements.isEmpty ? sentences : statements).take(3).join('\n');
}

MathTextbookLearning seedMathTextbookLearning(
  MathTextbookLesson lesson, {
  String unitTitle = '',
}) {
  final knowledge = <MathTextbookKnowledgePoint>[];
  final exercises = <MathTextbookExercise>[];
  var section = lesson.title;
  for (final block in lesson.blocks) {
    if (block.kind == MathTextbookBlockKind.sourcePage) continue;
    if (block.kind == MathTextbookBlockKind.heading) {
      if (!_practiceHeading.hasMatch(
        block.text.replaceAll(RegExp(r'\s'), ''),
      )) {
        section = block.text.trim();
      }
      continue;
    }
    if (block.kind == MathTextbookBlockKind.exercise) {
      exercises.add(
        MathTextbookExercise(
          id: '${block.id}-exercise',
          title: mathTextbookSectionTitle(block),
          number: block.exerciseNumber ?? '',
          blockIds: [block.id],
          knowledgePointIds: knowledge.isEmpty ? [] : [knowledge.last.id],
          fields: [
            MathTextbookAnswerField(
              id: 'answer',
              label: '你的作答或纸上完成情况',
              rule: MathTextbookAnswerRule(
                kind: MathTextbookAnswerKind.parent,
                reference: '请对照这组原书题目，核对完整过程与作答。',
              ),
            ),
          ],
        ),
      );
      continue;
    }
    final summary = _knowledgeSummary(block);
    if (summary.isEmpty) continue;
    final title = block.kind == MathTextbookBlockKind.example
        ? '$section · ${mathTextbookSectionTitle(block)}'
        : section;
    knowledge.add(
      MathTextbookKnowledgePoint(
        id: '${block.id}-knowledge',
        title: title.length <= 200 ? title : title.substring(0, 200),
        summary: summary,
        blockIds: [block.id],
      ),
    );
  }
  return MathTextbookLearning.fromJson(
    MathTextbookLearning(
      unitTitle: unitTitle,
      knowledgePoints: knowledge,
      exercises: exercises,
      practicePlans: [
        if (knowledge.isNotEmpty)
          MathTextbookPracticePlan(
            id: '${lesson.id}-practice',
            knowledgePointId: knowledge.first.id,
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
