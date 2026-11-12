import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_exercise_progress.dart';
import 'package:poemath/data/models/textbook_recognition_progress.dart';
import 'package:poemath/data/models/textbook_writing_progress.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/data/repositories/textbook_download_repository.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';
import '../../helpers/textbook_fixture.dart';

void main() {
  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
  });
  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForTesting();
  });
  test('教材学习进度随备份迁移，PDF、书目登记和下载状态留在本机', () async {
    final repo = TextbookRepository();
    final book = textbookFixture();
    await HiveBoxes.settings.putAll({
      'selected_grade': 6,
      'selected_semester': '下',
    });
    await repo.addIfAbsent(book);
    await repo.savePage('child', book, 2);
    await repo.markOpened('child', book.pdfSha256);
    await repo.setMatch('child', book.pdfSha256, TextbookMatch.matches);
    await TextbookDownloadRepository().markPending(book.pdfSha256);
    final editionId = 'edition-1';
    final recognition = RecognitionProgress(
      profileId: 'child',
      bookId: book.pdfSha256,
      editionId: editionId,
    );
    final writing = WritingProgress(
      profileId: 'child',
      bookId: book.pdfSha256,
      editionId: editionId,
    );
    final exercise = TextbookExerciseProgress(
      profileId: 'child',
      bookId: book.pdfSha256,
      editionId: editionId,
    );
    final recognitionKey =
        'textbook_recognition_v1:${textbookTextDigest(jsonEncode(['child', book.pdfSha256, editionId]))}';
    final writingKey =
        'textbook_writing_v1:${textbookTextDigest(jsonEncode(['child', book.pdfSha256, editionId]))}';
    final exerciseKey =
        'textbook_exercise_v1:${textbookTextDigest(jsonEncode(['child', book.pdfSha256, editionId]))}';
    await HiveBoxes.settings.putAll({
      recognitionKey: jsonEncode(recognition.toJson()),
      writingKey: jsonEncode(writing.toJson()),
      exerciseKey: jsonEncode(exercise.toJson()),
      'theme_mode': 'dark',
    });
    final backup = BackupService();
    final exported = await backup.exportToJson();
    final json = jsonDecode(exported) as Map<String, dynamic>;
    final settings = json['settings'] as Map<String, dynamic>;
    expect(settings.keys.where((key) => key.startsWith('textbook_')), isEmpty);
    expect(json['textbookLearning'], isA<Map<String, dynamic>>());
    expect(backup.inspectJson(exported).counts['教材学习进度'], 4);
    expect(exported, contains(book.pdfSha256));
    expect(exported, isNot(contains(book.originalFileName)));

    await repo.savePage('child', book, 4);
    await HiveBoxes.settings.deleteAll([
      'textbook_reading_v1:${Uri.encodeComponent('child')}:${book.pdfSha256}',
      recognitionKey,
      writingKey,
      exerciseKey,
    ]);
    await backup.restoreFromJson(exported);
    expect(repo.find(book.pdfSha256)!.toJson(), book.toJson());
    expect(repo.recentBook('child')!.pdfSha256, book.pdfSha256);
    expect(repo.reading('child', book.pdfSha256).toJson(), {
      'page': 2,
      'match': 'matches',
    });
    expect(HiveBoxes.settings.get('selected_grade'), 6);
    expect(HiveBoxes.settings.get('selected_semester'), '下');
    expect(
      HiveBoxes.settings.get(recognitionKey),
      jsonEncode(recognition.toJson()),
    );
    expect(HiveBoxes.settings.get(writingKey), jsonEncode(writing.toJson()));
    expect(HiveBoxes.settings.get(exerciseKey), jsonEncode(exercise.toJson()));
    expect(TextbookDownloadRepository().pendingIds(), {book.pdfSha256});

    await repo.savePage('child', book, 4);
    final legacy = Map<String, dynamic>.from(json)
      ..remove('textbookLearning')
      ..remove('pictureStoryPractice');
    await backup.restoreFromJson(jsonEncode(legacy));
    expect(repo.reading('child', book.pdfSha256).page, 3);
    expect(
      HiveBoxes.settings.get(recognitionKey),
      jsonEncode(recognition.toJson()),
    );
  });
}
