import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_draft.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/domain/textbook_course_draft_parser.dart';

import 'textbook_draft_fixture.dart';

const readingFixtureLines = [
  '甲𠀀星光，',
  '乙月光。',
  '丙山光，',
  '丁水光。',
  '戊春风，',
  '己夏风。',
  '庚秋风，',
  '辛冬风。',
];

const illustratedReadingLines = [
  '甲𠀀星光，乙月光，',
  '丙山闪亮丁水明。',
  '戊风轻，己草青。',
  '庚日暖，辛云白，',
  '壬花点点照小窗。',
  '癸雨细，辰叶新。',
  '寅鸟鸣，卯蝶飞，',
  '午树高高连远山。',
  '未泉清，申石圆。',
];

/// 三个交错的多行文字块：首尾为左侧插图让位，正文不应保留图片空位。
TextbookPageText illustratedReadingPage() {
  final base = layoutFixturePage(2, ['星月测试', ...illustratedReadingLines]);
  return TextbookPageText(
    page: base.page,
    text: base.text,
    width: base.width,
    height: base.height,
    glyphs: [
      for (final glyph in base.glyphs)
        () {
          final row = base.text.runes
              .take(glyph.index)
              .where((rune) => rune == 0x0a)
              .length;
          final block = (row - 1) ~/ 3;
          final offset = row > 0 && block != 1 ? .3 : 0.0;
          final top = row == 0 ? .05 : .15 + (row - 1) * .06 + block * .04;
          return TextbookPageGlyph(
            text: glyph.text,
            index: glyph.index,
            left: glyph.left + offset,
            right: glyph.right + offset,
            top: top,
            bottom: top + .03,
          );
        }(),
    ],
  );
}

/// 自有文字模拟旧生成器把识字条并入末节，以及历史统一补缩进。
({TextbookCourseDocument document, List<TextbookPageText> pages})
    readingFixture({bool legacyIndent = false}) {
  final parser = TextbookCourseDraftParser();
  final seed = parser.seed(draftFixtureEntry(), draftFixtureToc);
  final base = layoutFixturePage(
    2,
    ['星月测试', ...readingFixtureLines, '星月山河', '朗读课文。背诵全文。'],
    step: .06,
  );
  final source = TextbookPageText(
    page: 2,
    text: base.text,
    width: base.width,
    height: base.height,
    glyphs: [
      for (final glyph in base.glyphs)
        () {
          final row = base.text.runes
              .take(glyph.index)
              .where((rune) => rune == 0x0a)
              .length;
          final top = row == 0
              ? .05
              : row <= 8
                  ? .15 + (row - 1) * .04 + ((row - 1) ~/ 2) * .03
                  : .75 + (row - 9) * .06;
          return TextbookPageGlyph(
            text: glyph.text,
            index: glyph.index,
            left: glyph.left,
            right: glyph.right,
            top: top,
            bottom: top + .03,
          );
        }(),
    ],
  );
  final tables = parser.vocabularyTables(seed.pack, [
    layoutFixturePage(2, ['识字表', '阅读', '1 星月', '山河']),
  ]);
  final lesson = seed.pack.lessons.first;
  final generated = parser.parse(
    lesson,
    seed.generation!.plans.first,
    [source],
    vocabulary: tables[lesson.id]!,
  );
  final raw = seed.pack.toJson();
  final old = generated.lesson;
  final paragraph = (old['paragraphs'] as List).first as Map<String, dynamic>;
  final text = '${readingFixtureLines.join('\n')}\n星月山河';
  paragraph['text'] = text;
  paragraph['pinyin'] = null;
  old['paragraphs'] = [paragraph];
  final recitation = (old['recitations'] as List).single as Map;
  recitation['ranges'] = [
    {
      'paragraphId': paragraph['id'],
      'start': 0,
      'end': text.runes.length,
      'textSha256': textbookTextDigest(text),
    },
  ];
  final baseline = textbookDraftBaseline(old);
  if (legacyIndent) {
    paragraph['text'] = '　　$text';
    final range = (recitation['ranges'] as List).single as Map;
    range['start'] = 2;
    range['end'] = text.runes.length + 2;
  }
  (raw['lessons'] as List)[0] = old;
  final manifest = seed.generation!.toJson()
    ..['parserVersion'] = 5
    ..['baselines'] = {...seed.generation!.baselines, lesson.id: baseline};
  return (
    document: TextbookCourseDocument(
      TextbookCoursePack.fromJson(raw),
      TextbookDraftManifest.fromJson(manifest),
    ),
    pages: [
      source,
      layoutFixturePage(3, ['山河测试', '下一课正文。']),
    ],
  );
}
