import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/textbook_toc_service.dart';
import 'package:poemath/data/models/textbook_toc.dart';

TextbookTocPage page(List<(String, double, double)> lines) {
  final glyphs = <TextbookTocGlyph>[];
  for (final (text, left, top) in lines) {
    for (var i = 0; i < text.length; i++) {
      glyphs.add(
        TextbookTocGlyph(
          text: text[i],
          left: left + i * 0.012,
          right: left + (i + 1) * 0.012,
          top: top,
          height: 0.015,
        ),
      );
    }
  }
  return TextbookTocPage(
    lines.map((line) => line.$1).join('\n'),
    glyphs: glyphs,
  );
}

void main() {
  test('没有单元头时，集合子篇只比父课深一层', () async {
    final toc = page([
      ('目录', 0.4, 0.05),
      ('1 古诗二首', 0.1, 0.2),
      ('1', 0.8, 0.2),
      ('朝霞', 0.18, 0.3),
      ('1', 0.8, 0.3),
      ('晚风', 0.18, 0.4),
      ('2', 0.8, 0.4),
      ('语文园地', 0.1, 0.5),
      ('3', 0.8, 0.5),
    ]);
    final service = TextbookTocService(
      pageCount: 5,
      loadOutline: () async => [],
      loadPage: (number) async => number == 2 ? toc : const TextbookTocPage(''),
    );
    expect(
      (await service.scan().last).result!.entries.map((e) => e.level),
      [0, 1, 1, 0],
    );
  });

  test('单元保留独立课号，跨栏跨页延续，集合子篇和附录归属正确', () async {
    final pages = {
      4: page([
        ('目录', 0.4, 0.05),
        ('第一单元·识字', 0.1, 0.12),
        ('1 星河', 0.1, 0.2),
        ('1', 0.43, 0.2),
        ('2 古诗二首', 0.1, 0.3),
        ('2', 0.43, 0.3),
        ('朝霞', 0.16, 0.4),
        ('2', 0.43, 0.4),
        ('晚风', 0.16, 0.5),
        ('3', 0.43, 0.5),
        ('3 远山', 0.6, 0.15),
        ('4', 0.9, 0.15),
        ('语文园地一', 0.6, 0.25),
        ('5', 0.9, 0.25),
        ('第二单元·阅读', 0.6, 0.35),
        ('1 春雨', 0.6, 0.45),
        ('6', 0.9, 0.45),
        ('2 流水', 0.6, 0.55),
        ('7', 0.9, 0.55),
      ]),
      5: page([
        ('3 秋色', 0.1, 0.1),
        ('8', 0.43, 0.1),
        ('第三单元', 0.1, 0.2),
        ('9', 0.43, 0.2),
        ('习作例文：', 0.1, 0.3),
        ('小草', 0.16, 0.4),
        ('10', 0.43, 0.4),
        ('竹林', 0.16, 0.5),
        ('11', 0.43, 0.5),
        ('习作：身边风景', 0.1, 0.6),
        ('12', 0.43, 0.6),
        ('古诗词诵读', 0.1, 0.7),
        ('1 晨光', 0.1, 0.75),
        ('13', 0.43, 0.75),
        ('写字表', 0.1, 0.85),
        ('14', 0.43, 0.85),
      ]),
    };
    final service = TextbookTocService(
      pageCount: 20,
      loadOutline: () async => [],
      loadPage: (number) async => pages[number] ?? const TextbookTocPage(''),
    );
    final result = (await service.scan().last).result!;
    expect(result.directoryPages, [4, 5]);
    expect(result.entries.map((e) => (e.title, e.lessonNumber, e.level)), [
      ('第一单元·识字', null, 0),
      ('星河', 1, 1),
      ('古诗二首', 2, 1),
      ('朝霞', null, 2),
      ('晚风', null, 2),
      ('远山', 3, 1),
      ('语文园地一', null, 1),
      ('第二单元·阅读', null, 0),
      ('春雨', 1, 1),
      ('流水', 2, 1),
      ('秋色', 3, 1),
      ('第三单元', null, 0),
      ('习作例文：', null, 1),
      ('小草', null, 2),
      ('竹林', null, 2),
      ('习作：身边风景', null, 1),
      ('古诗词诵读', null, 0),
      ('晨光', 1, 1),
      ('写字表', null, 0),
    ]);
    expect(result.entries.first.isGroup, isTrue);
    expect(result.entries.first.printedPage, isNull);
    expect(result.entries.first.page, isNull);
    expect(result.entries.firstWhere((e) => e.title == '第三单元').printedPage, 9);
  });

  test('字框高度差异不丢字，左栏分组不能吞入右栏课号或标题', () async {
    final toc = page([
      ('目录', 0.4, 0.05),
      ('星河', 0.1, 0.2),
      ('11', 0.46, 0.2),
      ('远山', 0.1, 0.3),
      ('12', 0.46, 0.3),
      ('流水', 0.1, 0.4),
      ('13', 0.46, 0.4),
      ('朝霞', 0.6, 0.2),
      ('21', 0.9, 0.2),
      ('晚风', 0.6, 0.3),
      ('22', 0.9, 0.3),
      ('一叶', 0.6, 0.4),
      ('23', 0.9, 0.4),
      ('无页码分组', 0.1, 0.5),
      ('7', 0.55, 0.5),
      ('春雨', 0.6, 0.5),
      ('24', 0.9, 0.5),
    ]);
    final glyphs = toc.glyphs
        .map(
          (g) => TextbookTocGlyph(
            text: g.text,
            left: g.left,
            right: g.right,
            top: g.text == '一' ? g.top + 0.0065 : g.top,
            height: g.text == '一' ? 0.002 : g.height,
          ),
        )
        .toList();
    final service = TextbookTocService(
      pageCount: 30,
      loadOutline: () async => [],
      loadPage: (number) async => number == 4
          ? TextbookTocPage(toc.text, glyphs: glyphs)
          : const TextbookTocPage(''),
    );
    final result = (await service.scan().last).result!;
    expect(
      result.entries.map((e) => e.title),
      ['星河', '远山', '流水', '朝霞', '晚风', '一叶', '春雨'],
    );
    expect(
      result.entries.map((e) => e.printedPage),
      [11, 12, 13, 21, 22, 23, 24],
    );
  });

  test('内置目录优先、保留层级、过滤越界目的页，不提取全文', () async {
    final service = TextbookTocService(
      pageCount: 20,
      loadOutline: () async => const [
        TextbookTocEntry(title: '第一章'),
        TextbookTocEntry(title: '起航', page: 3, level: 1),
        TextbookTocEntry(title: '无效页', page: 21),
      ],
      loadPage: (_) => throw StateError('不应读取全文'),
    );
    final result = (await service.scan().last).result!;
    expect(result.source, TextbookTocSource.bookmarks);
    expect(result.entries.map((entry) => entry.page), [null, 3, null]);
    expect(result.entries[1].level, 1);
  });

  test('任意位置及跨页文字目录，正文标题和页脚校准不同偏移', () async {
    for (final offset in [2, 7]) {
      final pages = <int, TextbookTocPage>{
        15: page(
          [('目录', 0.4, 0.1), ('1 星河……1', 0.1, 0.2), ('2 远山……2', 0.1, 0.3)],
        ),
        16: page([('3 流水……3', 0.1, 0.2), ('4 未知……8', 0.1, 0.3)]),
        1 + offset: page([('星河', 0.1, 0.2), ('1', 0.5, 0.95)]),
        2 + offset: page([('远山', 0.1, 0.2), ('2', 0.5, 0.95)]),
        3 + offset: page([('流水', 0.1, 0.2), ('3', 0.5, 0.95)]),
      };
      final service = TextbookTocService(
        pageCount: 20,
        loadOutline: () async => [],
        loadPage: (number) async =>
            pages[number] ?? const TextbookTocPage('正文'),
      );
      final result = (await service.scan().last).result!;
      expect(result.directoryPages, [15, 16]);
      expect(
        result.entries.map((entry) => entry.title),
        ['星河', '远山', '流水', '未知'],
      );
      expect(
        result.entries.map((entry) => entry.page),
        [1 + offset, 2 + offset, 3 + offset, null],
      );
    }
  });

  test('恢复打乱的双栏顺序，保留拼音标题和缩进层级', () async {
    final toc = page([
      ('目录', 0.4, 0.05),
      ('a o e', 0.55, 0.2),
      ('9', 0.9, 0.2),
      ('1 朝霞', 0.1, 0.2),
      ('1', 0.43, 0.2),
      ('晚风', 0.15, 0.3),
      ('2', 0.43, 0.3),
      ('i u ü', 0.55, 0.3),
      ('10', 0.9, 0.3),
    ]);
    final service = TextbookTocService(
      pageCount: 20,
      loadOutline: () async => [],
      loadPage: (number) async => number == 3 ? toc : const TextbookTocPage(''),
    );
    final result = (await service.scan().last).result!;
    expect(
      result.entries.map((entry) => entry.title),
      ['朝霞', '晚风', 'a o e', 'i u ü'],
    );
    expect(result.entries[1].level, greaterThan(0));
    expect(result.entries.every((entry) => entry.page == null), isTrue);
  });

  test('重复标题用页脚区分，不能定位的条目不猜测页码', () async {
    final pages = {
      1: page([
        ('目录', 0.3, 0.1),
        ('古诗二首', 0.1, 0.2),
        ('2', 0.8, 0.2),
        ('古诗二首', 0.1, 0.3),
        ('7', 0.8, 0.3),
        ('未知', 0.1, 0.4),
        ('9', 0.8, 0.4),
      ]),
      4: page([('古诗二首', 0.1, 0.2), ('2', 0.5, 0.95)]),
      9: page([('古诗二首', 0.1, 0.2), ('7', 0.5, 0.95)]),
    };
    final service = TextbookTocService(
      pageCount: 12,
      loadOutline: () async => [],
      loadPage: (number) async => pages[number] ?? const TextbookTocPage(''),
    );
    expect(
      (await service.scan().last).result!.entries.map((e) => e.page),
      [4, 9, null],
    );
  });

  test('文件分段书签回退文字目录，完成结果内存复用，强制刷新重新读取', () async {
    var loads = 0;
    final service = TextbookTocService(
      pageCount: 10,
      loadOutline: () async =>
          const [TextbookTocEntry(title: '36126-0_DJD', page: 1)],
      loadPage: (number) async {
        loads++;
        return TextbookTocPage(number == 2 ? '目录\n星河 1\n远山 2' : '');
      },
    );
    final first = (await service.scan().last).result!;
    expect(first.source, TextbookTocSource.text);
    expect(first.entries.map((e) => e.title), ['星河', '远山']);
    final count = loads;
    expect((await service.scan().last).result, same(first));
    expect(loads, count);
    await service.scan(refresh: true).last;
    expect(loads, greaterThan(count));
  });

  test('无文字和无目录分别报告，页读取失败可重试', () async {
    var fail = true;
    final service = TextbookTocService(
      pageCount: 3,
      loadOutline: () async => [],
      loadPage: (_) async {
        if (fail) throw StateError('暂时不可读');
        return const TextbookTocPage('');
      },
    );
    await expectLater(service.scan().last, throwsStateError);
    fail = false;
    final empty = (await service.scan().last).result!;
    expect(empty.entries, isEmpty);
    expect(empty.hasText, isFalse);
    final text = TextbookTocService(
      pageCount: 1,
      loadOutline: () async => [],
      loadPage: (_) async => const TextbookTocPage('普通正文'),
    );
    expect((await text.scan().last).result!.hasText, isTrue);
  });

  test('取消后不继续读取剩余页面，未完成结果不进入缓存', () async {
    var loads = 0;
    final service = TextbookTocService(
      pageCount: 100,
      loadOutline: () async => [],
      loadPage: (_) async {
        loads++;
        return const TextbookTocPage('');
      },
    );
    await service.scan().take(3).toList();
    expect(loads, 2);
    await service.scan().last;
    expect(loads, 102);
  });
}
