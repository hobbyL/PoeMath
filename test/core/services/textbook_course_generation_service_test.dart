import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/textbook_course_generation_service.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_draft.dart';
import 'package:poemath/data/models/textbook_course_review.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/domain/textbook_course_mutations.dart';
import 'package:poemath/features/textbook/providers/textbook_generation_controller.dart';

import '../../helpers/textbook_draft_fixture.dart';

void main() {
  final entry = draftFixtureEntry();
  final book = entry.book;
  late Directory root;
  late TextbookCourseRepository repository;
  late TextbookCourseGenerationService service;
  late List<DraftFixtureSource> sources;
  late List<TextbookGenerationProgress> progress;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('poemath-generation-');
    repository = TextbookCourseRepository(directoryProvider: () async => root);
    sources = [];
    progress = [];
    service = TextbookCourseGenerationService(
      repository,
      TextbookFileService(directoryProvider: () async => root),
      openSource: ({
        required path,
        required book,
        required cache,
        required token,
      }) async {
        final source = DraftFixtureSource(token);
        sources.add(source);
        return source;
      },
    );
  });
  tearDown(() async => root.delete(recursive: true));
  Future<void> run({
    TextbookDraftToken? token,
    void Function()? changed,
    bool refresh = false,
    String? lessonId,
  }) =>
      service.run(
        book,
        entry,
        '/owned.pdf',
        token ?? TextbookDraftToken(),
        progress.add,
        changed ?? () {},
        refresh: refresh,
        lessonId: lessonId,
      );

  test('真实生成器逐课生成正文和Unicode背诵范围，整份检查点冷启动恢复', () async {
    await run();
    final document = (await repository.loadDocument(book))!;
    final first = document.pack.lessons.first;
    expect(first.paragraphs.single.text, '星𠀀，月。');
    expect(first.paragraphs.single.pinyin, isNull);
    expect(first.recitations.single.ranges.single.end, 5);
    expect(
      first.recitations.single.ranges.single.textSha256,
      textbookTextDigest('星𠀀，月。'),
    );
    expect(first.exercises.single.prompt, '朗读课文。背诵全文。');
    expect(first.exercises.single.answers, isEmpty);
    expect(first.coverage.values.toSet(), {TextbookCoverage.pending});
    expect(document.pack.lessons.last.paragraphs.single.text, '山河，星光。');
    expect(document.generation!.completed, ['auto-l-1', 'auto-l-2']);
    expect(document.generation!.phase, 'ready');
    expect(progress.last.done, 2);
    expect(sources.single.closed, isTrue);
    final reopened =
        TextbookCourseRepository(directoryProvider: () async => root);
    expect((await reopened.loadDocument(book))!.toJson(), document.toJson());
    expect(
      TextbookCoursePack.fromJson(document.pack.toJson()).toJson(),
      document.pack.toJson(),
    );
  });

  test('第一课安全保存后暂停，重启继续不重复追加或改动已完成目标', () async {
    final token = TextbookDraftToken();
    var changedCount = 0;
    await run(
      token: token,
      changed: () {
        if (++changedCount == 2) token.cancel();
      },
    );
    final paused = (await repository.loadDocument(book))!;
    expect(paused.generation!.phase, 'paused');
    expect(paused.generation!.completed, ['auto-l-1']);
    final saved = paused.pack.lessons.first.toJson();
    await run();
    final resumed = (await repository.loadDocument(book))!;
    expect(resumed.pack.lessons.first.toJson(), saved);
    expect(resumed.generation!.completed, ['auto-l-1', 'auto-l-2']);
    expect(sources.last.tocReads, 0);
    expect(sources.every((s) => s.closed), isTrue);
  });

  test('编辑和审核后的本课重试保留完整人工版本，差异需明确采纳', () async {
    await run();
    final previous = (await repository.load(book))!;
    final paragraph = previous.lessons.first.paragraphs.single;
    final edited =
        editTextbookCourseNode(previous, paragraph.id, {'text': '星𠀀，月亮。'});
    final reviewed = TextbookCoursePack.fromJson(
      reviewTextbookCourse(
        input: edited.toJson(),
        nodeId: paragraph.id,
        reviewer: '测试家长',
        decision: 'approved',
        checks: ['sourcePages', 'content', 'pinyin'],
        notes: '已核对自有原书',
        at: DateTime.utc(2026, 10, 24),
      ),
    );
    await repository.save(book, reviewed, previous: previous);
    await run(lessonId: previous.lessons.first.id);
    final retried = (await repository.loadDocument(book))!;
    expect(retried.pack.toJson(), reviewed.toJson());
    expect(retried.generation!.pending.keys, [previous.lessons.first.id]);
    await repository.resolveDifference(
      book,
      previous.lessons.first.id,
      accept: false,
      previous: reviewed,
    );
    expect((await repository.loadDocument(book))!.generation!.pending, isEmpty);
    expect((await repository.load(book))!.toJson(), reviewed.toJson());
  });

  test('移除误识别段落及其背诵后，全书重试不会复活', () async {
    await run();
    final previous = (await repository.load(book))!;
    final id = previous.lessons.first.paragraphs.single.id;
    final removed =
        removeTextbookCourseTarget(previous, id, removeReferences: true);
    await repository.save(book, removed, previous: previous);
    await run(refresh: true);
    final next = (await repository.loadDocument(book))!;
    expect(next.pack.lessons.first.paragraphs, isEmpty);
    expect(next.pack.lessons.first.recitations, isEmpty);
    expect(next.generation!.removed, contains(id));
    expect(next.generation!.errors, isEmpty);
  });

  test('人工范围和忽略候选跨全书刷新保留，课名修改不新增重复课目', () async {
    await run();
    var document = (await repository.loadDocument(book))!;
    final lesson = document.pack.lessons.first;
    final edited =
        editTextbookCourseNode(document.pack, lesson.id, {'title': '人工课名'});
    await repository.save(book, edited, previous: document.pack);
    await repository.updateGeneration(
      book,
      document.generation!.runId,
      (g) => g.copyWith(
        plans: [
          for (final p in g.plans)
            if (p.id == lesson.id)
              TextbookDraftPlan(
                id: p.id,
                startPage: 2,
                endPage: 2,
                title: '星月测试',
                edited: true,
              )
            else
              p,
        ],
        removed: ['candidate:${lesson.id}-page-2'],
      ),
    );
    await run(refresh: true);
    document = (await repository.loadDocument(book))!;
    expect(document.pack.lessons.length, 2);
    expect(document.pack.lessons.first.title, '人工课名');
    expect(document.generation!.plans.first.edited, isTrue);
    expect(document.generation!.plans.first.endPage, 2);
    final current = document.pack.lessons.first.toJson();
    await repository.commitGeneratedLesson(
      book,
      document.generation!.runId,
      current,
      [
        TextbookDraftCandidate(
          id: '${lesson.id}-page-2',
          text: '不再出现',
          reason: '已忽略',
          pages: [2],
        ),
      ],
      check: () {},
    );
    expect(
        (await repository.loadDocument(book))!
            .generation!
            .candidates[lesson.id],
        isEmpty,);
  });

  test('仅重试尚未完成的一课后仍报告暂停，不谎报整册完成', () async {
    final token = TextbookDraftToken();
    await run(token: token, changed: () => token.cancel());
    final seed = (await repository.loadDocument(book))!;
    expect(seed.generation!.completed, isEmpty);
    await run(lessonId: seed.pack.lessons.first.id);
    final document = (await repository.loadDocument(book))!;
    expect(document.generation!.completed, [seed.pack.lessons.first.id]);
    expect(document.generation!.phase, 'paused');
    expect(progress.last.phase, 'paused');
  });

  test('旧直接JSON转换前保留v1副本，人工导入课目不被自动结果替换', () async {
    await run();
    final previous = (await repository.load(book))!;
    await repository.importDraft(book, previous);
    await run();
    final next = (await repository.loadDocument(book))!;
    expect(next.pack.toJson(), previous.toJson());
    final backup =
        File('${root.path}/textbooks/courses/${book.pdfSha256}.json.v1.bak');
    expect(jsonDecode(await backup.readAsString()), previous.toJson());
  });

  test('旧ID的字词被删除后，新解析ID也不能把同一目标复活', () async {
    await run();
    final original = (await repository.load(book))!;
    final lesson = original.lessons.first;
    final legacy = addTextbookCourseTarget(
      original,
      lesson.id,
      'writingCharacters',
      id: 'legacy-writing-0',
      text: '星',
      pages: [2],
    );
    await repository.save(book, legacy, previous: original);
    final removed = removeTextbookCourseTarget(legacy, 'legacy-writing-0');
    await repository.save(book, removed, previous: legacy);
    final doc = (await repository.loadDocument(book))!;
    final proposed = lesson.toJson();
    proposed['writingCharacters'] = [
      {
        ...legacy.lessons.first.writingCharacters.single.toJson(),
        'id': 'new-stable-id',
      },
    ];
    final committed = await repository.commitGeneratedLesson(
      book,
      doc.generation!.runId,
      proposed,
      [],
      check: () {},
    );
    expect(committed.pack.lessons.first.writingCharacters, isEmpty);
    expect(
        committed.generation!.pending[lesson.id]?['writingCharacters'] ??
            <dynamic>[],
        isEmpty,);
  });

  test('同书并发启动共享打开过程，暂停等待关闭后才能再次运行', () async {
    final opened = Completer<void>();
    var opens = 0;
    final gated = TextbookCourseGenerationService(
      repository,
      TextbookFileService(directoryProvider: () async => root),
      openSource: ({
        required path,
        required book,
        required cache,
        required token,
      }) async {
        opens++;
        await opened.future;
        final source = DraftFixtureSource(token);
        sources.add(source);
        return source;
      },
    );
    final controller = TextbookGenerationController(gated, (_) {});
    final first = controller.start(book, entry, '/owned.pdf');
    final second = controller.start(book, entry, '/owned.pdf');
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(opens, 1);
    final stopped = controller.stop(book.pdfSha256);
    opened.complete();
    await stopped;
    expect(sources.single.closed, isTrue);
    expect(await repository.load(book), isNull);
    controller.dispose();
  });
}
