import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/math_textbook_generation_service.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_page_layout.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/math_textbook_course_repository.dart';

import '../../helpers/math_textbook_fixture.dart';

void main() {
  late Directory root;
  late MathTextbookCourseRepository repository;
  late MathTextbookGenerationService service;
  final book = mathTextbookFixture();
  MathTextbookPageLayout page(int number) =>
      (MathPageFixture(number)..text('自有内容', .1, .1)).build();
  setUp(() async {
    root = await Directory.systemTemp.createTemp('poemath-math-generation-');
    repository = MathTextbookCourseRepository(
      directoryProvider: () async => root,
    );
    service = MathTextbookGenerationService(
      repository,
      TextbookFileService(directoryProvider: () async => root),
    );
  });
  tearDown(() async => root.delete(recursive: true));

  test('完整范围读取包含失败页，失败页保存整页来源和待核原因', () async {
    final reads = <int>[], progress = <int>[];
    final course = await service.generate(
      book: book,
      title: '三页完整课',
      startPage: 1,
      endPage: 3,
      token: TextbookDraftToken(),
      authorize: () {},
      onProgress: (done, total) {
        expect(total, 3);
        progress.add(done);
      },
      pageLoader: (number) async {
        reads.add(number);
        if (number == 2) throw StateError('no text layer');
        return page(number);
      },
    );
    expect(reads, [1, 2, 3]);
    expect(progress, [1, 2, 3]);
    final sources = course.lessons.single.blocks
        .where((b) => b.kind == MathTextbookBlockKind.sourcePage)
        .toList();
    expect(sources.map((b) => b.sources.single.page), [1, 2, 3]);
    expect(sources[1].warnings, isNotEmpty);
    expect((await repository.load(book))!.toJson(), course.toJson());
  });

  for (final action in ['cancel', 'lock', 'delete']) {
    test('$action 使正在读取的课时失效，不能保存半课或迟到结果', () async {
      final entered = Completer<void>();
      final gate = Completer<MathTextbookPageLayout>();
      final token = TextbookDraftToken();
      var allowed = true;
      final result = service.generate(
        book: book,
        title: '中断课',
        startPage: 1,
        endPage: 3,
        token: token,
        authorize: () {
          if (!allowed) throw const ParentAccessDenied();
        },
        onProgress: (_, __) {},
        pageLoader: (number) async {
          if (number == 2) {
            entered.complete();
            return gate.future;
          }
          return page(number);
        },
      );
      final failed = expectLater(
        result,
        throwsA(
          action == 'cancel'
              ? isA<TextbookDraftCancelled>()
              : action == 'lock'
              ? isA<ParentAccessDenied>()
              : isA<FormatException>(),
        ),
      );
      await entered.future;
      switch (action) {
        case 'cancel':
          token.cancel();
        case 'lock':
          allowed = false;
        case 'delete':
          await repository.clear(book);
      }
      gate.complete(page(2));
      await failed;
      expect(await repository.load(book), isNull);
    });
  }

  test('非数学教材与错误页来源不能进入数学仓储', () async {
    await expectLater(
      service.generate(
        book: book.withSubject(TextbookSubject.chinese),
        title: '错误学科',
        startPage: 1,
        endPage: 1,
        token: TextbookDraftToken(),
        authorize: () {},
        onProgress: (_, __) {},
        pageLoader: (number) async => page(number),
      ),
      throwsFormatException,
    );
    await expectLater(
      service.generate(
        book: book,
        title: '错误来源',
        startPage: 1,
        endPage: 1,
        token: TextbookDraftToken(),
        authorize: () {},
        onProgress: (_, __) {},
        pageLoader: (_) async => page(2),
      ),
      throwsFormatException,
    );
    expect(await repository.load(book), isNull);
  });
}
