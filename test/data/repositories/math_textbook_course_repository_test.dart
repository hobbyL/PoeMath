import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart'
    show textbookContentDigest;
import 'package:poemath/data/repositories/math_textbook_course_repository.dart';
import 'package:poemath/domain/math_textbook_content_organizer.dart';

import '../../helpers/math_textbook_fixture.dart';
import '../../helpers/math_textbook_learning_fixture.dart';

void main() {
  late Directory root;
  late MathTextbookCourseRepository repository;
  final book = mathTextbookFixture();
  final lesson = mathLessonFixture();
  void authorize() {}
  setUp(() async {
    root = await Directory.systemTemp.createTemp('poemath-math-course-');
    repository = MathTextbookCourseRepository(
      directoryProvider: () async => root,
    );
  });
  tearDown(() async => root.delete(recursive: true));

  test('课程整理缓存跨实例复用，热读不重复解析；清理和原稿变化立即失效', () async {
    final files = TextbookFileService(directoryProvider: () async => root);
    repository = MathTextbookCourseRepository(
      directoryProvider: () async => root,
      files: files,
    );
    await repository.saveGenerated(
      book,
      mathMisclassifiedPracticeFixture(),
      generation: 0,
      authorize: authorize,
    );
    final originalFile = File(
      '${root.path}/textbooks/math-courses/${book.pdfSha256}.json',
    );
    final original = await originalFile.readAsString();
    final prepared = (await repository.load(book))!;
    expect(identical(await repository.load(book), prepared), isTrue);
    final cacheDirectory = Directory(
      '${root.path}/textbooks/cache/${book.pdfSha256}',
    );
    final cacheFile = (await cacheDirectory.list().toList()).single as File;
    final written = await cacheFile.lastModified();
    final reopened = MathTextbookCourseRepository(
      directoryProvider: () async => root,
    );
    expect((await reopened.load(book))!.toJson(), prepared.toJson());
    expect(await cacheFile.lastModified(), written);
    expect(await originalFile.readAsString(), original);

    await files.clearExtractedContent(book);
    expect(await cacheDirectory.list().toList(), isEmpty);
    final rebuilt = (await repository.load(book))!;
    expect(identical(rebuilt, prepared), isFalse);
    expect(rebuilt.toJson(), prepared.toJson());
    expect(await originalFile.readAsString(), original);
    await originalFile.writeAsString('{broken');
    await expectLater(repository.load(book), throwsFormatException);
    await originalFile.writeAsString(original);
    expect((await repository.load(book))!.toJson(), prepared.toJson());
  });

  test('读取时兼容当前稿与待比较稿的例题 OCR 标题，且不重写课程文件', () async {
    final source = mathMisclassifiedPracticeFixture();
    final originalExample = source.blocks.firstWhere(
      (block) => block.kind == MathTextbookBlockKind.example,
    );
    final example = MathTextbookBlock.fromJson({
      ...originalExample.toJson(),
      'exerciseNumber': '5',
    });
    MathTextbookBlock heading(String id, String title) => MathTextbookBlock(
      id: id,
      kind: MathTextbookBlockKind.heading,
      spans: [MathTextbookSpan.text(title)],
      sources: example.sources,
    );
    final draft = source.edit(
      title: '～ 9 的表内乘、除法',
      blocks: [
        heading('valid-section', '7 ～ 9的乘法口诀'),
        heading('ocr-heading', '）\n）\n八八（\n）'),
        example,
        ...source.blocks.where((block) => block != originalExample),
      ],
    );
    final old = draft.edit(
      learning: MathTextbookLearning.fromJson({
        ...seedMathTextbookLearning(draft, legacyLayout: true).toJson(),
        'knowledgePoints': [
          for (final point in seedMathTextbookLearning(
            draft,
            legacyLayout: true,
          ).knowledgePoints)
            if (point.blockIds.contains(example.id))
              {...point.toJson(), 'title': '）\n）\n八八（\n） · 例 5'}
            else
              point.toJson(),
        ],
      }),
    );
    final saved = await repository.saveGenerated(
      book,
      old,
      generation: 0,
      authorize: authorize,
    );
    final pendingDraft = draft.edit(
      blocks: [
        heading('valid-section', '7 ～ 9 的乘法口诀（新整理）'),
        ...draft.blocks.where((block) => block.id != 'valid-section'),
      ],
    );
    final pendingBaseline = seedMathTextbookLearning(
      pendingDraft,
      legacyLayout: true,
    );
    final pendingLearning = MathTextbookLearning.fromJson({
      ...pendingBaseline.toJson(),
      'knowledgePoints': [
        for (final point in pendingBaseline.knowledgePoints)
          if (point.blockIds.contains(example.id))
            {...point.toJson(), 'title': '）\n）\n八八（\n） · 例 5'}
          else
            point.toJson(),
      ],
    });
    final pending = pendingDraft.edit(learning: pendingLearning);

    final file = File(
      '${root.path}/textbooks/math-courses/${book.pdfSha256}.json',
    );
    final bytesBeforeRead = utf8.encode(
      jsonEncode({
        ...saved.toJson(),
        'pendingLessons': [pending.toJson()],
      }),
    );
    await file.writeAsBytes(bytesBeforeRead);
    final staleCourse = MathTextbookCourse.fromJson(
      jsonDecode(utf8.decode(bytesBeforeRead)),
    );
    final files = TextbookFileService(directoryProvider: () async => root);
    final staleKey = textbookContentDigest({
      'kind': 'math-course',
      'version': 1,
      'source': sha256.convert(bytesBeforeRead).toString(),
    });
    await files
        .contentCache(book)
        .mathData<MathTextbookCourse>(
          staleKey,
          decode: MathTextbookCourse.fromJson,
          encode: (course) => course.toJson(),
          load: () async => staleCourse,
        );
    repository = MathTextbookCourseRepository(
      directoryProvider: () async => root,
      files: files,
    );
    final loaded = (await repository.load(book))!;
    for (final (lesson, expectedTitle) in [
      (loaded.lessons.single, '7 ～ 9的乘法口诀 · 例 5'),
      (loaded.pendingLessons.single, '7 ～ 9 的乘法口诀（新整理） · 例 5'),
    ]) {
      expect(
        lesson.learning!.knowledgePoints
            .firstWhere((point) => point.blockIds.contains(example.id))
            .title,
        expectedTitle,
      );
    }
    expect(await file.readAsBytes(), bytesBeforeRead);
  });

  for (final large in [false, true]) {
    test('旧自动分类读取时修正，练习写入读取同一配置，原文件不变（后台：$large）', () async {
      final original = mathMisclassifiedPracticeFixture(
        illustratedHeading: true,
      );
      final saved = await repository.saveGenerated(
        book,
        original,
        generation: 0,
        authorize: authorize,
      );
      final file = File(
        '${root.path}/textbooks/math-courses/${book.pdfSha256}.json',
      );
      final raw =
          '${large ? ' ' * (64 * 1024) : ''}${jsonEncode(saved.toJson())}';
      await file.writeAsString(raw);

      final loaded = (await repository.load(book))!;
      expect(loaded.revision, saved.revision);
      expect(loaded.lessons.single.learning!.knowledgePoints.map((k) => k.id), [
        'example-knowledge',
        'next-example-knowledge',
      ]);
      expect(loaded.lessons.single.learning!.exercises.map((e) => e.blockIds), [
        ['practice-heading', 'practice-body'],
        ['numbered'],
        ['continued-practice'],
      ]);
      expect(
        loaded.lessons.single.blocks.map((b) => b.toJson()),
        original.blocks.map((b) => b.toJson()),
      );
      expect(loaded.lessons.single.review, isNull);
      await repository.withCurrentCourse(book, (current) async {
        expect(current!.toJson(), loaded.toJson());
      });
      expect(await file.readAsString(), raw);
    });
  }

  for (final reviewed in [false, true]) {
    test('分类兼容不重写${reviewed ? '已审核' : '人工修改'}的学习配置', () async {
      final original = mathMisclassifiedPracticeFixture();
      final preserved = reviewed
          ? original.approve(
              pdfSha256: book.pdfSha256,
              reviewer: '测试家长',
              editingMilliseconds: 1000,
            )
          : original.edit(
              learning: MathTextbookLearning.fromJson({
                ...original.learning!.toJson(),
                'knowledgePoints': [
                  for (final point in original.learning!.knowledgePoints)
                    {...point.toJson(), 'summary': '${point.summary}家长补充说明。'},
                ],
              }),
            );
      final saved = await repository.saveGenerated(
        book,
        preserved,
        generation: 0,
        authorize: authorize,
      );
      expect((await repository.load(book))!.toJson(), saved.toJson());
    });
  }

  test('整书量级草稿在后台解码后保留正文、审核和教材身份校验', () async {
    final dense = denseMathLearningFixture().approve(
      pdfSha256: book.pdfSha256,
      reviewer: '测试家长',
      editingMilliseconds: 1000,
    );
    final saved = await repository.saveGenerated(
      book,
      dense,
      generation: 0,
      authorize: authorize,
    );
    final file = File(
      '${root.path}/textbooks/math-courses/${book.pdfSha256}.json',
    );
    expect(await file.length(), greaterThan(64 * 1024));
    final loaded = (await repository.load(book))!;
    expect(loaded.toJson(), saved.toJson());
    expect(loaded.lessons.single.isApproved(book.pdfSha256), isTrue);
    await expectLater(
      repository.load(book.withSubject(TextbookSubject.chinese)),
      throwsFormatException,
    );
  });

  test('人工把大量内容合为少量知识点时，读取不受自动摘录数量上限影响', () async {
    final source = denseMathLearningFixture(additionalBlocks: 150);
    final manual = source.edit(
      learning: MathTextbookLearning.fromJson({
        ...source.learning!.toJson(),
        'coverageConfirmed': false,
      }),
    );
    final saved = await repository.saveGenerated(
      book,
      manual,
      generation: 0,
      authorize: authorize,
    );
    expect((await repository.load(book))!.toJson(), saved.toJson());
  });

  test('后台解码拒绝损坏大文件，失败后课程队列仍可读取', () async {
    final saved = await repository.saveGenerated(
      book,
      lesson,
      generation: 0,
      authorize: authorize,
    );
    final file = File(
      '${root.path}/textbooks/math-courses/${book.pdfSha256}.json',
    );
    final broken = '${' ' * (64 * 1024)}{truncated';
    await file.writeAsString(broken);
    await expectLater(repository.load(book), throwsFormatException);
    expect(await file.readAsString(), broken);
    await file.writeAsString(jsonEncode(saved.toJson()));
    expect((await repository.load(book))!.toJson(), saved.toJson());
  });

  test('后台解析前仍在流式读取中拒绝超过16 MiB的文件', () async {
    await repository.saveGenerated(
      book,
      lesson,
      generation: 0,
      authorize: authorize,
    );
    final file = File(
      '${root.path}/textbooks/math-courses/${book.pdfSha256}.json',
    );
    await file.writeAsString(' ' * (MathTextbookCourseRepository.maxBytes + 1));
    await expectLater(repository.load(book), throwsFormatException);
  });

  test('生成、人工修改、审核、重启、缓存清理保留同一份草稿', () async {
    final generated = await repository.saveGenerated(
      book,
      lesson,
      generation: 0,
      authorize: authorize,
    );
    final reviewed = lesson
        .edit(title: '家长补齐的分数课')
        .approve(
          pdfSha256: book.pdfSha256,
          reviewer: '测试家长',
          editingMilliseconds: 3500,
        );
    final saved = await repository.saveLesson(
      book,
      reviewed,
      expectedRevision: generated.revision,
      generation: 0,
      authorize: authorize,
    );
    await TextbookFileService(directoryProvider: () async => root)
        .clearDerived(book);
    final reopened = MathTextbookCourseRepository(
      directoryProvider: () async => root,
    );
    expect((await reopened.load(book))!.toJson(), saved.toJson());
    expect(
      (await reopened.load(book))!.lessons.single.isApproved(book.pdfSha256),
      isTrue,
    );
    await TextbookFileService(directoryProvider: () async => root)
        .removePdf(book.pdfSha256);
    expect((await reopened.load(book))!.toJson(), saved.toJson());
  });

  test('重整只新增待采纳结果，旧页不能覆盖，显式采纳清除审核', () async {
    final generated = await repository.saveGenerated(
      book,
      lesson,
      generation: 0,
      authorize: authorize,
    );
    final manual = lesson
        .edit(title: '人工改过')
        .approve(
          pdfSha256: book.pdfSha256,
          reviewer: '测试家长',
          editingMilliseconds: 2000,
        );
    final saved = await repository.saveLesson(
      book,
      manual,
      expectedRevision: generated.revision,
      generation: 0,
      authorize: authorize,
    );
    final pending = await repository.saveGenerated(
      book,
      lesson,
      generation: 0,
      authorize: authorize,
    );
    expect(pending.lessons.single.toJson(), manual.toJson());
    expect(pending.pendingLessons.single.toJson(), lesson.toJson());
    await expectLater(
      repository.saveLesson(
        book,
        lesson.edit(title: '旧页'),
        expectedRevision: saved.revision,
        generation: 0,
        authorize: authorize,
      ),
      throwsFormatException,
    );
    final accepted = await repository.acceptPending(
      book,
      lesson.id,
      expectedRevision: pending.revision,
      generation: 0,
      authorize: authorize,
    );
    expect(accepted.lessons.single.toJson(), lesson.toJson());
    expect(accepted.lessons.single.review, isNull);
    expect(accepted.pendingLessons, isEmpty);
  });

  test('重整内容相同不会丢失审核或产生虚假差异', () async {
    final first = await repository.saveGenerated(
      book,
      lesson,
      generation: 0,
      authorize: authorize,
    );
    final reviewed = lesson.approve(
      pdfSha256: book.pdfSha256,
      reviewer: '测试家长',
      editingMilliseconds: 1000,
    );
    final saved = await repository.saveLesson(
      book,
      reviewed,
      expectedRevision: first.revision,
      generation: 0,
      authorize: authorize,
    );
    final again = await repository.saveGenerated(
      book,
      lesson,
      generation: 0,
      authorize: authorize,
    );
    expect(again.toJson(), saved.toJson());
  });

  test('写临时文件后撤销授权不会破坏原草稿，队列可继续使用', () async {
    final first = await repository.saveGenerated(
      book,
      lesson,
      generation: 0,
      authorize: authorize,
    );
    void revokeAtCommit() {
      if (root.listSync(recursive: true).any((f) => f.path.contains('.tmp-'))) {
        throw const ParentAccessDenied();
      }
    }

    await expectLater(
      repository.saveLesson(
        book,
        lesson.edit(title: '不得写入'),
        expectedRevision: first.revision,
        generation: 0,
        authorize: revokeAtCommit,
      ),
      throwsA(isA<ParentAccessDenied>()),
    );
    expect((await repository.load(book))!.toJson(), first.toJson());
    expect(
      root.listSync(recursive: true).where((f) => f.path.contains('.tmp-')),
      isEmpty,
    );
    final next = await repository.saveLesson(
      book,
      lesson.edit(title: '允许保存'),
      expectedRevision: first.revision,
      generation: 0,
      authorize: authorize,
    );
    expect(next.lessons.single.title, '允许保存');
  });

  test('删除时使等候中的保存失效，迟到写入不能重建草稿', () async {
    final first = await repository.saveGenerated(
      book,
      lesson,
      generation: 0,
      authorize: authorize,
    );
    final entered = Completer<void>();
    final gate = Completer<Directory>();
    var delayed = true;
    final waiting = MathTextbookCourseRepository(
      directoryProvider: () {
        if (delayed) {
          delayed = false;
          entered.complete();
          return gate.future;
        }
        return Future.value(root);
      },
    );
    final saving = waiting.saveLesson(
      book,
      lesson.edit(title: '迟到'),
      expectedRevision: first.revision,
      generation: 0,
      authorize: authorize,
    );
    final rejection = expectLater(saving, throwsFormatException);
    await entered.future;
    final deleting = waiting.clear(book);
    gate.complete(root);
    await rejection;
    await deleting;
    expect(await waiting.load(book), isNull);
    await expectLater(
      waiting.saveGenerated(book, lesson, generation: 0, authorize: authorize),
      throwsFormatException,
    );
    expect(await waiting.load(book), isNull);
  });

  test('损坏文件不能被生成操作悄悄覆盖', () async {
    await repository.saveGenerated(
      book,
      lesson,
      generation: 0,
      authorize: authorize,
    );
    final file = File(
      '${root.path}/textbooks/math-courses/${book.pdfSha256}.json',
    );
    await file.writeAsString('{truncated');
    await expectLater(
      repository.saveGenerated(
        book,
        lesson,
        generation: 0,
        authorize: authorize,
      ),
      throwsFormatException,
    );
    expect(await file.readAsString(), '{truncated');
  });
}
