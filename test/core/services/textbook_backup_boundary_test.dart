import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import '../../helpers/hive_test_helper.dart';
import '../../helpers/textbook_fixture.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);
  test('实际备份导出不包含教材，恢复保留本机书目阅读状态和学习背景', () async {
    final repo = TextbookRepository();
    final book = textbookFixture();
    await HiveBoxes.settings
        .putAll({'selected_grade': 6, 'selected_semester': '下'});
    await repo.addIfAbsent(book);
    await repo.savePage('child', book, 2);
    await repo.setMatch('child', book.pdfSha256, TextbookMatch.matches);
    final backup = BackupService();
    final exported = await backup.exportToJson();
    final json = jsonDecode(exported) as Map<String, dynamic>;
    final settings = json['settings'] as Map<String, dynamic>;
    expect(settings.keys.where((key) => key.startsWith('textbook_')), isEmpty);
    expect(exported.contains(book.pdfSha256), isFalse);
    await backup.restoreFromJson(exported);
    expect(repo.find(book.pdfSha256)!.toJson(), book.toJson());
    expect(repo.reading('child', book.pdfSha256).toJson(),
        {'page': 2, 'match': 'matches'},);
    expect(HiveBoxes.settings.get('selected_grade'), 6);
    expect(HiveBoxes.settings.get('selected_semester'), '下');
  });
}
