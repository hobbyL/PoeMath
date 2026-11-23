import 'dart:math' as math;

import 'package:lpinyin/lpinyin.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook_course.dart'
    show textbookContentDigest;
import 'package:poemath/domain/textbook_pinyin_font.dart';

final _practiceHeading = RegExp(r'^(?:练习[一二三四五六七八九十百0-9]+|做一做|想一想|说一说|试一试)$');
final _subquestion = RegExp(r'^(?:[（(]\d+[）)]|[①-⑳])');
const _exampleStepHeadings = {'阅读与理解', '分析与解答', '回顾与反思'};
final _instructionNumber = RegExp(r'^([0-9]{1,2})[.、]\s*');

bool isMathTextbookPracticeHeading(String text) =>
    _practiceHeading.hasMatch(text.replaceAll(RegExp(r'\s'), ''));

bool isMathTextbookExampleStepHeading(String text) =>
    _exampleStepHeadings.contains(text.replaceAll(RegExp(r'\s'), ''));

/// Numbered topic banners can be merged with an introductory scene. A section
/// name such as "1. 加法" does not turn that scene into an answerable question.
String? mathTextbookNumberedTopicTitle(MathTextbookBlock block) {
  if (block.kind != MathTextbookBlockKind.exercise ||
      block.parentNote.isNotEmpty ||
      block.sources.first.top > .18) {
    return null;
  }
  final firstLine = block.text
      .split('\n')
      .first
      .trim()
      .replaceAll(RegExp(r'\s'), '');
  final match = RegExp(r'^[0-9]{1,2}[.、](.+)$').firstMatch(firstLine);
  if (match == null) return null;
  final title = match[1]!;
  return RegExp(r'^(?:(?:加|减|乘|除)法(?:的初步认识)?|[0-9]+[~～—-][0-9]+的乘法口诀)$')
          .hasMatch(title)
      ? title
      : null;
}

/// Keep each example/question with its explanation and drawing. The original
/// page remains an independent anchor; an uncertain diagram is never flattened.
MathTextbookLesson organizeMathTextbookLesson(
  MathTextbookLesson lesson, {
  bool legacyLayout = false,
}) {
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
    var blocks = lesson.blocks
        .where(
          (b) =>
              b.kind != MathTextbookBlockKind.sourcePage &&
              b.sources.first.page == page &&
              !isMathTextbookFooter(b),
        )
        .map(
          (block) =>
              legacyLayout ? block : _namedUnitHeading(block, lesson.title),
        )
        .toList();
    if (!legacyLayout) blocks = _practiceQuestionRoles(blocks);
    if (blocks.isEmpty) {
      organized.addAll(originals);
      continue;
    }
    final candidates =
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
    final anchors = legacyLayout
        ? candidates
        : _contentAnchors(candidates, blocks);
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
      final mathCells = legacyLayout
          ? const <MathTextbookBlock>[]
          : members
                .where((b) => b.spans.any((s) => s.expression != null))
                .toList();
      final parallelMath = mathCells.any(
        (left) => mathCells.any(
          (right) =>
              right.sources.first.left - left.sources.first.right >
                  math.max(
                        left.sources.first.height,
                        right.sources.first.height,
                      ) *
                      .8 &&
              (right.sources.first.top - left.sources.first.top).abs() <
                  math.min(
                        left.sources.first.height,
                        right.sources.first.height,
                      ) *
                      .6,
        ),
      );
      // A worksheet can have several formula columns without drawing paths.
      // Keep those columns in the source layout instead of flattening them.
      final visual =
          !titleOnly &&
          (parallelMath || intersecting.any((b) => b.needsSource));
      final spans = <MathTextbookSpan>[];
      // Illustration labels stay in the image. Supported expressions keep
      // their structure through grouping, including intermediate work.
      for (final block in members.where(
        (b) =>
            b.spans.isNotEmpty &&
            !(visual && !group.contains(b) && _isLayoutLabel(b)),
      )) {
        final content = block.kind == MathTextbookBlockKind.illustration
            ? legacyLayout
                  ? const <MathTextbookSpan>[]
                  : block.spans
                        .where((span) => span.expression != null)
                        .toList()
            : block.spans;
        if (content.isEmpty) continue;
        if (spans.isNotEmpty) spans.add(const MathTextbookSpan.text('\n'));
        spans.addAll(
          content.map(
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
      final drawings = !legacyLayout && visual
          ? members.where((b) => b.kind == MathTextbookBlockKind.illustration)
          : const <MathTextbookBlock>[];
      final region = MathTextbookRegion(
        page: page,
        left: intersecting.map((b) => b.sources.first.left).reduce(math.min),
        // Question bands can overlap a drawing's edge. Preserve every owned
        // drawing in full while retaining the next question's prompt.
        top: drawings.fold(
          start,
          (edge, b) => math.min(edge, b.sources.first.top),
        ),
        right: intersecting.map((b) => b.sources.first.right).reduce(math.max),
        bottom: drawings.fold(
          end,
          (edge, b) => math.max(edge, b.sources.first.bottom),
        ),
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

MathTextbookBlock _namedUnitHeading(
  MathTextbookBlock block,
  String lessonTitle,
) {
  if (block.kind != MathTextbookBlockKind.exercise ||
      block.parentNote.isNotEmpty ||
      block.sources.first.top > .18) {
    return block;
  }
  final topic = mathTextbookNumberedTopicTitle(block);
  final text = block.text.replaceAll(RegExp(r'\s'), '');
  final match = RegExp(r'^[0-9]{1,2}[.、](.+)$').firstMatch(text);
  if (match == null) return block;
  final title = lessonTitle.replaceAll(RegExp(r'\s'), '');
  final name = match[1]!;
  if (topic == null &&
      name != title &&
      !(title.endsWith(name) &&
          RegExp(r'^[0-9]{1,2}[.、]?$')
              .hasMatch(title.substring(0, title.length - name.length)))) {
    return block;
  }
  // The named unit on the page is a heading, even when it starts with "2.".
  return MathTextbookBlock.fromJson({
    ...block.toJson(),
    'kind': MathTextbookBlockKind.heading.name,
    'exerciseNumber': null,
  });
}

List<MathTextbookBlock> _practiceQuestionRoles(List<MathTextbookBlock> blocks) {
  final ordered = [...blocks]
    ..sort((a, b) => a.sources.first.top.compareTo(b.sources.first.top));
  final replacements = <String, MathTextbookBlock>{};
  var practice = false;
  for (final block in ordered) {
    if (block.kind == MathTextbookBlockKind.heading) {
      final text = block.text.replaceAll(RegExp(r'\s'), '');
      if (_practiceHeading.hasMatch(text)) {
        practice = true;
      } else if (!_exampleStepHeadings.contains(text) &&
          blocks.any((b) => _independentHeadingBackdrop(b, block))) {
        practice = false;
      }
    } else if (practice && block.kind == MathTextbookBlockKind.example) {
      // Practice badges can look larger than nearby small drawing labels.
      // The printed practice section determines their role.
      replacements[block.id] = MathTextbookBlock.fromJson({
        ...block.toJson(),
        'kind': MathTextbookBlockKind.exercise.name,
      });
    }
  }
  return [for (final block in blocks) replacements[block.id] ?? block];
}

bool _independentHeadingBackdrop(
  MathTextbookBlock block,
  MathTextbookBlock heading,
) =>
    _isHeadingBackdrop(block, heading) &&
    heading.sources.first.top - block.sources.first.top <=
        heading.sources.first.height * .8 &&
    block.sources.first.height <= heading.sources.first.height * 3;

List<MathTextbookBlock> _contentAnchors(
  List<MathTextbookBlock> candidates,
  List<MathTextbookBlock> blocks,
) {
  final instructionIds = <String>{};
  for (final frame in blocks.where(
    (b) => b.kind == MathTextbookBlockKind.illustration,
  )) {
    final source = frame.sources.first;
    if (source.width < .3 || source.height < .08) continue;
    final steps = candidates
        .where(
          (b) =>
              b.kind == MathTextbookBlockKind.exercise &&
              b.parentNote.isEmpty &&
              _instructionNumber.hasMatch(b.text) &&
              source.containsCenter(b.sources.first),
        )
        .toList();
    if (steps.length < 2 ||
        !RegExp(r'^(?:先|首先)').hasMatch(
          steps.first.text.replaceFirst(_instructionNumber, '').trimLeft(),
        ) ||
        !steps
            .skip(1)
            .any(
              (b) => RegExp(r'^(?:再|然后|最后|接着)').hasMatch(
                b.text.replaceFirst(_instructionNumber, '').trimLeft(),
              ),
            )) {
      continue;
    }
    final numbers = steps
        .map((b) => int.parse(_instructionNumber.firstMatch(b.text)![1]!))
        .toList();
    if (numbers.first != 1 ||
        numbers.indexed.any((entry) => entry.$2 != entry.$1 + 1)) {
      continue;
    }
    instructionIds.addAll(steps.map((b) => b.id));
  }
  final anchors = <MathTextbookBlock>[];
  MathTextbookBlock? question;
  for (final block in candidates) {
    final phase =
        block.kind == MathTextbookBlockKind.heading &&
        _exampleStepHeadings.contains(block.text.replaceAll(RegExp(r'\s'), ''));
    final heading = block.kind == MathTextbookBlockKind.heading;
    final independentHeading =
        !phase &&
        (_practiceHeading.hasMatch(block.text.replaceAll(RegExp(r'\s'), '')) ||
            blocks.any((b) => _independentHeadingBackdrop(b, block)));
    if (question != null &&
        (heading && !independentHeading ||
            question.kind == MathTextbookBlockKind.example &&
                instructionIds.contains(block.id))) {
      continue;
    }
    anchors.add(block);
    if (block.kind == MathTextbookBlockKind.example ||
        block.kind == MathTextbookBlockKind.exercise) {
      question = block;
    } else {
      question = null;
    }
  }
  return anchors;
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
/// underneath every extracted fragment. Source-only and incomplete pages remain
/// visible so partial text cannot hide missing drawings in an older draft.
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
                b.warnings.isNotEmpty ||
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

bool isReadableMathTextbookDisplayTitle(String value) {
  if (value.trim().isEmpty || RegExp(r'[\r\n]').hasMatch(value)) return false;
  final readable = value.replaceAll(
    RegExp(
      r'[\s\d零〇一二三四五六七八九十百千万~～（）()\[\]【】{}<>《》:：,，.。;；!?！？、·…⋯_+=×÷/\\—-]+',
    ),
    '',
  );
  return readable.isNotEmpty;
}

Map<String, String> mathTextbookExampleSections(MathTextbookLesson lesson) {
  var section = isReadableMathTextbookDisplayTitle(lesson.title)
      ? lesson.title.trim()
      : '';
  final sections = <String, String>{};
  for (final block in lesson.blocks) {
    if (block.kind == MathTextbookBlockKind.sourcePage ||
        isMathTextbookFooter(block)) {
      continue;
    }
    if (block.kind == MathTextbookBlockKind.example) {
      sections[block.id] = section;
      continue;
    }
    if (block.kind != MathTextbookBlockKind.heading ||
        isMathTextbookExampleStepHeading(block.text) ||
        isMathTextbookPracticeHeading(block.text)) {
      continue;
    }
    final heading = block.text.trim();
    if (isReadableMathTextbookDisplayTitle(heading)) section = heading;
  }
  return Map.unmodifiable(sections);
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

/// Student notes contain explanations, while worked examples have their own
/// learning entries. Authored summaries remain intact; automatic excerpts keep
/// only complete method statements from the source, never generated answers.
List<MathTextbookKnowledgePoint> mathTextbookStudyNotes(
  MathTextbookLesson lesson,
) {
  final learning = lesson.learning;
  if (learning == null) return const [];
  final automatic =
      lesson.review == null &&
      !learning.coverageConfirmed &&
      textbookContentDigest(learning.toJson()) ==
          textbookContentDigest(
            _seedMathTextbookLearning(
              lesson,
              unitTitle: learning.unitTitle,
              classifyPracticeSections: true,
              excludeIntroductions: true,
            ).toJson(),
          );
  if (!automatic) {
    return learning.knowledgePoints
        .where((point) => point.summary.trim().isNotEmpty)
        .toList();
  }
  final exampleSections = mathTextbookExampleSections(lesson);
  final notes = <MathTextbookKnowledgePoint>[];
  for (final point in learning.knowledgePoints) {
    final statements = <String>{};
    for (final block in lesson.blocks.where(
      (b) => point.blockIds.contains(b.id),
    )) {
      // A formula or diagram separates prose fragments. Do not attach a
      // question's labels to the explanation which follows its calculation.
      final text = block.spans
          .map((span) => span.text ?? '\u0000')
          .join()
          .replaceAll(
            RegExp(
              r'(?<=[\u3400-\u9fff，、；：])[^\S\n]*\n[^\S\n]*(?=[\u3400-\u9fff])',
            ),
            '',
          );
      for (final match in RegExp(r'[^。！？!?\n\u0000]+[。！]').allMatches(text)) {
        final sentence = match[0]!.trim().replaceFirst(RegExp(r'^\d+\s+'), '');
        if (sentence.length > 400 ||
            RegExp(
              r'[（(]\s*[）)]|_{2,}|……|后记|本册教材|编写|出版社|敬意|谢意|上面|下面|下表|你自己|说一说|填一填|量一量',
            ).hasMatch(sentence)) {
          continue;
        }
        if (RegExp(
          r'对齐|相加满十|不够减|从十位退|进[一1]|可以用|可以看作|可以得到|可以形成|可以比较|可以测量|就是|叫作|称为|作为|作单位|需要使用|先画|再画|借助尺子|用相同|相同的单位|要注意|应注意',
        ).hasMatch(sentence)) {
          statements.add(sentence);
        }
      }
    }
    if (statements.isEmpty) continue;
    var title = point.title
        .replaceFirst(RegExp(r'\s*·\s*例\s*[^·]+$'), '')
        .trim();
    if (!isReadableMathTextbookDisplayTitle(title)) {
      final example = lesson.blocks
          .where(
            (block) =>
                block.kind == MathTextbookBlockKind.example &&
                point.blockIds.contains(block.id),
          )
          .firstOrNull;
      final section = example == null ? null : exampleSections[example.id];
      if (section != null && section.isNotEmpty) {
        title = section;
      } else if (example != null) {
        title = mathTextbookSectionTitle(example);
      }
    }
    final index = notes.indexWhere((note) => note.title == title);
    if (index < 0) {
      notes.add(
        MathTextbookKnowledgePoint(
          id: point.id,
          title: title,
          summary: statements.join('\n'),
          blockIds: point.blockIds,
        ),
      );
    } else {
      final previous = notes[index];
      notes[index] = MathTextbookKnowledgePoint(
        id: previous.id,
        title: title,
        summary: {...previous.summary.split('\n'), ...statements}.join('\n'),
        blockIds: {...previous.blockIds, ...point.blockIds}.toList(),
      );
    }
  }
  return notes;
}

MathTextbookLearning seedMathTextbookLearning(
  MathTextbookLesson lesson, {
  String unitTitle = '',
  bool legacyLayout = false,
}) => MathTextbookLearning.fromJson(
  _seedMathTextbookLearning(
    lesson,
    unitTitle: unitTitle,
    legacyLayout: legacyLayout,
    legacyExampleTitles: legacyLayout,
    classifyPracticeSections: !legacyLayout,
    excludeIntroductions: !legacyLayout,
  ).toJson(),
);

/// Repair only a reproducible, unreviewed automatic learning configuration.
/// Keep authored blocks and the stored course untouched; both student reads and
/// authoritative practice writes must resolve the same configuration.
MathTextbookLesson resolveMathTextbookLearningSections(
  MathTextbookLesson lesson,
) {
  final learning = lesson.learning;
  if (learning == null || lesson.review != null || learning.coverageConfirmed) {
    return lesson;
  }
  final digest = textbookContentDigest(learning.toJson());
  final reproducible = [
    for (final classify in [false, true])
      for (final excludeIntroductions in [false, true])
        for (final legacyLayout in [false, true])
          for (final legacyExampleTitles in [false, true])
            textbookContentDigest(
              _seedMathTextbookLearning(
                lesson,
                unitTitle: learning.unitTitle,
                legacyLayout: legacyLayout,
                legacyExampleTitles: legacyExampleTitles,
                classifyPracticeSections: classify,
                excludeIntroductions: excludeIntroductions,
              ).toJson(),
            ),
  ].contains(digest);
  if (!reproducible) return lesson;
  final corrected = _seedMathTextbookLearning(
    lesson,
    unitTitle: learning.unitTitle,
    classifyPracticeSections: true,
    excludeIntroductions: true,
  );
  // Do not make a valid saved course unreadable if the extra question groups
  // exceed the learning schema's limit. Generation still validates this limit.
  if (corrected.exercises.length > 1000) return lesson;
  final sections = mathTextbookExampleSections(lesson);
  final knowledgePoints = corrected.knowledgePoints.map((point) {
    final titleWithoutExample = point.title
        .replaceFirst(RegExp(r'\s*·\s*例\s*[^·]+$'), '')
        .trim();
    if (isReadableMathTextbookDisplayTitle(titleWithoutExample)) return point;
    final example = lesson.blocks
        .where(
          (block) =>
              block.kind == MathTextbookBlockKind.example &&
              point.blockIds.contains(block.id),
        )
        .firstOrNull;
    if (example == null) return point;
    final section = sections[example.id] ?? '';
    final exampleTitle = mathTextbookSectionTitle(example);
    final title = section.isEmpty ? exampleTitle : '$section · $exampleTitle';
    final boundedTitle = title.length <= 200
        ? title
        : '${title.substring(0, 199)}…';
    return MathTextbookKnowledgePoint(
      id: point.id,
      title: boundedTitle,
      summary: point.summary,
      blockIds: point.blockIds,
    );
  }).toList();
  final normalized = MathTextbookLearning(
    unitTitle: corrected.unitTitle,
    knowledgePoints: knowledgePoints,
    exercises: corrected.exercises,
    practicePlans: corrected.practicePlans,
    coverageConfirmed: corrected.coverageConfirmed,
    noExercises: corrected.noExercises,
  );
  if (textbookContentDigest(normalized.toJson()) == digest) return lesson;
  return lesson.edit(learning: normalized);
}

/// Reconstruct an exact older automatic configuration solely to validate and
/// retain existing practice drafts when introductory scenes stop being tasks.
MathTextbookLesson? mathTextbookLessonBeforeIntroductionFix(
  MathTextbookLesson lesson, {
  required String bookId,
  required String digest,
}) {
  final learning = lesson.learning;
  if (learning == null || lesson.review != null || learning.coverageConfirmed) {
    return null;
  }
  final current = _seedMathTextbookLearning(
    lesson,
    unitTitle: learning.unitTitle,
    classifyPracticeSections: true,
    excludeIntroductions: true,
  );
  if (textbookContentDigest(current.toJson()) !=
      textbookContentDigest(learning.toJson())) {
    return null;
  }
  for (final classify in [true, false]) {
    for (final legacyExampleTitles in [false, true]) {
      final previous = lesson.edit(
        learning: _seedMathTextbookLearning(
          lesson,
          unitTitle: learning.unitTitle,
          classifyPracticeSections: classify,
          legacyExampleTitles: legacyExampleTitles,
        ),
      );
      if (previous.contentDigest(bookId) == digest) return previous;
    }
  }
  return null;
}

MathTextbookLearning _seedMathTextbookLearning(
  MathTextbookLesson lesson, {
  String unitTitle = '',
  bool legacyLayout = false,
  bool legacyExampleTitles = false,
  required bool classifyPracticeSections,
  bool excludeIntroductions = false,
}) {
  final knowledge = <MathTextbookKnowledgePoint>[];
  final exercises = <MathTextbookExercise>[];
  var section =
      legacyExampleTitles || isReadableMathTextbookDisplayTitle(lesson.title)
      ? lesson.title
      : '';
  var practice = false;
  MathTextbookBlock? practiceHeading;
  MathTextbookRegion? previousPracticeSource;
  for (final block in lesson.blocks) {
    if (block.kind == MathTextbookBlockKind.sourcePage) continue;
    if (classifyPracticeSections && isMathTextbookFooter(block)) continue;
    final introduction = excludeIntroductions
        ? mathTextbookNumberedTopicTitle(block)
        : null;
    if (introduction != null) {
      section = introduction;
      practice = false;
      practiceHeading = null;
      previousPracticeSource = null;
      continue;
    }
    if (block.kind == MathTextbookBlockKind.heading) {
      final isPractice = isMathTextbookPracticeHeading(block.text);
      if (classifyPracticeSections &&
          !_exampleStepHeadings.contains(
            block.text.replaceAll(RegExp(r'\s'), ''),
          )) {
        practice = isPractice;
        practiceHeading = isPractice ? block : null;
        previousPracticeSource = null;
      }
      if (!isPractice &&
          (legacyExampleTitles ||
              isReadableMathTextbookDisplayTitle(block.text))) {
        section = block.text.trim();
      }
      continue;
    }
    if (classifyPracticeSections) {
      if (block.kind == MathTextbookBlockKind.example) {
        practice = false;
        practiceHeading = null;
        previousPracticeSource = null;
      } else if (block.kind == MathTextbookBlockKind.exercise) {
        practice = true;
      }
    }
    if (block.kind == MathTextbookBlockKind.exercise || practice) {
      // Unnumbered prompts and their drawings can be separate organized blocks.
      // Keep them in the same page's question; the next page retains its own
      // source instead of guessing a cross-page question boundary.
      if (classifyPracticeSections &&
          block.kind != MathTextbookBlockKind.exercise &&
          previousPracticeSource?.page == block.sources.first.page &&
          exercises.last.blockIds.length < 100) {
        final previous = exercises.removeLast();
        exercises.add(
          MathTextbookExercise.fromJson({
            ...previous.toJson(),
            'blockIds': [...previous.blockIds, block.id],
          }),
        );
        previousPracticeSource = block.sources.last;
        continue;
      }
      exercises.add(
        MathTextbookExercise(
          id: '${block.id}-exercise',
          title: block.kind == MathTextbookBlockKind.exercise
              ? mathTextbookSectionTitle(block)
              : '原书练习',
          number: block.exerciseNumber ?? '',
          blockIds: [
            if (classifyPracticeSections &&
                block.kind != MathTextbookBlockKind.exercise &&
                practiceHeading?.sources.first.page == block.sources.first.page)
              practiceHeading!.id,
            block.id,
          ],
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
      previousPracticeSource = block.sources.last;
      practiceHeading = null;
      continue;
    }
    final summary = _knowledgeSummary(block);
    // A printed example is still a knowledge source when its explanation is
    // pictorial or mathematical. Keep its source and leave the prose empty;
    // do not invent a textual rule from the drawing.
    if (summary.isEmpty &&
        (legacyLayout || block.kind != MathTextbookBlockKind.example)) {
      continue;
    }
    final sectionTitle = block.kind == MathTextbookBlockKind.example
        ? mathTextbookSectionTitle(block)
        : '';
    final title = legacyExampleTitles
        ? block.kind == MathTextbookBlockKind.example
              ? '$section · $sectionTitle'
              : section
        : block.kind == MathTextbookBlockKind.example
        ? section.isEmpty
              ? sectionTitle
              : '$section · $sectionTitle'
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
  return MathTextbookLearning(
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
  );
}
