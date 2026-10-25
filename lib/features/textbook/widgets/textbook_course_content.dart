import 'package:flutter/material.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/domain/textbook_pinyin.dart';
import 'package:poemath/features/textbook/widgets/textbook_exercise_prompt.dart';

const textbookCourseCategoryLabels = {
  'paragraphs': '课文与注音',
  'recognitionCharacters': '会认字',
  'writingCharacters': '会写字',
  'words': '词语',
  'recitations': '背诵范围',
  'exercises': '习题',
};
const textbookCourseCheckLabels = {
  'sourcePages': '已对照原书页码和来源',
  'edition': '已核对出版社、册次与版次信息',
  'content': '已逐项核对内容',
  'pinyin': '已逐字核对注音和多音字读音',
  'requirement': '已核对原书的认读、书写或听写要求',
  'range': '已核对背诵要求与具体选文',
  'answer': '已核对题目、答案类型和答案来源',
  'coverage': '已核对内容完整性和各类要求',
};
const textbookCourseRequirementLabels = {
  'recognition': '会认',
  'writing': '会写',
  'reading': '阅读词语',
  'dictation': '听写词语',
};
const textbookCourseCoverageLabels = {
  TextbookCoverage.pending: '待核对',
  TextbookCoverage.complete: '已整理完整',
  TextbookCoverage.notApplicable: '原书无此要求',
};
const textbookCourseAnswerLabels = {
  TextbookAnswerType.none: '未提供答案',
  TextbookAnswerType.exact: '标准答案',
  TextbookAnswerType.reference: '参考答案',
  TextbookAnswerType.parentCheck: '家长核对',
};

String textbookCourseNodeTitle(TextbookCourseNode node) => switch (node) {
      TextbookCourseEdition() => '版次与来源',
      TextbookCourseUnit() => node.title,
      TextbookCourseLesson() => node.title,
      TextbookCourseVocabulary() => node.text,
      TextbookCourseParagraph() => '课文段落',
      TextbookCourseRecitation() => '背诵要求',
      TextbookCourseExercise() => '习题与答案',
      _ => '审核内容',
    };

String textbookCourseReviewLabel(TextbookCourseNode node) =>
    textbookCourseReviewLabelFor([node]);

String textbookCourseReviewLabelFor(Iterable<TextbookCourseNode> nodes) {
  final items = nodes.toList(growable: false);
  if (items.isEmpty) return '待审核';
  if (items.every((node) => node.isApproved)) return '已通过';
  if (items
      .any((node) => node.review.status == TextbookReviewStatus.rejected)) {
    return '已退回';
  }
  if (items.any(
    (node) =>
        !node.isApproved && node.review.status == TextbookReviewStatus.approved,
  )) {
    return '修改后待复核';
  }
  return '待审核';
}

final _coursePunctuationSpaces = RegExp(
  r'([，。！？；：、…“”‘’（）《》〈〉【】])[ \t\u3000]+',
);

List<String> _courseDisplayLines(TextbookCourseParagraph node) {
  // 抽取产生的标点后空白不占字格；换行和英文词间空格保留。
  final lines = node.text
      .split('\n')
      .map(
        (line) => line.replaceAllMapped(
          _coursePunctuationSpaces,
          (match) => match.group(1)!,
        ),
      )
      .toList();
  if (node is! TextbookCourseVocabulary) {
    // 仅规范显示缩进，不改写原文、拼音位置或背诵范围。
    lines[0] = '　　${lines[0].trimLeft()}';
  }
  return lines;
}

class _CourseTextMetrics {
  _CourseTextMetrics(
    BuildContext context,
    List<TextbookCourseParagraph> nodes,
  ) {
    final theme = Theme.of(context);
    final fallback = DefaultTextStyle.of(context).style;
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    );
    Size measure(String text, TextStyle style) {
      painter.text = TextSpan(text: text, style: style);
      painter.layout();
      return painter.size;
    }

    final pinyinStyle = theme.textTheme.bodySmall ?? fallback;
    final characterStyle = theme.textTheme.titleSmall ?? fallback;
    try {
      final pinyinTokens = <String>{'Āg'};
      final characters = <String>{'国'};
      for (final node in nodes) {
        final pinyin = textbookCoursePinyinForReview(node);
        pinyinByNode[node] = pinyin;
        columnsByNode[node] = 1;
        pinyinTokens.addAll(pinyin);
        for (final line in _courseDisplayLines(node)) {
          final runes = line.runes.toList();
          if (runes.length > columns) columns = runes.length;
          if (runes.length > columnsByNode[node]!) {
            columnsByNode[node] = runes.length;
          }
          characters.addAll(runes.map(String.fromCharCode));
        }
      }
      for (final token in pinyinTokens) {
        final size = measure(token, pinyinStyle);
        if (size.height > pinyinLineHeight) pinyinLineHeight = size.height;
        final width = size.width + SpacingTokens.xs;
        if (width > cellWidth) cellWidth = width;
      }
      for (final character in characters) {
        final width =
            measure(character, characterStyle).width + SpacingTokens.sm;
        if (width > cellWidth) cellWidth = width;
      }
    } finally {
      painter.dispose();
    }
  }

  final pinyinByNode = <TextbookCourseParagraph, List<String>>{};
  final columnsByNode = <TextbookCourseParagraph, int>{};
  double cellWidth = 0;
  double pinyinLineHeight = 0;
  int columns = 1;
  double get width => cellWidth * columns;
}

class _CourseTextViewport extends StatelessWidget {
  const _CourseTextViewport({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final content = SizedBox(width: width, child: child);
          if (constraints.hasBoundedWidth && width > constraints.maxWidth) {
            return Scrollbar(
              scrollbarOrientation: ScrollbarOrientation.bottom,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: content,
              ),
            );
          }
          return Align(alignment: Alignment.center, child: content);
        },
      );
}

/// 逐字排注音使用 Unicode 码点，与课程解码规则一致。
class TextbookCourseText extends StatelessWidget {
  const TextbookCourseText({super.key, required this.node})
      : _metrics = null,
        _wrap = false;
  const TextbookCourseText._({
    super.key,
    required this.node,
    required _CourseTextMetrics metrics,
    bool wrap = false,
  })  : _metrics = metrics,
        _wrap = wrap;

  final TextbookCourseParagraph node;
  final _CourseTextMetrics? _metrics;
  final bool _wrap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pinyinStyle =
        theme.textTheme.bodySmall ?? DefaultTextStyle.of(context).style;
    final metrics = _metrics ?? _CourseTextMetrics(context, [node]);
    final pinyin = metrics.pinyinByNode[node]!;
    var index = 0;
    final lines = _courseDisplayLines(node);
    Widget buildLine(int lineIndex, String line) {
      final cells = [
        for (final rune in line.runes)
          SizedBox(
            width: metrics.cellWidth,
            child: String.fromCharCode(rune).trim().isEmpty
                ? const SizedBox.shrink()
                : Semantics(
                    label: '${String.fromCharCode(rune)} ${pinyin[index]}',
                    excludeSemantics: true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: metrics.pinyinLineHeight,
                          child: OverflowBox(
                            minWidth: 0,
                            maxWidth: double.infinity,
                            alignment: Alignment.center,
                            child: Text(
                              pinyin[index++],
                              maxLines: 1,
                              softWrap: false,
                              style: pinyinStyle,
                            ),
                          ),
                        ),
                        Text(
                          String.fromCharCode(rune),
                          style: theme.textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
          ),
      ];
      final key = ValueKey('course-text-line-$lineIndex');
      return _wrap
          ? Wrap(
              key: key,
              alignment: WrapAlignment.center,
              runSpacing: SpacingTokens.md,
              children: cells,
            )
          : Row(
              key: key,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: cells,
            );
    }

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          _wrap ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        for (final (lineIndex, line) in lines.indexed) ...[
          if (lineIndex > 0) const SizedBox(height: SpacingTokens.md),
          buildLine(lineIndex, line),
        ],
      ],
    );
    return _metrics != null
        ? content
        : _CourseTextViewport(width: metrics.width, child: content);
  }
}

/// 字词按词换行；单个长词超过行宽时继续按字换行，完整保留注音。
class TextbookCourseVocabularyContent extends StatelessWidget {
  const TextbookCourseVocabularyContent({
    super.key,
    required this.vocabulary,
  });

  final List<TextbookCourseVocabulary> vocabulary;

  @override
  Widget build(BuildContext context) {
    final metrics = _CourseTextMetrics(context, vocabulary);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: metrics.cellWidth,
      runSpacing: SpacingTokens.md,
      children: [
        for (final node in vocabulary)
          SizedBox(
            width: metrics.cellWidth * metrics.columnsByNode[node]!,
            child: TextbookCourseText._(
              key: ValueKey('course-text-${node.id}'),
              node: node,
              metrics: metrics,
              wrap: true,
            ),
          ),
      ],
    );
  }
}

class TextbookCourseParagraphsContent extends StatelessWidget {
  const TextbookCourseParagraphsContent({
    super.key,
    required this.paragraphs,
  });

  final List<TextbookCourseParagraph> paragraphs;

  bool _sharesSourcePage(
    TextbookCourseParagraph prior,
    TextbookCourseParagraph current,
  ) {
    final priorPages = prior.sources.map((source) => source.pdfPage).toSet();
    return current.sources.any((source) => priorPages.contains(source.pdfPage));
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _CourseTextMetrics(context, paragraphs);
    return _CourseTextViewport(
      width: metrics.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, paragraph) in paragraphs.indexed) ...[
            if (index > 0)
              SizedBox(
                height: _sharesSourcePage(paragraphs[index - 1], paragraph)
                    ? SpacingTokens.md
                    : SpacingTokens.lg,
              ),
            TextbookCourseText._(
              key: ValueKey('course-text-${paragraph.id}'),
              node: paragraph,
              metrics: metrics,
            ),
          ],
        ],
      ),
    );
  }
}

class TextbookCourseContent extends StatelessWidget {
  const TextbookCourseContent({
    super.key,
    required this.pack,
    required this.node,
    this.showExerciseHeading = true,
  });
  final TextbookCoursePack pack;
  final TextbookCourseNode node;
  final bool showExerciseHeading;

  @override
  Widget build(BuildContext context) {
    final current = node;
    final children = <Widget>[];
    void text(String value) => children.add(
          SelectableText(
            value,
            style: current is TextbookCourseRecitation ||
                    current is TextbookCourseExercise
                ? Theme.of(context).textTheme.titleSmall
                : null,
            textAlign: current is TextbookCourseParagraph
                ? TextAlign.center
                : TextAlign.start,
          ),
        );
    if (current is TextbookCourseEdition) {
      text('${current.title} · ${current.grade}年级${current.semester}册');
      text('${current.publisher}\n${current.editionLabel}');
      final raw = current.toJson();
      text(
        '出版年月：${current.publicationDate ?? '未载明'}\n版次：${current.editionNumber ?? '未载明'}\n印刷年月：${current.printingDate ?? '未载明'}\n印次：${current.printingNumber ?? '未载明'}',
      );
      text(raw['editionNotes'] as String);
      text('原书来源：${raw['sourceUrl']}');
    } else if (current is TextbookCourseParagraph) {
      if (current is! TextbookCourseVocabulary) {
        final lesson = pack.lessons
            .where((lesson) => lesson.paragraphs.contains(current))
            .firstOrNull;
        if (lesson != null) {
          children.add(
            Text(
              lesson.title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          );
        }
      }
      children.add(TextbookCourseText(node: current));
    } else if (current is TextbookCourseRecitation) {
      text(current.instruction);
      final lesson = pack.lessons
          .firstWhere((lesson) => lesson.recitations.contains(current));
      for (final range in current.ranges) {
        final paragraph =
            lesson.paragraphs.firstWhere((p) => p.id == range.paragraphId);
        final number = lesson.paragraphs.indexOf(paragraph) + 1;
        text('第 $number 段，第 ${range.start + 1}–${range.end} 个字符');
        text(
          String.fromCharCodes(
            paragraph.text.runes.toList().sublist(range.start, range.end),
          ),
        );
      }
    } else if (current is TextbookCourseExercise) {
      children.add(
        TextbookExercisePrompt(
          exercise: current,
          showHeading: showExerciseHeading,
        ),
      );
      if (current.answerType != TextbookAnswerType.none) {
        text('答案类型：${textbookCourseAnswerLabels[current.answerType]}');
      }
      if (current.answerOrigin != 'none') {
        text(
          current.answerOrigin == 'textbook' ? '答案来源：原书' : '答案来源：审核者整理的参考要点',
        );
      }
      for (final answer in current.answers) {
        text(answer);
      }
    } else if (current is TextbookCourseLesson) {
      text(current.title);
      for (final entry in current.coverage.entries) {
        if (entry.value != TextbookCoverage.pending) {
          text(
            '${textbookCourseCategoryLabels[entry.key]}：${textbookCourseCoverageLabels[entry.value]}',
          );
        }
      }
    } else if (current is TextbookCourseUnit) {
      text(current.title);
      for (final id in current.lessonIds) {
        text(pack.lessons.firstWhere((lesson) => lesson.id == id).title);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in children)
          Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.md),
            child: child,
          ),
      ],
    );
  }
}
