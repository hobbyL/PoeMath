import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_draft.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/data/models/textbook_toc.dart';
import 'package:poemath/domain/textbook_course_draft_parser.dart';
import 'package:poemath/domain/textbook_text_display.dart';

import '../helpers/textbook_draft_fixture.dart';
import '../helpers/textbook_course_fixture.dart';
import '../helpers/textbook_reading_fixture.dart';

TextbookPageText _versePage(int page, int start, double left) {
  final text = StringBuffer('星月测试\n');
  final glyphs = <TextbookPageGlyph>[
    for (final (index, rune) in '星月测试'.runes.indexed)
      TextbookPageGlyph(
        text: String.fromCharCode(rune),
        index: index,
        left: .1 + index * .03,
        right: .125 + index * .03,
        top: .05,
        bottom: .08,
      ),
  ];
  var rawIndex = '星月测试\n'.runes.length;
  for (var row = 0; row < 12; row++) {
    final line = '甲${start + row}星光闪，';
    final top = .15 + row * .05 + (row ~/ 4) * .025;
    for (final (column, rune) in line.runes.indexed) {
      glyphs.add(
        TextbookPageGlyph(
          text: String.fromCharCode(rune),
          index: rawIndex++,
          left: left + column * .03,
          right: left + column * .03 + .025,
          top: top,
          bottom: top + .03,
        ),
      );
    }
    text.writeln(line);
    rawIndex++;
  }
  return TextbookPageText(
    page: page,
    text: text.toString(),
    width: 600,
    height: 800,
    glyphs: glyphs,
  );
}

TextbookCourseParagraph _legacyVerse(List<TextbookPageText> pages) {
  final raw = courseFixture();
  final lesson = (raw['lessons'] as List).single as Map;
  final text = '　　${[
    for (final page in pages) ...page.text.trim().split('\n').skip(1),
  ].join('\n')}';
  lesson['paragraphs'] = [
    courseFixtureText('legacy-verse', text, null)
      ..['sources'] = [
        for (final page in pages) courseFixtureSource(page.page),
      ],
  ];
  lesson['recitations'] = <Object>[];
  (lesson['coverage'] as Map)['recitations'] = 'notApplicable';
  return TextbookCoursePack.fromJson(raw).lessons.single.paragraphs.single;
}

void main() {
  final parser = TextbookCourseDraftParser();
  final seed = parser.seed(draftFixtureEntry(), draftFixtureToc);
  final lesson = seed.pack.lessons.first;
  final plan = seed.generation!.plans.first;

  test('为插图整体右移的文字块保持三节，不逐行拆段或注入缩进，旧稿同样恢复诗行', () {
    final page = illustratedReadingPage();
    final parsed = parser.parse(lesson, plan, [page]);
    expect(
      (parsed.lesson['paragraphs'] as List).map((p) => p['text']),
      [
        for (var row = 0; row < illustratedReadingLines.length; row += 3)
          illustratedReadingLines.sublist(row, row + 3).join('\n'),
      ],
    );
    final legacy = _legacyVerse([page]);
    final before = legacy.toJson();
    final layout = parser.readingLayout(legacy, [page]);
    expect(layout.retainLeadingIndent, isFalse);
    expect(layout.leadingIndentCells, 0);
    var rawIndex = 2;
    expect(layout.breaks, {
      for (var index = 1; index < illustratedReadingLines.length; index++)
        (rawIndex += illustratedReadingLines[index - 1].runes.length + 1):
            index % 3 == 0
                ? TextbookReadingBreak.stanza
                : TextbookReadingBreak.line,
    });
    expect(legacy.toJson(), before);
  });

  test('插图旁散文仍保留相对本块续行的真实两格首行缩进', () {
    final base = illustratedReadingPage();
    final page = TextbookPageText(
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
            final indent = row > 0 && (row - 1) % 3 == 0 ? .06 : 0.0;
            return TextbookPageGlyph(
              text: glyph.text,
              index: glyph.index,
              left: glyph.left + indent,
              right: glyph.right + indent,
              top: glyph.top,
              bottom: glyph.bottom,
            );
          }(),
      ],
    );
    final parsed = parser.parse(lesson, plan, [page]);
    expect(
      (parsed.lesson['paragraphs'] as List).map((p) => p['text']),
      [
        for (var row = 0; row < illustratedReadingLines.length; row += 3)
          '　　${illustratedReadingLines.sublist(row, row + 3).join('\n')}',
      ],
    );
  });

  for (final explicit in [false, true]) {
    test('单行自然段从原书恢复缩进，已有缩进不重复补（文字层含缩进=$explicit）', () {
      final prefix = explicit ? '\u2003\u2003 ' : '';
      final base =
          layoutFixturePage(2, ['星月测试', '前段星月明，', '山河也明亮。', '$prefix短段𠀀。']);
      final lastStart = base.text.indexOf('$prefix短段');
      final page = TextbookPageText(
        page: 2,
        text: base.text,
        width: base.width,
        height: base.height,
        glyphs: [
          for (final glyph in base.glyphs)
            TextbookPageGlyph(
              text: glyph.text,
              index: glyph.index,
              left: glyph.left +
                  (!explicit && glyph.index >= lastStart ? .06 : 0),
              right: glyph.right +
                  (!explicit && glyph.index >= lastStart ? .06 : 0),
              top: glyph.top,
              bottom: glyph.bottom,
            ),
        ],
      );
      final raw = courseFixture();
      final lesson = (raw['lessons'] as List).single as Map;
      lesson['paragraphs'] = [
        courseFixtureText('prior', '　　前段星月明，\n山河也明亮。', null),
        courseFixtureText('last', '短段𠀀。', null),
        courseFixtureText('saved', '　　短段𠀀。', null),
      ];
      lesson['recitations'] = <Object>[];
      (lesson['coverage'] as Map)['recitations'] = 'notApplicable';
      final paragraphs =
          TextbookCoursePack.fromJson(raw).lessons.single.paragraphs;
      final source = paragraphs[1].toJson();
      final layout =
          parser.readingLayout(paragraphs[1], [page], paragraphs: paragraphs);
      expect(layout.leadingIndentCells, 2);
      expect(layout.breaks, isEmpty);
      expect(layout.retainLeadingIndent, isTrue);
      expect(paragraphs[1].toJson(), source);
      expect(
        parser
            .readingLayout(paragraphs[2], [page], paragraphs: paragraphs)
            .leadingIndentCells,
        0,
      );
      expect(
        parser
            .readingLayout(paragraphs[1], const [], paragraphs: paragraphs)
            .leadingIndentCells,
        0,
      );
    });
  }

  test('旧课程按真实页坐标恢复6节24行，跨页边距不同不制造缩进或丢失分节', () {
    final pages = [_versePage(2, 0, .36), _versePage(3, 12, .12)];
    final paragraph = _legacyVerse(pages);
    final source = paragraph.text;
    final layout = parser.readingLayout(paragraph, pages);
    expect(layout.retainLeadingIndent, isFalse);
    expect(layout.breaks.length, 23);
    final sourceLines = source.split('\n');
    var rawIndex = 0;
    for (final (index, line) in sourceLines.indexed) {
      if (index > 0) {
        expect(
          layout.breaks[rawIndex],
          index % 4 == 0
              ? TextbookReadingBreak.stanza
              : TextbookReadingBreak.line,
        );
      }
      rawIndex += line.runes.length + 1;
    }
    expect(paragraph.text, source);
    final changed = courseFixture();
    final lesson = (changed['lessons'] as List).single as Map;
    lesson['paragraphs'] = [courseFixtureText('edited', '甲乙\n改写正文。', null)];
    lesson['recitations'] = <Object>[];
    (lesson['coverage'] as Map)['recitations'] = 'notApplicable';
    final edited =
        TextbookCoursePack.fromJson(changed).lessons.single.paragraphs.single;
    expect(parser.readingLayout(edited, pages).breaks, isEmpty);
    final shortened = paragraph.text.split('\n')..removeAt(1);
    lesson['paragraphs'] = [
      courseFixtureText('shortened', shortened.join('\n'), null),
    ];
    final removedLine =
        TextbookCoursePack.fromJson(changed).lessons.single.paragraphs.single;
    expect(parser.readingLayout(removedLine, pages).breaks, isEmpty);
  });

  test('重新提取识别1.5倍节间距，6节逐节保存且左右页不注入错误缩进', () {
    final parsed = parser.parse(
      lesson,
      TextbookDraftPlan(
        id: plan.id,
        title: plan.title,
        startPage: 2,
        endPage: 3,
      ),
      [_versePage(2, 0, .36), _versePage(3, 12, .12)],
    );
    final paragraphs = parsed.lesson['paragraphs'] as List;
    expect(paragraphs, hasLength(6));
    expect(
      paragraphs.every(
        (paragraph) => !(paragraph['text'] as String).startsWith('　'),
      ),
      isTrue,
    );
    expect(
      paragraphs.map(
        (paragraph) => (paragraph['text'] as String).split('\n').length,
      ),
      everyElement(4),
    );
  });

  test('插图小字不因邻列拼音或错位图注合行混入正文，薄标点归回同列正文', () {
    final text = StringBuffer();
    final glyphs = <TextbookPageGlyph>[];
    var index = 0;
    void line(
      String value,
      double top,
      double left, {
      double width = .03,
      double height = .024,
      double step = .045,
      bool thinPunctuation = false,
    }) {
      for (final (column, rune) in value.runes.indexed) {
        final character = String.fromCharCode(rune);
        final thin = thinPunctuation && '，。'.contains(character);
        text.write(character);
        glyphs.add(
          TextbookPageGlyph(
            text: character,
            index: index++,
            left: left + column * step,
            right: left + column * step + (thin ? .008 : width),
            top: thin ? top + .018 : top,
            bottom: top + height,
          ),
        );
      }
      text.writeln();
      index++;
    }

    const body = [
      '星光照亮小山河，',
      '月色轻轻洒窗前。',
      '清风吹过青青草，',
      '细雨轻敲小屋檐。',
      '白云悠悠飘山外，',
      '小鸟声声唱林间。',
      '我们一起看星月，',
      '快乐歌声满校园。',
    ];
    line('星月测试', .05, .45, height: .034);
    for (final (row, value) in body.indexed) {
      line(
        value,
        .2 + row * .055,
        .45,
        // 正文字形较窄但同样高，不能仅凭宽度判成小字。
        width: row == 4 ? .019 : .03,
        thinPunctuation: true,
      );
    }
    // 同一视觉行内的邻列拼音会撑大图注外框。
    line('xUng guQng', .184, .45, width: .007, height: .0146, step: .008);
    line('云朵', .187, .12, width: .0215, height: .0156, step: .024);
    // 图注比正文行更接近逗号的纵向位置，但横向位于另一列。
    line('石桥', .328, .12, width: .0215, height: .0156, step: .024);
    for (final (column, label) in ['风筝', '花朵', '小船'].indexed) {
      line(
        label,
        .75 + column * .004,
        .45 + column * .15,
        width: .0215,
        height: .0156,
        step: .024,
      );
    }
    final page = TextbookPageText.fromJson(
      TextbookPageText(
        page: 2,
        text: text.toString(),
        width: 600,
        height: 800,
        glyphs: glyphs,
      ).toJson(),
    );
    final parsed = parser.parse(lesson, plan, [page]);
    final raw = seed.pack.toJson();
    (raw['lessons'] as List)[0] = parsed.lesson;
    final paragraph =
        TextbookCoursePack.fromJson(raw).lessons.first.paragraphs.single;
    expect(paragraph.text, body.join('\n'));
    expect(paragraph.sources.map((source) => source.pdfPage), [2]);
    for (final label in ['云朵', '石桥', '风筝 花朵 小船']) {
      expect(
        parsed.candidates.any(
          (candidate) =>
              candidate.text.contains(label) && candidate.pages.contains(2),
        ),
        isTrue,
      );
    }
    final layout = parser.readingLayout(paragraph, [page]);
    expect(layout.retainLeadingIndent, isFalse);
    expect(layout.breaks.values, List.filled(7, TextbookReadingBreak.line));
  });

  for (final (crossPage, writing) in [
    (false, false),
    (true, false),
    (false, true),
  ]) {
    test('生字条匹配完整识字表（跨页=$crossPage，续表为写字表=$writing）', () {
      final continuation = [
        if (writing) ...['写字表', '阅读', '1 林风'] else '林风',
      ];
      final tables = parser.vocabularyTables(seed.pack, [
        layoutFixturePage(
          2,
          [
            '识字表',
            '阅读',
            '1 星月山河',
            if (!crossPage) ...continuation,
          ],
          step: .1,
        ),
        if (crossPage) layoutFixturePage(3, continuation),
      ]);
      expect(
        tables[lesson.id]!.map((candidate) => candidate.text),
        ['星月山河', '林风'],
      );
      final pages = [
        _versePage(2, 0, .36),
        layoutFixturePage(3, ['星月山河林风', '朗读课文。']),
      ];
      final parsed = parser.parse(
        lesson,
        TextbookDraftPlan(
          id: plan.id,
          title: plan.title,
          startPage: 2,
          endPage: 3,
        ),
        pages,
        vocabulary: tables[lesson.id]!,
      );
      final paragraphs = parsed.lesson['paragraphs'] as List;
      expect(paragraphs, hasLength(3));
      final last = paragraphs.last as Map;
      final lines = (last['text'] as String).split('\n');
      expect(lines, [
        for (var row = 8; row < 12; row++) '甲$row星光闪，',
        if (writing) '星月山河林风',
      ]);
      expect(
        (last['sources'] as List).map((source) => (source as Map)['pdfPage']),
        writing ? [2, 3] : [2],
      );
      expect(
        (parsed.lesson['recognitionCharacters'] as List)
            .map((node) => (node as Map)['text']),
        writing ? ['星', '月', '山', '河'] : ['星', '月', '山', '河', '林', '风'],
      );
      expect(
        (parsed.lesson['exercises'] as List)
            .map((node) => (node as Map)['prompt']),
        ['朗读课文。'],
      );
      if (!writing) {
        final raw = seed.pack.toJson();
        (raw['lessons'] as List)[0] = parsed.lesson;
        final paragraphs =
            TextbookCoursePack.fromJson(raw).lessons.first.paragraphs;
        final layout = parser.readingLayout(paragraphs.last, pages);
        expect(layout.retainLeadingIndent, isFalse);
        expect(layout.breaks.values, [
          TextbookReadingBreak.line,
          TextbookReadingBreak.line,
          TextbookReadingBreak.line,
        ]);
      }
    });
  }

  test('阅读习题按视觉行分题，词语不跨题，加点由字符下方几何位置识别', () {
    final text = StringBuffer();
    final glyphs = <TextbookPageGlyph>[];
    void line(String value, double top, double left, {bool dot = false}) {
      var x = left;
      for (final rune in value.runes) {
        final index = text.toString().runes.length;
        text.writeCharCode(rune);
        glyphs.add(
          TextbookPageGlyph(
            text: String.fromCharCode(rune),
            index: index,
            left: x,
            top: top,
            right: x + .025,
            bottom: top + .03,
          ),
        );
        x += .03;
      }
      text.write('\n');
      if (dot) {
        // 模拟 PDF 的小号字形编码：只有位于汉字正下方的 3 才是加点。
        glyphs.add(
          TextbookPageGlyph(
            text: '3',
            index: text.toString().runes.length,
            left: left + .01,
            top: top + .034,
            right: left + .014,
            bottom: top + .038,
          ),
        );
        text.write('3\n');
      }
    }

    line('星月测试', .05, .1);
    line('星月明，山河亮。', .12, .1);
    line('读一读，注意加点的词。', .22, .1);
    line('看星星', .30, .1, dot: true);
    line('望月亮', .30, .45, dot: true);
    line('听风声', .38, .1, dot: true);
    line('赏春光', .38, .45, dot: true);
    line('读一读，记一记。', .48, .1);
    for (final (r, words) in [
      ['星光', '月光', '光点', '光线'],
      ['山风', '春风', '风雨', '风声'],
    ].indexed) {
      for (final (c, word) in words.indexed) {
        line(word, .56 + r * .08, .1 + c * .2);
      }
    }
    final parsed = parser.parse(lesson, plan, [
      TextbookPageText(
        page: 2,
        text: text.toString(),
        width: 600,
        height: 800,
        glyphs: glyphs,
      ),
    ]);
    final raw = seed.pack.toJson();
    (raw['lessons'] as List)[0] = parsed.lesson;
    final exercises = TextbookCoursePack.fromJson(raw).lessons.first.exercises;
    expect(exercises.map((e) => e.prompt), [
      '读一读，注意加点的词。\n看星星\t望月亮\n听风声\t赏春光',
      '读一读，记一记。\n星光\t月光\t光点\t光线\n山风\t春风\t风雨\t风声',
    ]);
    expect(
        exercises.first.promptLayout
            .skip(1)
            .expand((r) => r)
            .map((c) => c.emphasis),
        [
          [0],
          [0],
          [0],
          [0],
        ]);
    expect(
      exercises.last.promptLayout.skip(1).expand((r) => r).map((c) => c.text),
      ['星光', '月光', '光点', '光线', '山风', '春风', '风雨', '风声'],
    );
    expect(
      exercises.last.promptLayout
          .expand((r) => r)
          .every((c) => c.emphasis.isEmpty),
      isTrue,
    );
  });

  test('目录新增课目和单元时保留已有ID，不用列表位置占用原ID', () {
    final next = parser.seed(
      draftFixtureEntry(),
      const TextbookTocResult(
        source: TextbookTocSource.text,
        directoryPages: [1],
        entries: [
          TextbookTocEntry(title: '新增单元', isGroup: true),
          TextbookTocEntry(title: '新增课目', page: 2, lessonNumber: 3),
          TextbookTocEntry(title: '第一单元', isGroup: true),
          TextbookTocEntry(title: '星月测试', page: 2, lessonNumber: 1),
          TextbookTocEntry(title: '山河测试', page: 3, lessonNumber: 2),
        ],
      ),
      existing: seed.pack,
      previousPlans: seed.generation!.plans,
    );
    expect(next.pack.lessons.length, 3);
    expect(
      next.pack.lessons.skip(1).map((l) => l.id),
      seed.pack.lessons.map((l) => l.id),
    );
    expect(next.pack.units.last.id, seed.pack.units.single.id);
    expect(next.pack.units.first.id, isNot(seed.pack.units.single.id));
  });

  test('正文“我会”保留，薄标点归回汉字行，原书有效注音按码点对齐', () {
    final base = layoutFixturePage(2, ['星月测试', '星𠀀，月。']);
    final glyphs = <TextbookPageGlyph>[];
    final text = StringBuffer(base.text);
    var index = base.text.runes.length;
    for (final g in base.glyphs) {
      final punctuation = '，。'.contains(g.text);
      glyphs.add(
        TextbookPageGlyph(
          text: g.text,
          index: g.index,
          left: g.left,
          top: punctuation ? g.bottom - .004 : g.top,
          right: g.right,
          bottom: g.bottom,
        ),
      );
      final hint = {'星': 'xīng', '𠀀': 'hē', '月': 'yuè'}[g.text];
      if (hint == null) continue;
      for (final (i, rune) in hint.runes.indexed) {
        text.writeCharCode(rune);
        glyphs.add(
          TextbookPageGlyph(
            text: String.fromCharCode(rune),
            index: index++,
            left: g.left + i * g.width / hint.runes.length,
            top: g.top - .02,
            right: g.left + (i + 1) * g.width / hint.runes.length,
            bottom: g.top - .006,
          ),
        );
      }
    }
    final parsed = parser.parse(lesson, plan, [
      TextbookPageText(
        page: 2,
        text: text.toString(),
        width: 600,
        height: 800,
        glyphs: glyphs,
      ),
    ]);
    expect((parsed.lesson['paragraphs'] as List).single['text'], '星𠀀，月。');
    expect(
      (parsed.lesson['paragraphs'] as List).single['pinyin'],
      ['xīng', 'hē', '，', 'yuè', '。'],
    );
    final body = parser.parse(lesson, plan, [
      layoutFixturePage(2, ['星月测试', '我会变，星月明。']),
    ]);
    expect((body.lesson['paragraphs'] as List).single['text'], '我会变，星月明。');
    expect(body.lesson['exercises'], isEmpty);
  });

  test('文字层逐字注音用完整音节归属，长拼音不会跨到邻字或被截断', () {
    final base = layoutFixturePage(2, ['星月测试']);
    final text = StringBuffer('${base.text}\n');
    final glyphs = <TextbookPageGlyph>[...base.glyphs];
    for (final (column, item) in [
      ('绿', 'lC', .11),
      ('洲', 'zhTu', .1325),
    ].indexed) {
      final (han, hint, hintLeft) = item;
      final left = .1 + column * .05;
      glyphs.add(
        TextbookPageGlyph(
          text: han,
          index: text.toString().runes.length,
          left: left,
          right: left + .03,
          top: .25,
          bottom: .28,
        ),
      );
      text.writeln(han);
      for (final (index, rune) in hint.runes.indexed) {
        glyphs.add(
          TextbookPageGlyph(
            text: String.fromCharCode(rune),
            index: text.toString().runes.length,
            left: hintLeft + index * .012,
            right: hintLeft + index * .012 + .007,
            top: .23,
            bottom: .244,
          ),
        );
        text.writeCharCode(rune);
      }
      text.writeln();
    }
    final parsed = parser.parse(lesson, plan, [
      TextbookPageText.fromJson(
        TextbookPageText(
          page: 2,
          text: text.toString(),
          width: 600,
          height: 800,
          glyphs: glyphs,
        ).toJson(),
      ),
    ]);
    expect((parsed.lesson['paragraphs'] as List).single['text'], '绿洲');
    expect(
      (parsed.lesson['paragraphs'] as List).single['pinyin'],
      ['lǜ', 'zhōu'],
    );
    expect(parsed.candidates, isEmpty);

    final misplaced = parser.parse(lesson, plan, [
      TextbookPageText(
        page: 2,
        text: text.toString(),
        width: 600,
        height: 800,
        glyphs: [
          for (final glyph in glyphs)
            if (glyph.top == .23 && glyph.left >= .13)
              TextbookPageGlyph(
                text: glyph.text,
                index: glyph.index,
                left: glyph.left + .5,
                right: glyph.right + .5,
                top: glyph.top,
                bottom: glyph.bottom,
              )
            else
              glyph,
        ],
      ),
    ]);
    expect((misplaced.lesson['paragraphs'] as List).single['pinyin'], isNull);
    expect(
      misplaced.candidates.any(
        (candidate) =>
            candidate.pinyin.contains('洲: 未找到注音') &&
            candidate.pages.contains(2),
      ),
      isTrue,
    );
  });

  test('拼音字体大写编码在生成时还原为带调注音', () {
    final base = layoutFixturePage(2, ['星月测试', '星月']);
    final glyphs = <TextbookPageGlyph>[...base.glyphs];
    final text = StringBuffer(base.text);
    var index = base.text.runes.length;
    for (final han in base.glyphs.where((g) => g.top > .2)) {
      final hint = han.text == '星' ? 'xUng' : 'yuF';
      for (final (i, rune) in hint.runes.indexed) {
        text.writeCharCode(rune);
        glyphs.add(
          TextbookPageGlyph(
            text: String.fromCharCode(rune),
            index: index++,
            left: han.left + i * .006,
            top: han.top - .02,
            right: han.left + (i + 1) * .006,
            bottom: han.top - .006,
          ),
        );
      }
    }
    final parsed = parser.parse(lesson, plan, [
      TextbookPageText(
        page: 2,
        text: text.toString(),
        width: 600,
        height: 800,
        glyphs: glyphs,
      ),
    ]);
    expect(
      (parsed.lesson['paragraphs'] as List).single['pinyin'],
      ['xīng', 'yuè'],
    );
    expect(parsed.candidates, isEmpty);
  });

  test('隐藏页外文字、已定位生字条和成对写字格不混入正文或习题', () {
    final base = layoutFixturePage(
      2,
      ['星月测试', '星月明，山河亮。', '星月山河', '星 星 月 月', '朗读课文。背诵全文。'],
    );
    final hidden = layoutFixturePage(2, ['相邻页隐藏内容']);
    final parsed = parser.parse(
      lesson,
      plan,
      [
        TextbookPageText(
          page: 2,
          text: '${base.text}\n${hidden.text}',
          width: 600,
          height: 800,
          glyphs: [
            ...base.glyphs,
            for (final g in hidden.glyphs)
              TextbookPageGlyph(
                text: g.text,
                index: base.text.runes.length + 1 + g.index,
                left: g.left - 2,
                top: g.top,
                right: g.right - 2,
                bottom: g.bottom,
              ),
          ],
        ),
      ],
      vocabulary: const [
        TextbookDraftCandidate(
          id: 'r',
          text: '星月山河',
          reason: '自有字表',
          pages: [3],
          category: 'recognitionCharacters',
        ),
        TextbookDraftCandidate(
          id: 'w',
          text: '星月',
          reason: '自有字表',
          pages: [3],
          category: 'writingCharacters',
        ),
      ],
    );
    expect((parsed.lesson['paragraphs'] as List).single['text'], '星月明，山河亮。');
    expect((parsed.lesson['exercises'] as List).single['prompt'], '朗读课文。背诵全文。');
    expect(
      (parsed.lesson['recitations'] as List).single['ranges'].single['end'],
      8,
    );
  });

  test('重复课号按识字/阅读分组，园地标题不变成生字，表尾停止', () {
    final pack = parser
        .seed(
          draftFixtureEntry(),
          const TextbookTocResult(
            source: TextbookTocSource.text,
            directoryPages: [
              1,
            ],
            entries: [
              TextbookTocEntry(title: '第一单元·识字', isGroup: true),
              TextbookTocEntry(title: '星月测试', page: 2, lessonNumber: 1),
              TextbookTocEntry(title: '第二单元', isGroup: true),
              TextbookTocEntry(title: '山河测试', page: 3, lessonNumber: 1),
              TextbookTocEntry(title: '语文园地一', page: 3),
            ],
          ),
        )
        .pack;
    final tables = parser.vocabularyTables(pack, [
      layoutFixturePage(
        3,
        [
          '写字表',
          '识字',
          '1 星月',
          '阅读',
          '1 山河',
          '语文园地一 明亮',
          '（共6个字）',
          '常用偏旁名称表',
          '1 后记污染内容',
        ],
        step: .08,
      ),
    ]);
    String content(String id) => tables[id]!.map((v) => v.text).join();
    expect(content(pack.lessons[0].id), '星月');
    expect(content(pack.lessons[1].id), '山河');
    expect(content(pack.lessons[2].id), '明亮');
  });

  test('非汉字拼音课保留非空待定位原文，不使整课提交失败', () {
    final parsed = parser.parse(lesson, plan, [
      layoutFixturePage(2, ['b p m f', 'a o e']),
    ]);
    expect(parsed.lesson['paragraphs'], isEmpty);
    expect(parsed.candidates.single.text, contains('b p m f'));
    expect(
      TextbookDraftCandidate.fromJson(parsed.candidates.single.toJson()).text,
      isNotEmpty,
    );
  });

  test('双栏表格的较长园地行仍按栏读取，不落到总计之后', () {
    final glyphs = <TextbookPageGlyph>[];
    final text = StringBuffer();
    var index = 0;
    void row(String value, double left, double top) {
      for (final rune in value.runes) {
        text.writeCharCode(rune);
        glyphs.add(
          TextbookPageGlyph(
            text: String.fromCharCode(rune),
            index: index++,
            left: left,
            top: top,
            right: left + .018,
            bottom: top + .025,
          ),
        );
        left += .022;
      }
      text.writeln();
      index++;
    }

    row('写字表', .4, .1);
    row('1 星月', .1, .25);
    row('2 山河', .55, .25);
    row('明亮', .1, .4);
    row('风雨', .55, .4);
    // This long left row leaves a narrow gutter; the repeated column evidence
    // from other rows must still split it, instead of postponing the whole row.
    row('星月山河天地明亮', .1, .55);
    row('星光', .55, .55);
    row('（共14个字）', .55, .8);
    final tables = parser.vocabularyTables(seed.pack, [
      TextbookPageText(
        page: 3,
        text: text.toString(),
        width: 600,
        height: 800,
        glyphs: glyphs,
      ),
    ]);
    expect(
      tables[seed.pack.lessons.first.id]!.map((v) => v.text).join(),
      '星月明亮星月山河天地明亮',
    );
    expect(
      tables[seed.pack.lessons.last.id]!.map((v) => v.text).join(),
      '山河风雨星光',
    );
  });

  test('组合声调保留原始线索，不能丢声调后误写完整注音', () {
    final base = layoutFixturePage(2, ['星月测试', '星月']);
    final glyphs = [...base.glyphs];
    final text = StringBuffer(base.text);
    var index = base.text.runes.length;
    for (final han in base.glyphs.where((g) => g.top > .2)) {
      final hint = han.text == '星' ? 'xi\u0304ng' : 'yuè';
      for (final (i, rune) in hint.runes.indexed) {
        text.writeCharCode(rune);
        glyphs.add(
          TextbookPageGlyph(
            text: String.fromCharCode(rune),
            index: index++,
            left: han.left + i * .004,
            top: han.top - .02,
            right: han.left + (i + 1) * .004,
            bottom: han.top - .006,
          ),
        );
      }
    }
    final parsed = parser.parse(lesson, plan, [
      TextbookPageText(
        page: 2,
        text: text.toString(),
        width: 600,
        height: 800,
        glyphs: glyphs,
      ),
    ]);
    expect((parsed.lesson['paragraphs'] as List).single['pinyin'], isNull);
    expect(parsed.candidates.single.pinyin.join(), contains('\u0304'));
  });

  test('同一字词来自多页时合并来源，全文指令后有其他要求仍能绑定', () {
    final parsed = parser.parse(
      lesson,
      plan,
      [
        layoutFixturePage(2, ['星月测试', '星月明。', '背诵课文。读一读词语。']),
      ],
      vocabulary: const [
        TextbookDraftCandidate(
          id: 'a',
          text: '星',
          reason: '自有表',
          pages: [2],
          category: 'recognitionCharacters',
        ),
        TextbookDraftCandidate(
          id: 'b',
          text: '星',
          reason: '自有表',
          pages: [3],
          category: 'recognitionCharacters',
        ),
      ],
    );
    expect(
      (parsed.lesson['recognitionCharacters'] as List).single['sources'].length,
      2,
    );
    expect((parsed.lesson['recitations'] as List).length, 1);
  });

  test('段落首行保留原书缩进，续行折行不保留行首空白', () {
    // 原书缩进只存在于几何坐标：段首行 left 比正文左边界外扩约两字宽。
    final base = layoutFixturePage(2, [
      '星月测试',
      '星月明，山河亮。',
      '星月山河都明亮。',
      '另一段开始了。',
    ]);
    final indentedGlyphs = <TextbookPageGlyph>[];
    var index = 0;
    for (final (lineIndex, line) in [
      '星月测试',
      '星月明，山河亮。',
      '星月山河都明亮。',
      '另一段开始了。',
    ].indexed) {
      // 第 1、3 行（正文段落首行）外扩 0.06（约两字宽）。
      final x = lineIndex == 1 || lineIndex == 3 ? .16 : .1;
      var cursor = x;
      for (final rune in line.runes) {
        indentedGlyphs.add(
          TextbookPageGlyph(
            text: String.fromCharCode(rune),
            index: index++,
            left: cursor,
            top: .1 + lineIndex * .15,
            right: cursor + .025,
            bottom: .13 + lineIndex * .15,
          ),
        );
        cursor += .03;
      }
      index++;
    }
    final parsed = parser.parse(
      lesson,
      plan,
      [
        TextbookPageText(
          page: 2,
          text: base.text,
          width: 600,
          height: 800,
          glyphs: indentedGlyphs,
        ),
      ],
    );
    final paragraphs = parsed.lesson['paragraphs'] as List;
    expect(paragraphs.length, 2, reason: '几何缩进开启新段落');
    expect(paragraphs[0]['text'], '　　星月明，山河亮。\n星月山河都明亮。');
    expect(paragraphs[1]['text'], '　　另一段开始了。');
  });
}
