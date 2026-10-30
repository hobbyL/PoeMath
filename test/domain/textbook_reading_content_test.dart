import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_draft.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/domain/textbook_narration.dart';
import 'package:poemath/domain/textbook_reading_content.dart';
import 'package:poemath/domain/textbook_text_display.dart';

import '../helpers/textbook_reading_fixture.dart';

void main() {
  final resolver = TextbookReadingResolver();

  for (final indent in [false, true]) {
    test('旧自动草稿共用正文管线，显示与朗读只含4节正文且不写课程（历史缩进=$indent）', () {
      final fixture = readingFixture(legacyIndent: indent);
      final doc = fixture.document;
      final old = doc.pack.lessons.first;
      final before = doc.toJson();
      expect(resolver.automaticPlan(doc, old), isNotNull);
      final content = resolver.resolve(
        doc.pack,
        old,
        fixture.pages,
        document: doc,
      );
      expect(content.lesson.paragraphs.map((p) => p.text), [
        for (var i = 0; i < readingFixtureLines.length; i += 2)
          readingFixtureLines.sublist(i, i + 2).join('\n'),
      ]);
      expect(
        content.lesson.recognitionCharacters.map((n) => n.text),
        ['星', '月', '山', '河'],
      );
      expect(
        content.layouts.values.map((layout) => layout.breaks.values),
        everyElement([TextbookReadingBreak.line]),
      );
      expect(
        content.layouts.values.map((layout) => layout.retainLeadingIndent),
        everyElement(isFalse),
      );
      final narration = buildTextbookNarration([content.lesson]);
      expect(
        narration.map((s) => s.text).join(),
        textbookContinuousText(readingFixtureLines.join('\n')),
      );
      final paragraphs = {
        for (final paragraph in content.lesson.paragraphs)
          paragraph.id: paragraph,
      };
      for (final span in narration.expand((segment) => segment.spans)) {
        expect(span.start, greaterThanOrEqualTo(0));
        expect(
          span.end,
          lessThanOrEqualTo(paragraphs[span.paragraphId]!.text.runes.length),
        );
      }
      expect(doc.toJson(), before);
    });
  }

  for (final mutation in [
    'text',
    'punctuation',
    'coverage',
    'review',
    'range',
    'removed',
    'plan',
    'baseline',
    'pending',
  ]) {
    test('人工更改或不能确认来源时保留保存版本：$mutation', () {
      final fixture = readingFixture(legacyIndent: true);
      final raw = jsonDecode(jsonEncode(fixture.document.toJson()))
          as Map<String, dynamic>;
      final pack = raw['coursePack'] as Map;
      final lesson = (pack['lessons'] as List).first as Map;
      final paragraph = (lesson['paragraphs'] as List).single as Map;
      final generation = raw['generation'] as Map;
      final range =
          (((lesson['recitations'] as List).single as Map)['ranges'] as List)
              .single as Map;
      switch (mutation) {
        case 'text':
        case 'punctuation':
          paragraph['text'] = (paragraph['text'] as String).replaceFirst(
            mutation == 'text' ? '星光' : '，',
            mutation == 'text' ? '晨光' : '。',
          );
          range['textSha256'] = textbookTextDigest(paragraph['text'] as String);
        case 'coverage':
          (lesson['coverage'] as Map)['paragraphs'] = 'complete';
        case 'review':
          (paragraph['review'] as Map)['notes'] = '人工核对保留';
        case 'range':
          range['start'] = 3;
          range['textSha256'] = textbookTextDigest(
            String.fromCharCodes(
              (paragraph['text'] as String).runes.toList().sublist(
                    3,
                    range['end'] as int,
                  ),
            ),
          );
        case 'removed':
          (generation['removed'] as List).add('${lesson['id']}-removed');
        case 'plan':
          ((generation['plans'] as List).first as Map)['edited'] = true;
        case 'baseline':
          (generation['baselines'] as Map).remove(lesson['id']);
        case 'pending':
          (generation['pending'] as Map)[lesson['id']] = lesson;
      }
      range['textSha256'] = textbookTextDigest(
        String.fromCharCodes(
          (paragraph['text'] as String).runes.toList().sublist(
                range['start'] as int,
                range['end'] as int,
              ),
        ),
      );
      final doc = TextbookCourseDocument.fromJson(raw);
      final old = doc.pack.lessons.first;
      final before = doc.toJson();
      expect(resolver.automaticPlan(doc, old), isNull);
      expect(
        resolver.resolve(doc.pack, old, fixture.pages, document: doc).lesson,
        same(old),
      );
      expect(doc.toJson(), before);
    });
  }

  test('缺原书、标题或文字层时保留已有内容，导入课程也不隐式替换', () {
    final fixture = readingFixture();
    final doc = fixture.document;
    final old = doc.pack.lessons.first;
    final source = fixture.pages.first;
    for (final pages in [
      <TextbookPageText>[],
      [
        const TextbookPageText(
          page: 2,
          text: '',
          width: 1,
          height: 1,
          status: 'extraction_error',
        ),
      ],
      [
        TextbookPageText(
          page: 2,
          text: source.text,
          width: source.width,
          height: source.height,
          glyphs: source.glyphs.where((g) => g.top > .1).toList(),
        ),
      ],
    ]) {
      expect(
        resolver.resolve(doc.pack, old, pages, document: doc).lesson,
        same(old),
      );
    }
    expect(resolver.resolve(doc.pack, old, fixture.pages).lesson, same(old));
  });
}
