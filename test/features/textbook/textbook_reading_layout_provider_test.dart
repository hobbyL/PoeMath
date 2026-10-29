import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/domain/textbook_text_display.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

import '../../helpers/textbook_course_fixture.dart';
import '../../helpers/textbook_draft_fixture.dart';

class _CachedFiles extends TextbookFileService {
  _CachedFiles(this.cache);
  final TextbookContentCache cache;
  var pathReads = 0;

  @override
  TextbookContentCache contentCache(Textbook book) => cache;

  @override
  Future<String?> installedPath(Textbook book) async {
    pathReads++;
    throw StateError('已有布局缓存不应打开 PDF');
  }
}

void main() {
  test('单行段落利用同课正文边距恢复几何缩进，课程数据保持原样', () async {
    final directory = await Directory.systemTemp.createTemp('reading_indent_');
    addTearDown(() => directory.delete(recursive: true));
    final book = courseFixtureBook();
    final base = layoutFixturePage(2, ['前段星月明，', '山河也明亮。', '短段𠀀。']);
    final start = '前段星月明，\n山河也明亮。\n'.runes.length;
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
            left: glyph.left + (glyph.index >= start ? .06 : 0),
            right: glyph.right + (glyph.index >= start ? .06 : 0),
            top: glyph.top,
            bottom: glyph.bottom,
          ),
      ],
    );
    final cache = TextbookContentCache(
      book: book,
      directoryProvider: () async => directory,
    );
    await cache.pageLayout(2, () async => page);
    final raw = courseFixture();
    final lesson = (raw['lessons'] as List).single as Map;
    lesson['paragraphs'] = [
      courseFixtureText('prior', '　　前段星月明，\n山河也明亮。', null),
      courseFixtureText('last', '短段𠀀。', null),
    ];
    lesson['recitations'] = <Object>[];
    (lesson['coverage'] as Map)['recitations'] = 'notApplicable';
    final pack = TextbookCoursePack.fromJson(raw);
    final before = pack.toJson();
    final files = _CachedFiles(cache);
    final container = ProviderContainer(
      overrides: [
        textbookListProvider.overrideWithValue([book]),
        textbookFileServiceProvider.overrideWithValue(files),
        textbookCourseProvider(book.pdfSha256).overrideWith((_) async => pack),
      ],
    );
    addTearDown(container.dispose);
    final provider = textbookReadingLayoutProvider(
      (bookId: book.pdfSha256, lessonId: 'lesson-001'),
    );
    final subscription = container.listen(provider, (_, __) {});
    addTearDown(subscription.close);
    final layouts = await container.read(provider.future);
    expect(layouts['last']!.leadingIndentCells, 2);
    expect(layouts['prior']!.leadingIndentCells, 0);
    expect(pack.toJson(), before);
    expect(files.pathReads, 0);
  });

  test('读一读按需读取冷布局缓存，恢复text课目的诗行分节且不改写课程', () async {
    final directory = await Directory.systemTemp.createTemp('reading_layout_');
    addTearDown(() => directory.delete(recursive: true));
    final book = courseFixtureBook();
    const lines = [
      '甲星光，',
      '乙月光。',
      '丙山光，',
      '丁水光。',
      '戊春风，',
      '己夏风。',
      '庚秋风，',
      '辛冬风。',
    ];
    final base = layoutFixturePage(2, lines);
    final glyphs = <TextbookPageGlyph>[];
    for (final glyph in base.glyphs) {
      final row = base.text.runes
          .take(glyph.index)
          .where((rune) => rune == 0x0a)
          .length;
      final top = .1 + row * .05 + (row ~/ 4) * .025;
      glyphs.add(
        TextbookPageGlyph(
          text: glyph.text,
          index: glyph.index,
          left: glyph.left,
          right: glyph.right,
          top: top,
          bottom: top + .03,
        ),
      );
    }
    final page = TextbookPageText(
      page: 2,
      text: base.text,
      width: base.width,
      height: base.height,
      glyphs: glyphs,
    );
    TextbookContentCache cache() => TextbookContentCache(
          book: book,
          directoryProvider: () async => directory,
        );
    await cache().pageLayout(2, () async => page);
    final files = _CachedFiles(cache());
    final raw = courseFixture();
    final lesson = (raw['lessons'] as List).single as Map;
    lesson['paragraphs'] = [
      courseFixtureText('verse', '　　${lines.join('\n')}', null),
    ];
    lesson['recitations'] = <Object>[];
    (lesson['coverage'] as Map)['recitations'] = 'notApplicable';
    final pack = TextbookCoursePack.fromJson(raw);
    final before = pack.toJson();
    final container = ProviderContainer(
      overrides: [
        textbookListProvider.overrideWithValue([book]),
        textbookFileServiceProvider.overrideWithValue(files),
        textbookCourseProvider(book.pdfSha256).overrideWith((_) async => pack),
      ],
    );
    addTearDown(container.dispose);
    final provider = textbookReadingLayoutProvider(
      (bookId: book.pdfSha256, lessonId: 'lesson-001'),
    );
    final subscription = container.listen(provider, (_, __) {});
    addTearDown(subscription.close);
    final layout = (await container.read(provider.future))['verse']!;
    expect(files.pathReads, 0);
    expect(layout.retainLeadingIndent, isFalse);
    expect(layout.breaks, hasLength(7));
    expect(
      layout.breaks.values
          .where((value) => value == TextbookReadingBreak.stanza),
      hasLength(1),
    );
    expect(pack.toJson(), before);
  });
}
