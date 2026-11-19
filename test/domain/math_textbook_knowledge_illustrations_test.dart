import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/domain/math_textbook_knowledge_illustrations.dart';

void main() {
  MathTextbookBlock part(
    String id,
    MathTextbookBlockKind kind,
    String text,
    double left,
    double top,
    double right,
    double bottom, {
    String? number,
  }) => MathTextbookBlock(
    id: id,
    kind: kind,
    spans: [MathTextbookSpan.text(text)],
    exerciseNumber: number,
    sources: [
      MathTextbookRegion(
        page: 1,
        left: left,
        top: top,
        right: right,
        bottom: bottom,
      ),
    ],
  );
  final example = MathTextbookBlock(
    id: 'example',
    kind: MathTextbookBlockKind.example,
    exerciseNumber: '3',
    sourceLayout: true,
    spans: const [MathTextbookSpan.text('两组一共有多少人？个位相加满十，向十位进1。')],
    sources: const [
      MathTextbookRegion(
        page: 1,
        left: .05,
        top: .05,
        right: .95,
        bottom: .8,
        printedPage: '8',
      ),
    ],
  );
  final point = MathTextbookKnowledgePoint(
    id: 'carry',
    title: '进位加',
    summary: '个位相加满十，向十位进1。',
    blockIds: ['example'],
  );
  MathTextbookLesson page(List<MathTextbookBlock> blocks) => MathTextbookLesson(
    id: 'page',
    title: '自有教学图',
    startPage: 1,
    endPage: 1,
    blocks: blocks,
  );
  final parsed = page([
    part(
      'badge',
      MathTextbookBlockKind.example,
      '3 两组一共有多少人？',
      .1,
      .1,
      .9,
      .16,
      number: '3',
    ),
    part(
      'prompt',
      MathTextbookBlockKind.illustration,
      '两组一共有多少人？',
      .1,
      .18,
      .9,
      .3,
    ),
    part(
      'sticks',
      MathTextbookBlockKind.illustration,
      '十根一捆',
      .1,
      .33,
      .4,
      .47,
    ),
    part(
      'calculation',
      MathTextbookBlockKind.illustration,
      '向十位进1，个位写2。',
      .45,
      .32,
      .7,
      .49,
    ),
    part(
      'sum',
      MathTextbookBlockKind.formula,
      '35 + 37 = 72',
      .75,
      .33,
      .9,
      .44,
    ),
    part('rule', MathTextbookBlockKind.text, point.summary, .45, .5, .9, .53),
    part('practice', MathTextbookBlockKind.heading, '做一做', .1, .6, .3, .64),
    part(
      'exercise',
      MathTextbookBlockKind.exercise,
      '算一算',
      .1,
      .65,
      .9,
      .7,
      number: '1',
    ),
    part(
      'exercise-image',
      MathTextbookBlockKind.illustration,
      '',
      .1,
      .71,
      .9,
      .8,
    ),
  ]);

  test('知识图保留完整的小棒、解法与竖式，排除例题题干和后续练习', () {
    final before = example.toJson();
    final regions = mathTextbookKnowledgeIllustrationRegions(
      point: point,
      blocks: [example],
      parsedPage: parsed,
    );
    expect(regions.single.toJson(), {
      'page': 1,
      'left': .096,
      'top': .316,
      'right': .904,
      'bottom': .494,
      'printedPage': '8',
    });
    expect(example.toJson(), before);
  });

  test('图片选区重叠到做一做时，知识图在练习标题之前结束', () {
    final overlapping = page([
      for (final block in parsed.blocks)
        if (block.id == 'calculation')
          part('calculation', block.kind, block.text, .45, .32, .7, .8)
        else
          block,
    ]);
    final region = mathTextbookKnowledgeIllustrationRegions(
      point: point,
      blocks: [example],
      parsedPage: overlapping,
    ).single;
    expect(region.bottom, .6);
    expect(
      region.containsCenter(overlapping.blocks.last.sources.single),
      isFalse,
    );
  });

  test('无法定位例题内部配图时不回退到整道例题截图', () {
    final withoutMarker = page(parsed.blocks.skip(1).toList());
    expect(
      mathTextbookKnowledgeIllustrationRegions(
        point: point,
        blocks: [example],
        parsedPage: withoutMarker,
      ),
      isEmpty,
    );
  });

  test('独立知识图按明确关联显示，不要求作者摘要逐字等于图中文字', () {
    final image = part(
      'image',
      MathTextbookBlockKind.illustration,
      '十根一捆',
      .2,
      .3,
      .8,
      .5,
    );
    final authored = MathTextbookKnowledgePoint(
      id: 'custom',
      title: '理解十进制',
      summary: '十个一组成一个十。',
      blockIds: ['image'],
    );
    final regions = mathTextbookKnowledgeIllustrationRegions(
      point: authored,
      blocks: [image],
      parsedPage: page([image]),
    );
    expect(regions.single.left, closeTo(.196, .0001));
    expect(regions.single.top, .3);
    expect(regions.single.bottom, .5);
  });

  test('知识图候选只从关联内容选择，不包含原页和练习', () {
    final lesson = page([
      example,
      part('source', MathTextbookBlockKind.sourcePage, '', 0, 0, 1, 1),
      part('exercise', MathTextbookBlockKind.exercise, '算一算', .1, .6, .9, .8),
      part('unrelated', MathTextbookBlockKind.illustration, '', .1, .7, .9, .8),
    ]);
    final linked = MathTextbookKnowledgePoint(
      id: point.id,
      title: point.title,
      summary: point.summary,
      blockIds: ['example', 'source', 'exercise'],
    );
    expect(mathTextbookKnowledgeImageBlocks(lesson, linked), [example]);
  });
  test('同一行旁边的其他配图不混入当前知识图', () {
    final selected = part(
      'selected',
      MathTextbookBlockKind.illustration,
      '',
      .1,
      .3,
      .3,
      .5,
    );
    final neighbour = part(
      'neighbour',
      MathTextbookBlockKind.illustration,
      '',
      .6,
      .3,
      .8,
      .5,
    );
    final regions = mathTextbookKnowledgeIllustrationRegions(
      point: point,
      blocks: [selected],
      parsedPage: page([selected, neighbour]),
    );
    expect(regions.single.right, closeTo(.304, .0001));
  });
}
