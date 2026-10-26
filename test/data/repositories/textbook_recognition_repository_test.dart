import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_review.dart';
import 'package:poemath/data/models/textbook_recognition_progress.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/data/repositories/textbook_recognition_repository.dart';
import 'package:poemath/domain/textbook_recognition_content.dart';
import 'package:poemath/domain/textbook_recognition_session.dart';
import '../../helpers/hive_test_helper.dart';
import '../../helpers/recognition_fixture.dart';
import '../../helpers/textbook_course_fixture.dart';

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
  late TextbookRecognitionRepository repo;
  final book = courseFixtureBook();
  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    dir = await Directory.systemTemp.createTemp('recognition-repo');
    courses = TextbookCourseRepository(directoryProvider: () async => dir);
    pack = recognitionFixture();
    await courses.importDraft(book, pack);
    repo = TextbookRecognitionRepository(
        book: book, editionId: pack.edition.id, courses: courses,);
  });
  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForTesting();
    await dir.delete(recursive: true);
  });
  Future<RecognitionProgress> start(
      {TextbookRecognitionRepository? using,}) async {
    final r = using ?? repo;
    final p = await r.load();
    final targets = recognitionTargets(pack, pack.lessons.single);
    final s = buildRecognitionSession(
      progress: p,
      lessonId: pack.lessons.single.id,
      targets: targets,
      id: 'round',
      now: DateTime(2026, 10, 25),
      epoch: r.epoch,
    )!;
    return r.change(
      lessonId: pack.lessons.single.id,
      fingerprint: recognitionLessonFingerprint(targets),
      operationId: 'start',
      expectedRevision: p.revision,
      reduce: (p, _) => p.copy(session: s),
    );
  }

  Future<RecognitionProgress> answer(RecognitionProgress p,
          {TextbookRecognitionRepository? using,}) =>
      (using ?? repo).change(
        lessonId: pack.lessons.single.id,
        fingerprint: p.session!.fingerprint,
        operationId: 'answer',
        expectedRevision: p.revision,
        sessionId: p.session!.id,
        reduce: (latest, targets) => answerRecognition(
            latest, targets, RecognitionEvidence.study, DateTime(2026, 10, 25),),
      );
  test('真实Hive关闭重开恢复完整题组及反馈；重放同操作不重复记数', () async {
    final p = await answer(await start());
    await HiveBoxes.close();
    await HiveBoxes.init();
    final reopened = TextbookRecognitionRepository(
        book: book, editionId: pack.edition.id, courses: courses,);
    expect((await reopened.load()).toJson(), p.toJson());
    final replay = await answer(p, using: reopened);
    expect(replay.toJson(), p.toJson());
    expect(replay.records.values.single.studies, 1);
  });
  test('跨仓库实例同键串写；不同操作的旧revision拒绝覆盖', () async {
    final p = await start();
    final other = TextbookRecognitionRepository(
        book: book, editionId: pack.edition.id, courses: courses,);
    final values = await Future.wait([answer(p), answer(p, using: other)]);
    expect(values.first.toJson(), values.last.toJson());
    await expectLater(
      repo.change(
        lessonId: pack.lessons.single.id,
        fingerprint: p.session!.fingerprint,
        operationId: 'stale',
        expectedRevision: p.revision,
        sessionId: 'round',
        reduce: (p, _) => p,
      ),
      throwsStateError,
    );
  });
  test('put失败原轮次不动；同一操作/时间重试只算一次', () async {
    final box = FailingBox();
    box.fail = false;
    final failing = TextbookRecognitionRepository(
        book: book, editionId: pack.edition.id, courses: courses, box: box,);
    final p = await start(using: failing);
    box.fail = true;
    await expectLater(answer(p, using: failing), throwsA(isA<HiveError>()));
    expect((await failing.load()).toJson(), p.toJson());
    final next = await answer(p, using: failing);
    expect(next.records.values.single.studies, 1);
    expect((await answer(p, using: failing)).toJson(), next.toJson());
  });
  test('审核撤回先完成，旧页面提交拒绝；与写入共用课程队列', () async {
    final p = await start();
    final next = TextbookCoursePack.fromJson(
      reviewTextbookCourse(
        input: pack.toJson(),
        nodeId: 'recognition-001',
        reviewer: '家长',
        decision: 'rejected',
        checks: [],
        notes: '待核对',
        at: DateTime(2026),
      ),
    );
    final saved = courses.save(book, next, previous: pack);
    final old = answer(p);
    await saved;
    await expectLater(old, throwsStateError);
    expect((await repo.load()).session, isNull);
  });
  test('restore等待排队guard；旧代次拒写，重进保留累计但不继续旧会话', () async {
    final p = await answer(await start());
    final entered = Completer<void>(), release = Completer<void>();
    final holding = courses.withCurrentPack(book, (_) async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final queued = repo.load();
    final rejected = expectLater(queued, throwsStateError);
    var restored = false;
    final restore = PracticeDraftRepository.whileRestoring(() async {
      await PracticeDraftRepository.clearAll();
      restored = true;
    });
    await Future<void>.value();
    expect(restored, false);
    release.complete();
    await holding;
    await rejected;
    await restore;
    await expectLater(repo.load(), throwsStateError);
    final fresh = TextbookRecognitionRepository(
        book: book, editionId: pack.edition.id, courses: courses,);
    final loaded = await fresh.load();
    expect(loaded.session, isNull);
    expect(loaded.records.values.single.studies, 1);
    expect(HiveBoxes.settings.get(repo.key), jsonEncode(p.toJson()));
  });
  test('档案隔离及旧scope拒写；备份不导出/注入本机记录', () async {
    final p = await answer(await start());
    final raw = HiveBoxes.settings.get(repo.key);
    ProfileScope.switchTo('other');
    await expectLater(repo.load(), throwsStateError);
    final other = TextbookRecognitionRepository(
        book: book, editionId: pack.edition.id, courses: courses,);
    expect((await other.load()).records, isEmpty);
    expect(other.key, isNot(repo.key));
    ProfileScope.reset();
    final backup = BackupService();
    final exported = await backup.exportToJson();
    expect(exported.contains('textbook_recognition_v1:'), false);
    final injected = jsonDecode(exported) as Map<String, dynamic>;
    (injected['settings'] as Map)[repo.key] = 'injected';
    await backup.restoreFromJson(jsonEncode(injected));
    expect(HiveBoxes.settings.get(repo.key), raw);
    final fresh = TextbookRecognitionRepository(
        book: book, editionId: pack.edition.id, courses: courses,);
    expect((await fresh.load()).records.values.single.toJson(),
        p.records.values.single.toJson(),);
  });
}
