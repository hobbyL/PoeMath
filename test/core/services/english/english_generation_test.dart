import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/english_course_generation_service.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/textbook_toc_service.dart';
import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/data/models/textbook_toc.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/english_course_repository.dart';

import '../../../helpers/english_fixture.dart';
import '../../../helpers/textbook_draft_fixture.dart';

class _Installed extends TextbookFileService {
  @override
  Future<String?> installedPath(Textbook book) async => '/owned.pdf';
}

void main() {
  test('英语原书目录复用完整字形布局，Unit 编号不是书内页码', () async {
    final root = await Directory.systemTemp.createTemp('english-toc-');
    addTearDown(() => root.delete(recursive: true));
    final book = englishBook(pages: 4);
    final cache = TextbookContentCache(
      book: book,
      directoryProvider: () async => root,
    );
    final texts = ['Unit 1 Garden', 'Lesson 1', 'Unit 2 River', 'Lesson 1'];
    final toc = TextbookTocService(
      pageCount: 4,
      cache: cache,
      loadOutline: () async => [],
      loadPage: (p) async =>
          TextbookTocPage.fromPageText(layoutFixturePage(p, [texts[p - 1]])),
    );
    final result = (await toc.scan().last).result!;
    expect(result.entries.where((e) => e.isGroup).map((e) => e.title), [
      'Unit 1 Garden',
      'Unit 2 River',
    ]);
    expect(
      result.entries.where((e) => e.title == 'Lesson 1').map((e) => e.page),
      [2, 4],
    );
    expect(result.entries.every((e) => e.printedPage == null), isTrue);
  });
  test('逐课落盘后暂停，冷启动续跑保留首课，刷新产生独立候选且关闭 PDF', () async {
    final root = await Directory.systemTemp.createTemp('english-generation-');
    addTearDown(() => root.delete(recursive: true));
    final book = englishBook(pages: 4), sources = <DraftFixtureSource>[];
    final repository = EnglishCourseRepository(
      directoryProvider: () async => root,
    );
    final service = EnglishCourseGenerationService(
      repository,
      _Installed(),
      open:
          ({
            required path,
            required book,
            required cache,
            required token,
          }) async {
            final source = DraftFixtureSource(
              token,
              pages: {
                1: layoutFixturePage(1, ['Unit 1 Garden']),
                2: layoutFixturePage(2, ['Lesson 1', 'I see a kite.']),
                3: layoutFixturePage(3, ['Lesson 2', 'A blue bird.']),
                4: layoutFixturePage(4, ['Story Time', 'Hello, bird!']),
              },
            );
            sources.add(source);
            return source;
          },
    );
    final token = TextbookDraftToken();
    var changes = 0;
    await expectLater(
      service.run(book, token, (m, d, t) {}, () {
        if (++changes == 2) token.cancel();
      }),
      throwsA(isA<TextbookDraftCancelled>()),
    );
    final paused = (await repository.load(book))!;
    expect(paused.lessons.where((l) => l.prepared), hasLength(1));
    final first = paused.lessons.first.toJson();
    await service.run(book, TextbookDraftToken(), (m, d, t) {}, () {});
    final resumed = (await EnglishCourseRepository(
      directoryProvider: () async => root,
    ).load(book))!;
    expect(resumed.lessons.every((l) => l.prepared), isTrue);
    expect(resumed.lessons.first.toJson(), first);
    expect(resumed.coverage.length, 4);
    final edited = resumed.lessons[1].change({
      'targets': [
        ...resumed.lessons[1].targets.map((t) => t.approve().toJson()),
      ],
    });
    await repository.saveLesson(
      book,
      edited,
      expectedRevision: resumed.revision,
      check: () {},
    );
    await service.run(
      book,
      TextbookDraftToken(),
      (m, d, t) {},
      () {},
      refresh: true,
    );
    final refreshed = (await repository.load(book))!;
    expect(refreshed.lesson(edited.id)!.approvedCount, edited.approvedCount);
    expect(refreshed.pending.single.id, edited.id);
    expect(refreshed.pending.single.approvedCount, 0);
    expect(sources.every((s) => s.closed), isTrue);
  });
}
