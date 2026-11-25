import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/english_recording_store.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/english_progress.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/repositories/english_progress_repository.dart';
import 'package:poemath/data/repositories/english_course_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/domain/english_practice.dart';

import '../../../helpers/english_fixture.dart';
import '../../../helpers/english_phrase_fixture.dart';
import '../../../helpers/hive_test_helper.dart';
import '../../../helpers/parent_access_test_helper.dart';

class _FailingProblems extends Mock implements Box<LlmProblem> {}

void main() {
  late Directory root;
  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
    root = await Directory.systemTemp.createTemp('english-storage-');
  });
  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForTesting();
    await root.delete(recursive: true);
  });
  test('拓展短语答题快照及复习记录真实备份往返，课程仍保存在本机', () async {
    final book = englishBook(), course = withPhrases(phraseCourse());
    final courses = EnglishCourseRepository(
      directoryProvider: () async => root,
    );
    await courses.seed(book, course, check: () {});
    final progress = EnglishProgressRepository(book, courses);
    final question = buildEnglishQuestions(
      course,
      EnglishPracticeKind.spelling,
    ).firstWhere((q) => q.target.isAiPhrase);
    await progress.complete(
      EnglishAttempt(
        id: 'generated-phrase',
        lessonId: question.lessonId,
        title: '短语拼写',
        kind: 'practice',
        completedAt: DateTime(2026, 11, 25),
        durationSeconds: 10,
        answers: [
          EnglishAnswer(
            question: question,
            answer: question.answers.single,
            correct: true,
          ),
        ],
      ),
    );
    final original = progress.load().toJson(portable: true);
    final backup = BackupService(), raw = await BackupService().exportToJson();
    backup.inspectJson(raw);
    await HiveBoxes.settings.delete(progress.key);
    await backup.restoreFromJson(raw);
    expect(
      EnglishProgressRepository(book, courses).load().toJson(portable: true),
      original,
    );
    expect((await courses.load(book))!.toJson(), course.toJson());
    expect((jsonDecode(raw) as Map).containsKey('englishCourses'), isFalse);
  });
  test('录音写为 PCM16 WAV，重启可读，权限失效无半成品，不接受路径标识', () async {
    final store = EnglishRecordingStore(directory: () async => root),
        pcm = Uint8List.fromList(List.generate(3200, (i) => i % 256));
    await store.save('child', 'recording-a', pcm, () {});
    final path = await EnglishRecordingStore(directory: () async => root)
        .path('child', 'recording-a');
    final bytes = await File(path!).readAsBytes();
    expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
    expect(ascii.decode(bytes.sublist(8, 12)), 'WAVE');
    final header = ByteData.sublistView(bytes);
    expect(header.getUint32(24, Endian.little), 16000);
    expect(header.getUint32(40, Endian.little), pcm.length);
    expect(bytes.sublist(44), pcm);
    expect(await store.path('other', 'recording-a'), isNull);
    await expectLater(
      store.save('child', '../bad', pcm, () {}),
      throwsFormatException,
    );
    var checks = 0;
    await expectLater(
      store.save('child', 'cancelled', pcm, () {
        if (++checks >= 3) throw StateError('locked');
      }),
      throwsStateError,
    );
    expect(await store.path('child', 'cancelled'), isNull);
    expect(
      (await root.list(recursive: true).toList()).where(
        (e) => e.path.endsWith('.pending'),
      ),
      isEmpty,
    );
  });
  test('真实备份含文字和复习，不含录音 ID/path；旧备份保留英语进度', () async {
    final book = englishBook(),
        progress = EnglishProgress(
          profileId: 'default',
          bookId: englishBook().pdfSha256,
          editionId: englishBook().learningEditionId,
          attempts: [
            EnglishAttempt(
              id: 'session-a',
              lessonId: 'unit-1-p2',
              title: '英语跟读',
              kind: 'speaking',
              completedAt: DateTime(2026, 11, 23),
              durationSeconds: 10,
              spokenTexts: ['A blue bird.'],
              recordingIds: ['local-recording-secret'],
            ),
          ],
        );
    final key =
        '${EnglishProgress.prefix}${textbookTextDigest(jsonEncode(['default', book.pdfSha256, book.learningEditionId]))}';
    await HiveBoxes.settings.put(key, jsonEncode(progress.toJson()));
    final backup = BackupService(),
        raw = await backup.exportToJson(),
        decoded = jsonDecode(
          await BackupService().exportToJson(),
        ) as Map<String, dynamic>;
    expect(raw, contains('A blue bird.'));
    expect(raw, isNot(contains('local-recording-secret')));
    backup.inspectJson(raw);
    await backup.restoreFromJson(raw);
    expect(
      EnglishProgress.fromJson(
        jsonDecode(HiveBoxes.settings.get(key) as String),
      ).attempts.single.recordingIds,
      ['local-recording-secret'],
    );
    final originalProblems = HiveBoxes.llmProblems,
        failingProblems = _FailingProblems();
    var calls = 0;
    when(() => failingProblems.values).thenReturn([]);
    when(() => failingProblems.clear()).thenAnswer((_) async {
      if (++calls == 1) throw StateError('late write failed');
      return 0;
    });
    HiveBoxes.llmProblems = failingProblems;
    try {
      final empty = {...decoded, 'textbookLearning': <String, dynamic>{}};
      await expectLater(
        backup.restoreFromJson(jsonEncode(empty)),
        throwsStateError,
      );
      expect(
        jsonDecode(HiveBoxes.settings.get(key) as String),
        progress.toJson(),
      );
    } finally {
      HiveBoxes.llmProblems = originalProblems;
    }
    final old = {...decoded}..remove('englishProgressVersion');
    old['textbookLearning'] = <String, dynamic>{};
    await backup.restoreFromJson(jsonEncode(old));
    expect(
      jsonDecode(HiveBoxes.settings.get(key) as String),
      progress.toJson(),
    );
    await HiveBoxes.settings.delete(key);
    await backup.restoreFromJson(raw);
    final restored = EnglishProgress.fromJson(
      jsonDecode(HiveBoxes.settings.get(key) as String),
    );
    expect(restored.attempts.single.spokenTexts, ['A blue bird.']);
    expect(restored.attempts.single.recordingIds, isEmpty);
    expect(
      EnglishProgressRepository.savedForProfile()
          .single
          .attempts
          .single
          .spokenTexts,
      ['A blue bird.'],
    );
    final malicious = {
      ...progress.toJson(portable: true),
      'audioPath': '/tmp/private.wav',
    };
    final payload = {
      ...decoded,
      'textbookLearning': {key: jsonEncode(malicious)},
    };
    expect(
      () => backup.inspectJson(jsonEncode(payload)),
      throwsFormatException,
    );
    payload['textbookLearning'] = {key: jsonEncode(progress.toJson())};
    expect(
      () => backup.inspectJson(jsonEncode(payload)),
      throwsFormatException,
    );
  });
  test('删书只删除对应书本录音并撤销存活英语草稿写入', () async {
    final store = EnglishRecordingStore(directory: () async => root),
        book = englishBook();
    final other = 'b' * 64, pcm = Uint8List(3200);
    await store.save('child', 'same', pcm, () {}, bookId: book.pdfSha256);
    await store.save('other-child', 'same', pcm, () {}, bookId: book.pdfSha256);
    await store.save('child', 'same', pcm, () {}, bookId: other);
    await store.deleteBook(book.pdfSha256, () {});
    expect(await store.path('child', 'same', bookId: book.pdfSha256), isNull);
    expect(
      await store.path('other-child', 'same', bookId: book.pdfSha256),
      isNull,
    );
    expect(await store.path('child', 'same', bookId: other), isNotNull);
    final draft = PracticeDraftRepository(), scope = '${book.pdfSha256}/lesson';
    draft.claim('englishSpeaking', scope: scope);
    await draft.save('englishSpeaking', {'sessionId': 's'}, scope: scope);
    await PracticeDraftRepository.deleteEnglishBookDrafts(
      book.pdfSha256,
      box: HiveBoxes.meta,
    );
    expect(draft.get('englishSpeaking', scope: scope), isNull);
    await expectLater(
      draft.save('englishSpeaking', {'sessionId': 's'}, scope: scope),
      throwsStateError,
    );
  });
}
