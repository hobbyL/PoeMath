import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/math_textbook_practice_cache.dart';
import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/domain/math_textbook_practice.dart';

import '../../helpers/math_textbook_fixture.dart';
import '../../helpers/math_textbook_learning_fixture.dart';

void main() {
  final book = mathTextbookFixture();
  final lesson = mathLearningFixture();
  final plan = lesson.learning!.practicePlans.single;
  late Directory root;
  late TextbookFileService files;
  var generations = 0;

  TextbookContentCache reopen() =>
      TextbookContentCache(book: book, directoryProvider: () async => root);
  Future<List<File>> cachedFiles() => root
      .list(recursive: true)
      .where((f) => f is File && f.path.contains('math-data-'))
      .cast<File>()
      .toList();
  List<Map<String, dynamic>> json(MathTextbookPreparedPractice value) =>
      value.items.map((item) => item.toJson()).toList();

  Future<MathTextbookPreparedPractice> prepare({
    TextbookContentCache? cache,
    MathTextbookPracticePlan? selectedPlan,
    int? seed,
  }) => prepareMathTextbookPractice(
    cache: cache ?? reopen(),
    book: book,
    lesson: lesson,
    plan: selectedPlan,
    seed: seed,
    generate: (seed) {
      generations++;
      return selectedPlan == null
          ? originalMathTextbookItems(lesson)
          : generateMathTextbookPractice(
              lesson: lesson,
              plan: selectedPlan,
              grade: book.grade,
              semester: book.semester,
              random: Random(seed!),
            );
    },
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('math-practice-cache-');
    files = TextbookFileService(directoryProvider: () async => root);
    generations = 0;
  });
  tearDown(() => root.delete(recursive: true));

  test('原题与巩固题首次生成，重建缓存实例后直接读取同一内容和种子', () async {
    final originals = await prepare();
    final practice = await prepare(selectedPlan: plan);
    expect(generations, 2);
    final saved = {
      for (final file in await cachedFiles())
        file.path: await file.lastModified(),
    };
    expect(saved.length, 3);
    for (var i = 0; i < 3; i++) {
      expect(json(await prepare()), json(originals));
      final again = await prepare(selectedPlan: plan);
      expect(again.seed, practice.seed);
      expect(json(again), json(practice));
    }
    expect(generations, 2);
    for (final file in await cachedFiles()) {
      expect(
        file.parent.path,
        '${root.path}/textbooks/cache/${book.pdfSha256}',
      );
      expect(await file.lastModified(), saved[file.path]);
    }
  });

  test('同一题组的并发首次读取只生成一次，旧草稿种子不覆盖默认题组', () async {
    final cache = files.contentCache(book);
    final parallel = await Future.wait([
      prepare(cache: cache, selectedPlan: plan),
      prepare(cache: cache, selectedPlan: plan),
    ]);
    expect(generations, 1);
    expect(json(parallel.first), json(parallel.last));
    final legacySeed = (parallel.first.seed! + 1) % 2147483647;
    final legacy = await prepare(selectedPlan: plan, seed: legacySeed);
    expect(generations, 2);
    expect(
      json(await prepare(selectedPlan: plan, seed: legacySeed)),
      json(legacy),
    );
    final current = await prepare(selectedPlan: plan);
    expect(current.seed, parallel.first.seed);
    expect(json(current), json(parallel.first));
    expect(generations, 2);
  });

  test('手动清理移除题目缓存，下次才重新生成；修改计划使用独立缓存', () async {
    final cache = files.contentCache(book);
    await prepare(cache: cache, selectedPlan: plan);
    await prepare(cache: cache, selectedPlan: plan);
    expect(generations, 1);
    final changed = MathTextbookPracticePlan.fromJson({
      ...plan.toJson(),
      'count': 3,
    });
    expect(
      (await prepare(cache: cache, selectedPlan: changed)).items.length,
      3,
    );
    expect(generations, 2);
    await files.clearExtractedContent(book);
    expect(await cachedFiles(), isEmpty);
    await prepare(cache: cache, selectedPlan: plan);
    expect(generations, 3);
  });

  test('缓存题目被修改或文件损坏时从课程重建，不把损坏答案作为校验依据', () async {
    final original = await prepare();
    final file = (await cachedFiles()).single;
    final envelope =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final data = envelope['data'] as Map<String, dynamic>;
    final items = data['data'] as List<dynamic>;
    final first = items.first as Map<String, dynamic>;
    final exercise = first['exercise'] as Map<String, dynamic>;
    exercise['title'] = '被修改的题目';
    await file.writeAsString(jsonEncode(envelope));
    expect(json(await prepare()), json(original));
    expect(generations, 2);
    await file.writeAsString('{invalid');
    expect(json(await prepare()), json(original));
    expect(generations, 3);
  });

  test('清理期间旧生成结果不能回写，新请求不复用在途旧结果', () async {
    final cache = files.contentCache(book);
    final started = Completer<void>();
    final pending = Completer<int>();
    final key = 'b' * 64;
    final old = cache.mathData<int>(
      key,
      decode: (value) => value! as int,
      encode: (value) => value,
      load: () {
        started.complete();
        return pending.future;
      },
    );
    final failure = expectLater(old, throwsStateError);
    await started.future;
    await files.clearExtractedContent(book);
    expect(await cachedFiles(), isEmpty);
    expect(
      await cache.mathData<int>(
        key,
        decode: (value) => value! as int,
        encode: (value) => value,
        load: () async => 2,
      ),
      2,
    );
    pending.complete(1);
    await failure;
    expect(
      await reopen().mathData<int>(
        key,
        decode: (value) => value! as int,
        encode: (value) => value,
        load: () => throw StateError('不应重新生成'),
      ),
      2,
    );
  });

  test('生成失败不缓存，缓存写入失败仍返回可用题目', () async {
    final cache = files.contentCache(book);
    await expectLater(
      prepareMathTextbookPractice(
        cache: cache,
        book: book,
        lesson: lesson,
        generate: (_) => throw StateError('生成失败'),
      ),
      throwsStateError,
    );
    expect(await cachedFiles(), isEmpty);
    final blocker = await File('${root.path}/blocked').writeAsString('file');
    final unavailable = TextbookContentCache(
      book: book,
      directoryProvider: () async => Directory(blocker.path),
    );
    expect((await prepare(cache: unavailable)).items, hasLength(1));
  });
}
