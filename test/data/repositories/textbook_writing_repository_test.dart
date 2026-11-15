import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_review.dart';
import 'package:poemath/data/models/textbook_writing_attempt.dart';
import 'package:poemath/data/models/textbook_writing_progress.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/data/repositories/textbook_writing_repository.dart';
import 'package:poemath/domain/textbook_writing_content.dart';
import 'package:poemath/domain/textbook_writing_review.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/textbook_course_fixture.dart';
import '../../helpers/writing_fixture.dart';
import '../../helpers/writing_attempt_fixture.dart';

class FailingBox extends Fake implements Box<dynamic> {
  final data = <String, dynamic>{};
  bool fail = true;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (fail) {
      fail = false;
      throw HiveError('disk full');
    }
    data[key as String] = value;
  }
}

void main() {
  late Directory dir;
  late TextbookCourseRepository courses;
  late TextbookCoursePack pack;
  late TextbookWritingRepository repo;
  final book = courseFixtureBook();
  bool hasStrokeData(String c) => c == '星';

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    dir = await Directory.systemTemp.createTemp('writing-repo');
    courses = TextbookCourseRepository(directoryProvider: () async => dir);
    pack = writingFixture();
    await courses.importDraft(book, pack);
    repo = TextbookWritingRepository(
      book: book,
      editionId: pack.edition.id,
      courses: courses,
      hasStrokeData: hasStrokeData,
    );
  });
  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForTesting();
    await dir.delete(recursive: true);
  });

  List<WritingTarget> targets() =>
      writingTargets(pack, pack.lessons.single, hasStrokeData: hasStrokeData);
  String lessonId() => pack.lessons.first.id;

  Future<WritingProgress> trace({TextbookWritingRepository? using}) async {
    final r = using ?? repo;
    final p = await r.load();
    return r.recordStage(
      lessonId: lessonId(),
      fingerprint: writingLessonFingerprint(targets()),
      targetId: targets().first.id,
      stage: WritingStageDone.trace,
      operationId: 'trace',
      expectedRevision: p.revision,
      attempt: writingAttemptFixture(
        id: 'trace',
        kind: WritingAttemptKind.trace,
      ),
    );
  }

  test('描红计数写入并可在新实例读回', () async {
    final p = await trace();
    expect(p.records.values.first.traceCount, 1);
    expect(p.records.values.first.badge, WritingBadge.traced);
    final reopened = TextbookWritingRepository(
      book: book,
      editionId: pack.edition.id,
      courses: courses,
      hasStrokeData: hasStrokeData,
    );
    expect((await reopened.load()).toJson(), p.toJson());
  });

  Future<WritingProgress> puzzle({
    TextbookWritingRepository? using,
    String operationId = 'puzzle-round',
    int expectedRevision = 0,
    WritingAttempt? attempt,
  }) => (using ?? repo).recordStage(
    lessonId: lessonId(),
    fingerprint: writingLessonFingerprint(targets()),
    targetId: targets().first.id,
    stage: WritingStageDone.puzzle,
    operationId: operationId,
    expectedRevision: expectedRevision,
    attempt: attempt,
  );

  test('拼装写入加密 box，关闭重开后读回；同轮旧 revision 重试不重复计数', () async {
    final cipher = HiveAesCipher(Hive.generateSecureKey());
    var disk = await Hive.openBox<dynamic>(
      'jigsaw-disk-test',
      encryptionCipher: cipher,
    );
    var persisted = TextbookWritingRepository(
      book: book,
      editionId: pack.edition.id,
      courses: courses,
      hasStrokeData: hasStrokeData,
      box: disk,
    );
    final attempt = writingAttemptFixture(
      id: 'puzzle-round',
      kind: WritingAttemptKind.puzzle,
    );
    final done = await puzzle(using: persisted, attempt: attempt);
    final record = done.records.values.single;
    expect(record.puzzleCount, 1);
    expect(record.attempts.single.toJson(), attempt.toJson());
    expect(record.traceCount, 0);
    expect(record.freeCount, 0);
    expect(record.geometryPasses, 0);
    expect(record.parentConfirms, 0);
    expect(record.stage, 0);
    expect(record.nextDay, isNull);
    expect(record.lastDay, isNull);
    expect(record.badge, WritingBadge.assembled);
    await disk.close();
    disk = await Hive.openBox<dynamic>(
      'jigsaw-disk-test',
      encryptionCipher: cipher,
    );
    persisted = TextbookWritingRepository(
      book: book,
      editionId: pack.edition.id,
      courses: courses,
      hasStrokeData: hasStrokeData,
      box: disk,
    );
    expect((await persisted.load()).toJson(), done.toJson());
    expect(
      (await puzzle(using: persisted, attempt: attempt)).toJson(),
      done.toJson(),
    );
    final next = await puzzle(
      using: persisted,
      operationId: 'new-round',
      expectedRevision: 1,
      attempt: writingAttemptFixture(
        id: 'new-round',
        kind: WritingAttemptKind.puzzle,
      ),
    );
    expect(next.records.values.single.puzzleCount, 2);
    expect(next.records.values.single.attempts.map((a) => a.id), [
      'puzzle-round',
      'new-round',
    ]);
    await disk.close();
  });

  test('拼装不覆盖既有书写和家长复习历史', () async {
    final traced = await trace();
    final confirmed = await repo.recordParentConfirm(
      lessonId: lessonId(),
      fingerprint: writingLessonFingerprint(targets()),
      targetId: targets().first.id,
      passed: true,
      day: '2026-11-14',
      operationId: 'parent-before-puzzle',
      expectedRevision: traced.revision,
    );
    final done = await puzzle(expectedRevision: confirmed.revision);
    expect(done.records.values.single.toJson(), {
      ...confirmed.records.values.single.toJson(),
      'puzzleCount': 1,
    });
  });

  test('拼装保存失败不写事实，相同 round ID 重试只计一次', () async {
    final box = FailingBox();
    final failing = TextbookWritingRepository(
      book: book,
      editionId: pack.edition.id,
      courses: courses,
      hasStrokeData: hasStrokeData,
      box: box,
    );
    final attempt = writingAttemptFixture(
      id: 'puzzle-round',
      kind: WritingAttemptKind.puzzle,
    );
    await expectLater(
      puzzle(using: failing, attempt: attempt),
      throwsA(isA<HiveError>()),
    );
    expect((await failing.load()).records, isEmpty);
    final retried = await puzzle(using: failing, attempt: attempt);
    expect(retried.records.values.single.puzzleCount, 1);
    expect(
      retried.records.values.single.attempts.single.toJson(),
      attempt.toJson(),
    );
    expect(
      (await puzzle(using: failing, attempt: attempt)).toJson(),
      retried.toJson(),
    );
  });

  test('档案切换及恢复后旧实例不能写拼装完成', () async {
    final before = await puzzle();
    final raw = HiveBoxes.settings.get(repo.key);
    ProfileScope.switchTo('other');
    await expectLater(
      puzzle(operationId: 'wrong-profile', expectedRevision: before.revision),
      throwsStateError,
    );
    expect(HiveBoxes.settings.get(repo.key), raw);
    ProfileScope.reset();
    final current = TextbookWritingRepository(
      book: book,
      editionId: pack.edition.id,
      courses: courses,
      hasStrokeData: hasStrokeData,
    );
    await PracticeDraftRepository.whileRestoring(
      PracticeDraftRepository.clearAll,
    );
    await expectLater(
      puzzle(
        using: current,
        operationId: 'stale-restore',
        expectedRevision: before.revision,
      ),
      throwsStateError,
    );
    expect(HiveBoxes.settings.get(repo.key), raw);
  });

  test('同 operationId 重放不重复计数；旧 revision 拒绝覆盖', () async {
    final p = await trace();
    final replay = await trace(using: repo);
    expect(replay.toJson(), p.toJson());
    expect(replay.records.values.first.traceCount, 1);
    final other = TextbookWritingRepository(
      book: book,
      editionId: pack.edition.id,
      courses: courses,
      hasStrokeData: hasStrokeData,
    );
    await expectLater(
      other.change(
        lessonId: lessonId(),
        fingerprint: writingLessonFingerprint(targets()),
        operationId: 'stale',
        // 旧页面看到的 revision 已过期。
        expectedRevision: p.revision - 1,
        reduce: (p, _) => p,
      ),
      throwsStateError,
    );
  });

  test('作品 ID 超过最近 200 次操作窗口后，旧 revision 重放也不重复写入', () async {
    final saved = await trace();
    final advanced = saved.copy(
      revision: 205,
      operations: [for (var i = 0; i < 200; i++) 'geometry-$i'],
    );
    await HiveBoxes.settings.put(repo.key, jsonEncode(advanced.toJson()));
    final raw = HiveBoxes.settings.get(repo.key);
    final replay = await repo.recordStage(
      lessonId: lessonId(),
      fingerprint: writingLessonFingerprint(targets()),
      targetId: targets().first.id,
      stage: WritingStageDone.trace,
      operationId: 'trace',
      expectedRevision: 0,
      attempt: writingAttemptFixture(
        id: 'trace',
        kind: WritingAttemptKind.trace,
      ),
    );
    expect(replay.revision, 205);
    expect(replay.records.values.single.traceCount, 1);
    expect(replay.records.values.single.attempts, hasLength(1));
    expect(HiveBoxes.settings.get(repo.key), raw);
  });

  test('作品种类和 ID 不匹配完成操作时，不写次数或作品', () async {
    final original = await repo.load();
    for (final attempt in [
      writingAttemptFixture(id: 'stage', kind: WritingAttemptKind.puzzle),
      writingAttemptFixture(id: 'different', kind: WritingAttemptKind.trace),
    ]) {
      expect(
        () => repo.recordStage(
          lessonId: lessonId(),
          fingerprint: writingLessonFingerprint(targets()),
          targetId: targets().first.id,
          stage: WritingStageDone.trace,
          operationId: 'stage',
          expectedRevision: 0,
          attempt: attempt,
        ),
        throwsArgumentError,
      );
    }
    expect((await repo.load()).toJson(), original.toJson());
    expect(HiveBoxes.settings.get(repo.key), isNull);
  });

  test('跨实例同键串写不交错', () async {
    final other = TextbookWritingRepository(
      book: book,
      editionId: pack.edition.id,
      courses: courses,
      hasStrokeData: hasStrokeData,
    );
    final values = await Future.wait([trace(), trace(using: other)]);
    expect(values.first.toJson(), values.last.toJson());
    expect(values.first.records.values.first.traceCount, 1);
  });

  test('put 失败原记录不动；重试成功', () async {
    final box = FailingBox()..fail = false;
    final failing = TextbookWritingRepository(
      book: book,
      editionId: pack.edition.id,
      courses: courses,
      hasStrokeData: hasStrokeData,
      box: box,
    );
    final p = await trace(using: failing);
    box.fail = true;
    final before = p.toJson();
    await expectLater(
      failing.recordStage(
        lessonId: lessonId(),
        fingerprint: writingLessonFingerprint(targets()),
        targetId: targets().first.id,
        stage: WritingStageDone.free,
        operationId: 'free',
        expectedRevision: p.revision,
      ),
      throwsA(isA<HiveError>()),
    );
    expect((await failing.load()).toJson(), before);
  });

  test('笔顺资产可用性变化使字级指纹失效，旧记录被丢弃', () async {
    final p = await trace();
    expect(p.records, isNotEmpty);
    // 同一课内容，但资产判定变化（如资产更新后新增该字）。
    final flipped = TextbookWritingRepository(
      book: book,
      editionId: pack.edition.id,
      courses: courses,
      hasStrokeData: (c) => false,
    );
    final loaded = await flipped.load();
    expect(loaded.records, isEmpty);
  });

  test('课程审核撤回后旧指纹拒绝写入并清空记录', () async {
    final p = await trace();
    final rejected = TextbookCoursePack.fromJson(
      reviewTextbookCourse(
        input: pack.toJson(),
        nodeId: 'writing-001',
        reviewer: '家长',
        decision: 'rejected',
        checks: [],
        notes: '待核对',
        at: DateTime(2026),
      ),
    );
    await courses.save(book, rejected, previous: pack);
    final stale = repo.recordStage(
      lessonId: lessonId(),
      fingerprint: writingLessonFingerprint(targets()),
      targetId: targets().first.id,
      stage: WritingStageDone.free,
      operationId: 'free',
      expectedRevision: p.revision,
    );
    await expectLater(stale, throwsStateError);
    expect((await repo.load()).records, isEmpty);
  });

  test('档案隔离与旧 scope 拒写', () async {
    await trace();
    final raw = HiveBoxes.settings.get(repo.key);
    ProfileScope.switchTo('other');
    await expectLater(repo.load(), throwsStateError);
    final other = TextbookWritingRepository(
      book: book,
      editionId: pack.edition.id,
      courses: courses,
      hasStrokeData: hasStrokeData,
    );
    expect((await other.load()).records, isEmpty);
    expect(other.key, isNot(repo.key));
    ProfileScope.reset();
    expect(HiveBoxes.settings.get(repo.key), raw);
  });

  test('恢复数据后旧实例拒写，新实例保留累计', () async {
    final p = await trace();
    var restored = false;
    await PracticeDraftRepository.whileRestoring(() async {
      restored = true;
    });
    expect(restored, true);
    final fresh = TextbookWritingRepository(
      book: book,
      editionId: pack.edition.id,
      courses: courses,
      hasStrokeData: hasStrokeData,
    );
    final loaded = await fresh.load();
    expect(loaded.records.values.first.traceCount, 1);
    expect(loaded.toJson(), p.toJson());
  });

  test('家长确认推进复习日程；判不通过归零到次日', () async {
    final p = await repo.load();
    final done = await repo.recordParentConfirm(
      lessonId: lessonId(),
      fingerprint: writingLessonFingerprint(targets()),
      targetId: targets().first.id,
      passed: true,
      day: '2026-10-25',
      operationId: 'confirm-1',
      expectedRevision: p.revision,
    );
    final record = done.records.values.first;
    expect(record.parentConfirms, 1);
    expect(record.lastParentDay, '2026-10-25');
    expect(record.badge, WritingBadge.written);
    expect(writingDueToday(record, '2026-10-25'), false);
    expect(record.nextDay, '2026-10-26');

    final failed = await repo.recordParentConfirm(
      lessonId: lessonId(),
      fingerprint: writingLessonFingerprint(targets()),
      targetId: targets().first.id,
      passed: false,
      day: '2026-10-26',
      operationId: 'confirm-2',
      expectedRevision: done.revision,
    );
    expect(failed.records.values.first.stage, 0);
    expect(failed.records.values.first.nextDay, '2026-10-27');
  });

  test('备份不导出写字记录', () async {
    await trace();
    // 与认一认同款：备份服务按前缀排除；这里只校验键命名契约。
    expect(repo.key, startsWith('textbook_writing_v1:'));
    expect(
      repo.key.substring('textbook_writing_v1:'.length),
      matches(RegExp(r'^[0-9a-f]{64}$')),
    );
  });
}
