import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_draft.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/domain/textbook_course_draft_parser.dart';
import 'package:poemath/domain/textbook_text_display.dart';

/// 显示、注音及朗读共用的只读课文；不覆盖保存的课程或审核记录。
class TextbookReadingContent {
  const TextbookReadingContent(this.lesson, {this.layouts = const {}});
  final TextbookCourseLesson lesson;
  final Map<String, TextbookReadingLayout> layouts;
}

class TextbookReadingResolver {
  final _parser = TextbookCourseDraftParser();

  TextbookDraftPlan? automaticPlan(
    TextbookCourseDocument? document,
    TextbookCourseLesson lesson,
  ) {
    final generation = document?.generation;
    if (generation == null ||
        document!.pack.status != 'draft' ||
        lesson.paragraphs.isEmpty ||
        lesson.review.status != TextbookReviewStatus.unreviewed ||
        lesson.targets.any(
          (node) => node.review.status != TextbookReviewStatus.unreviewed,
        ) ||
        lesson.coverage.values
            .any((value) => value != TextbookCoverage.pending) ||
        generation.pending.containsKey(lesson.id) ||
        generation.removed.any(
          (id) =>
              id.startsWith('${lesson.id}-') ||
              id.startsWith('vocabulary:${lesson.id}:'),
        )) {
      return null;
    }
    final plan = generation.plans
        .where((plan) => plan.id == lesson.id && !plan.edited)
        .firstOrNull;
    final baseline = generation.baselines[lesson.id];
    if (plan == null || baseline == null) return null;
    final raw = lesson.toJson();
    if (textbookDraftBaseline(raw) == baseline) return plan;

    // 兼容早期统一补缩进的草稿，严格逆变换后仍须命中原生成摘要。
    // 不忽略文字、标点或任意空白差异；真正的人工编辑始终使用保存版本。
    final shifted = <String, String>{};
    for (final node in raw['paragraphs'] as List) {
      final paragraph = node as Map<String, dynamic>;
      final text = paragraph['text'] as String;
      if (!text.startsWith('　　')) continue;
      final restored = text.substring(2);
      paragraph['text'] = restored;
      shifted[paragraph['id'] as String] = restored;
    }
    if (shifted.isEmpty) return null;
    for (final node in raw['recitations'] as List) {
      for (final value in (node as Map)['ranges'] as List) {
        final range = value as Map<String, dynamic>;
        final text = shifted[range['paragraphId']];
        if (text == null) continue;
        final start = range['start'] as int;
        final end = range['end'] as int;
        if (start < 2 || end < 2) return null;
        range['start'] = start - 2;
        range['end'] = end - 2;
        range['textSha256'] = textbookTextDigest(
          String.fromCharCodes(text.runes.toList().sublist(start - 2, end - 2)),
        );
      }
    }
    return textbookDraftBaseline(raw) == baseline ? plan : null;
  }

  TextbookReadingContent resolve(
    TextbookCoursePack pack,
    TextbookCourseLesson lesson,
    List<TextbookPageText> pages, {
    TextbookCourseDocument? document,
  }) {
    var reading = lesson;
    final plan = automaticPlan(document, lesson);
    final source = {for (final page in pages) page.page: page};
    if (plan != null &&
        [for (var page = plan.startPage; page <= plan.endPage; page++) page]
            .every(
          (number) =>
              source[number]?.status == 'text_extracted' &&
              source[number]!.glyphs.isNotEmpty,
        )) {
      final vocabulary = <TextbookDraftCandidate>[
        for (final category in [
          ('recognitionCharacters', lesson.recognitionCharacters),
          ('writingCharacters', lesson.writingCharacters),
          ('words', lesson.words),
        ])
          for (final node in category.$2)
            TextbookDraftCandidate(
              id: node.id,
              text: node.text,
              reason: '已保存的本课字词来源',
              category: category.$1,
              pages: node.sources.map((source) => source.pdfPage).toList(),
            ),
      ];
      final parsed = _parser.parse(
        lesson,
        plan,
        [
          for (var page = plan.startPage; page <= plan.endPage; page++)
            source[page]!,
        ],
        vocabulary: vocabulary,
      );
      if (parsed.sourceAnchored &&
          (parsed.lesson['paragraphs'] as List).isNotEmpty) {
        final raw = pack.toJson();
        final replacement = parsed.lesson;
        final original = lesson.toJson();
        // 课程附属目标与审核信息不由阅读展示重新生成。
        for (final field in [
          'recognitionCharacters',
          'writingCharacters',
          'words',
          'exercises',
          'coverage',
          'review',
        ]) {
          replacement[field] = original[field];
        }
        final lessons = raw['lessons'] as List;
        final index =
            lessons.indexWhere((node) => (node as Map)['id'] == lesson.id);
        lessons[index] = replacement;
        try {
          reading = TextbookCoursePack.fromJson(raw).lessons[index];
        } on FormatException {
          // 证据或内部引用不能完整解码时，保留已有可读课程。
        }
      }
    }
    return TextbookReadingContent(
      reading,
      layouts: {
        for (final paragraph in reading.paragraphs)
          paragraph.id: _parser.readingLayout(
            paragraph,
            [
              for (final page in paragraph.sources)
                if (source[page.pdfPage] != null) source[page.pdfPage]!,
            ],
            preserveLines: reading.kind == 'poetry',
            paragraphs: reading.paragraphs,
          ),
      },
    );
  }
}
