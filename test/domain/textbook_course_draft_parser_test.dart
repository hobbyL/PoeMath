import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_draft.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/data/models/textbook_toc.dart';
import 'package:poemath/domain/textbook_course_draft_parser.dart';

import '../helpers/textbook_draft_fixture.dart';

void main() {
  final parser = TextbookCourseDraftParser();
  final seed = parser.seed(draftFixtureEntry(), draftFixtureToc);
  final lesson = seed.pack.lessons.first;
  final plan = seed.generation!.plans.first;

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
}
