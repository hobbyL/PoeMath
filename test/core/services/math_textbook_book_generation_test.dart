import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/math_textbook_generation_service.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_page_layout.dart';
import 'package:poemath/data/models/textbook_toc.dart';
import 'package:poemath/data/repositories/math_textbook_course_repository.dart';

import '../../helpers/math_textbook_fixture.dart';

void main() {
  final book = mathTextbookFixture();
  const toc = TextbookTocResult(
    source: TextbookTocSource.bookmarks,
    entries: [
      TextbookTocEntry(title: '第一单元', isGroup: true),
      TextbookTocEntry(title: '甲课', page: 1, level: 1),
      TextbookTocEntry(title: '乙课', page: 2, level: 1),
      TextbookTocEntry(title: '第二单元', isGroup: true),
      TextbookTocEntry(title: '丙课', page: 3, level: 1),
    ],
  );
  late Directory directory;
  late MathTextbookCourseRepository repository;
  late MathTextbookGenerationService service;
  MathTextbookPageLayout page(int number, {String text = '自有完整内容'}) =>
      (MathPageFixture(number)..text(text, .1, .1)).build();
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('math-book-resume-');
    repository = MathTextbookCourseRepository(
      directoryProvider: () async => directory,
    );
    service = MathTextbookGenerationService(
      repository,
      TextbookFileService(directoryProvider: () async => directory),
    );
  });
  tearDown(() async {
    await repository.drain();
    await directory.delete(recursive: true);
  });

  test('先显示目录再逐课保存；暂停重开只整理未完成课且保留人工审核', () async {
    final entered = Completer<void>();
    final gate = Completer<MathTextbookPageLayout>();
    final token = TextbookDraftToken();
    final snapshots = <Future<MathTextbookCourse?>>[];
    final progress = <(int, int)>[];
    final run = service.generateBook(
      book: book,
      toc: toc,
      token: token,
      authorize: () {},
      onProgress: (_, __) {},
      onLessonProgress: (done, total) => progress.add((done, total)),
      onSaved: () => snapshots.add(repository.load(book)),
      pageLoader: (number) async {
        if (number == 2) {
          entered.complete();
          return gate.future;
        }
        return page(number);
      },
    );
    final failure = expectLater(run, throwsA(isA<TextbookDraftCancelled>()));
    await entered.future;
    token.cancel();
    gate.complete(page(2));
    await failure;
    final saved = await Future.wait(snapshots);
    expect(saved.first!.lessons, isEmpty);
    expect(saved.first!.outline!.ranges, hasLength(3));
    expect(saved.last!.lessons, hasLength(1));
    expect(saved.last!.outline!.completedLessonIds, ['math-1-1']);
    expect(progress, [(0, 3), (1, 3)]);
    final manual = mathLessonFixture(title: '家长修订甲课', start: 1, end: 1).approve(
      pdfSha256: book.pdfSha256,
      reviewer: '测试家长',
      editingMilliseconds: 0,
      at: DateTime.utc(2026, 11, 14),
    );
    await repository.saveLesson(
      book,
      manual,
      expectedRevision: saved.last!.revision,
      generation: repository.generation(book.pdfSha256),
      authorize: () {},
    );
    // Reopen the actual authored file with a fresh repository/service.
    repository = MathTextbookCourseRepository(
      directoryProvider: () async => directory,
    );
    service = MathTextbookGenerationService(
      repository,
      TextbookFileService(directoryProvider: () async => directory),
    );
    final reads = <int>[];
    final resumed = await service.generateBook(
      book: book,
      token: TextbookDraftToken(),
      authorize: () {},
      onProgress: (_, __) {},
      pageLoader: (number) async {
        reads.add(number);
        return page(number);
      },
    );
    expect(reads, [2, 3]);
    expect(resumed.outline!.completedLessonIds, [
      'math-1-1',
      'math-2-2',
      'math-3-3',
    ]);
    expect(resumed.lessons.first.toJson(), manual.toJson());
    expect(resumed.pendingLessons, isEmpty);
  });

  test('重新整理中断后续接本次进度，旧稿存在也不能误判本次已完成', () async {
    final initial = await service.generateBook(
      book: book,
      toc: toc,
      token: TextbookDraftToken(),
      authorize: () {},
      onProgress: (_, __) {},
      pageLoader: (number) async => page(number),
    );
    final manual = mathLessonFixture(title: '已审甲课', start: 1, end: 1).approve(
      pdfSha256: book.pdfSha256,
      reviewer: '家长',
      editingMilliseconds: 0,
      at: DateTime.utc(2026, 11, 14),
    );
    await repository.saveLesson(
      book,
      manual,
      expectedRevision: initial.revision,
      generation: repository.generation(book.pdfSha256),
      authorize: () {},
    );
    final entered = Completer<void>();
    final gate = Completer<MathTextbookPageLayout>();
    final token = TextbookDraftToken();
    final refresh = service.generateBook(
      book: book,
      toc: toc,
      refresh: true,
      token: token,
      authorize: () {},
      onProgress: (_, __) {},
      pageLoader: (number) async {
        if (number == 2) {
          entered.complete();
          return gate.future;
        }
        return page(number, text: '新的候选内容');
      },
    );
    final failure = expectLater(
      refresh,
      throwsA(isA<TextbookDraftCancelled>()),
    );
    await entered.future;
    token.cancel();
    gate.complete(page(2));
    await failure;
    final paused = (await repository.load(book))!;
    expect(paused.lessons, hasLength(3));
    expect(paused.outline!.completedLessonIds, ['math-1-1']);
    expect(paused.lessons.first.toJson(), manual.toJson());
    expect(paused.pendingLessons.single.id, 'math-1-1');
    final reads = <int>[];
    final resumed = await service.generateBook(
      book: book,
      token: TextbookDraftToken(),
      authorize: () {},
      onProgress: (_, __) {},
      pageLoader: (number) async {
        reads.add(number);
        return page(number, text: '新的候选内容');
      },
    );
    expect(reads, [2, 3]);
    expect(resumed.outline!.completedLessonIds, hasLength(3));
    expect(resumed.lessons.first.toJson(), manual.toJson());
    expect(resumed.pendingLessons, hasLength(3));
    reads.clear();
    await service.generateBook(
      book: book,
      token: TextbookDraftToken(),
      authorize: () {},
      onProgress: (_, __) {},
      pageLoader: (number) async {
        reads.add(number);
        return page(number);
      },
    );
    expect(reads, isEmpty);
  });

  test('移除目录课时同时撤销整理进度，续接仅补回该课', () async {
    final initial = await service.generateBook(
      book: book,
      toc: toc,
      token: TextbookDraftToken(),
      authorize: () {},
      onProgress: (_, __) {},
      pageLoader: (number) async => page(number),
    );
    final removed = await repository.removeLesson(
      book,
      'math-2-2',
      expectedRevision: initial.revision,
      authorize: () {},
    );
    expect(removed.outline!.completedLessonIds, ['math-1-1', 'math-3-3']);
    final reads = <int>[];
    final restored = await service.generateBook(
      book: book,
      token: TextbookDraftToken(),
      authorize: () {},
      onProgress: (_, __) {},
      pageLoader: (number) async {
        reads.add(number);
        return page(number);
      },
    );
    expect(reads, [2]);
    expect(restored.outline!.completedLessonIds, hasLength(3));
  });

  test('旧草稿没有续接字段时，保留已审课并只补齐缺少的目录课目', () async {
    final manual = mathLessonFixture(start: 1, end: 1);
    var old = await repository.saveGenerated(
      book,
      manual,
      generation: repository.generation(book.pdfSha256),
      authorize: () {},
    );
    old = await repository.saveLesson(
      book,
      manual.approve(
        pdfSha256: book.pdfSha256,
        reviewer: '家长',
        editingMilliseconds: 0,
        at: DateTime.utc(2026, 11, 14),
      ),
      expectedRevision: old.revision,
      generation: repository.generation(book.pdfSha256),
      authorize: () {},
    );
    old = await repository.saveOutline(
      book,
      MathTextbookCourseOutline(
        source: 'bookmarks',
        ranges: const [
          MathTextbookCourseRange(title: '甲课', startPage: 1, endPage: 1),
          MathTextbookCourseRange(title: '乙课', startPage: 2, endPage: 2),
          MathTextbookCourseRange(title: '丙课', startPage: 3, endPage: 3),
        ],
      ),
      generation: repository.generation(book.pdfSha256),
      authorize: () {},
    );
    expect(old.outline!.completedLessonIds, isNull);
    final reads = <int>[];
    final migrated = await service.generateBook(
      book: book,
      token: TextbookDraftToken(),
      authorize: () {},
      onProgress: (_, __) {},
      pageLoader: (number) async {
        reads.add(number);
        return page(number);
      },
    );
    expect(reads, [2, 3]);
    expect(migrated.lessons.first.toJson(), old.lessons.first.toJson());
    expect(migrated.pendingLessons, isEmpty);
    expect(migrated.outline!.completedLessonIds, hasLength(3));
  });

  test('旧目录兼容，无对应草稿、重复或未知的完成课时不能伪造进度', () {
    final outline = MathTextbookCourseOutline(
      source: 'bookmarks',
      ranges: const [
        MathTextbookCourseRange(title: '甲课', startPage: 1, endPage: 1),
      ],
    );
    expect(
      MathTextbookCourseOutline.fromJson(outline.toJson()).completedLessonIds,
      isNull,
    );
    expect(
      () => outline.withCompleted(['math-1-1', 'math-1-1']),
      throwsFormatException,
    );
    expect(() => outline.withCompleted(['math-2-2']), throwsFormatException);
    expect(
      () =>
          MathTextbookCourse.forBook(book)
              .replace(outline: outline.withCompleted(['math-1-1'])),
      throwsFormatException,
    );
    final wrongRange = MathTextbookLesson.fromJson({
      ...mathLessonFixture().toJson(),
      'id': 'math-1-1',
    });
    expect(
      () => MathTextbookCourse.forBook(book).replace(
        lessons: [wrongRange],
        outline: outline.withCompleted(['math-1-1']),
      ),
      throwsFormatException,
    );
  });
}
