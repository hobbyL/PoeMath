import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_catalog.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/data/models/textbook_toc.dart';

import 'textbook_course_fixture.dart';

TextbookCatalogEntry draftFixtureEntry() => TextbookCatalogEntry.fromJson(
      (courseFixtureCatalog()['books'] as List).single as Map<String, dynamic>,
    );

const draftFixtureToc = TextbookTocResult(
  source: TextbookTocSource.text,
  directoryPages: [1],
  entries: [
    TextbookTocEntry(title: '第一单元', isGroup: true),
    TextbookTocEntry(title: '星月测试', page: 2, lessonNumber: 1, level: 1),
    TextbookTocEntry(title: '山河测试', page: 3, lessonNumber: 2, level: 1),
  ],
);

/// 自有文字和归一化字符坐标；不是提取自真实教材的 fixture。
TextbookPageText draftFixturePage(int number) => layoutFixturePage(
      number,
      number == 2
          ? ['星月测试', '星𠀀，月。', '朗读课文。背诵全文。']
          : number == 3
              ? ['山河测试', '山河，星光。']
              : ['自有教材'],
    );

TextbookPageText layoutFixturePage(
  int number,
  List<String> lines, {
  double step = .15,
}) {
  final glyphs = <TextbookPageGlyph>[];
  final text = lines.join('\n');
  var index = 0;
  for (final (lineIndex, line) in lines.indexed) {
    var x = .1;
    for (final rune in line.runes) {
      final value = String.fromCharCode(rune);
      glyphs.add(
        TextbookPageGlyph(
          text: value,
          index: index++,
          left: x,
          top: .1 + lineIndex * step,
          right: x + .025,
          bottom: .13 + lineIndex * step,
        ),
      );
      x += .03;
    }
    index++;
  }
  return TextbookPageText(
    page: number,
    text: text,
    width: 600,
    height: 800,
    glyphs: glyphs,
  );
}

class DraftFixtureSource implements TextbookPdfSource {
  DraftFixtureSource(
    this.token, {
    this.pages = const {},
    this.result = draftFixtureToc,
  });
  final TextbookDraftToken token;
  final Map<int, TextbookPageText> pages;
  final TextbookTocResult result;
  bool closed = false;
  int tocReads = 0;
  final reads = <int>[];
  @override
  void check() => token.check();
  @override
  Future<TextbookPageText> page(int number) async {
    check();
    reads.add(number);
    return pages[number] ?? draftFixturePage(number);
  }

  @override
  Stream<TextbookTocProgress> toc({bool refresh = false}) async* {
    check();
    tocReads++;
    yield TextbookTocProgress(
      phase: TextbookTocPhase.ready,
      scanned: 3,
      total: 3,
      result: result,
    );
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

typedef DraftFixtureOpener = Future<TextbookPdfSource> Function({
  required String path,
  required Textbook book,
  required TextbookContentCache cache,
  required TextbookDraftToken token,
});
