import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:poemath/data/repositories/textbook_progress_cleanup.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late TextbookProgressCleanup cleanup;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('textbook_progress_');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('progress');
    cleanup = TextbookProgressCleanup(box: box);
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  String digestKey(String prefix, List<String> parts) =>
      '$prefix:${base64Encode(utf8.encode(jsonEncode(parts)))}';

  test('按 bookId 删除认一认与写一写两个前缀的进度键', () async {
    final sha = 'a' * 64;
    final other = List.filled(64, 'b').join();
    final recognitionKey = digestKey('textbook_recognition_v1', [
      'child',
      sha,
      'edition-1',
    ]);
    final writingKey = digestKey('textbook_writing_v1', ['child', sha, 'e1']);
    final otherKey = digestKey('textbook_recognition_v1', [
      'child',
      other,
      'edition-1',
    ]);
    box.put(recognitionKey, jsonEncode({
      'v': 1,
      'profileId': 'child',
      'bookId': sha,
      'editionId': 'edition-1',
      'revision': 0,
      'records': <String, dynamic>{},
      'audio': <String, dynamic>{},
      'operations': <String>[],
    }),);
    box.put(writingKey, jsonEncode({
      'v': 1,
      'profileId': 'child',
      'bookId': sha,
      'editionId': 'e1',
      'revision': 0,
      'records': <String, dynamic>{},
      'operations': <String>[],
    }),);
    box.put(otherKey, jsonEncode({
      'v': 1,
      'profileId': 'child',
      'bookId': other,
      'editionId': 'edition-1',
      'revision': 0,
      'records': <String, dynamic>{},
      'audio': <String, dynamic>{},
      'operations': <String>[],
    }),);
    // 无关键不动。
    box.put('poem_progress:1', 'whatever');

    final removed = await cleanup.deleteBookProgress(sha);

    expect(removed, 2);
    expect(box.get(recognitionKey), isNull);
    expect(box.get(writingKey), isNull);
    expect(box.get(otherKey), isNotNull, reason: '其他书的进度不受影响');
    expect(box.get('poem_progress:1'), 'whatever');
  });

  test('坏 JSON 与缺失 bookId 的键跳过不删', () async {
    final sha = 'c' * 64;
    final badKey = 'textbook_recognition_v1:digest-bad';
    final missingKey = 'textbook_writing_v1:digest-missing';
    box.put(badKey, '{not json');
    box.put(missingKey, jsonEncode({
      'v': 1,
      'profileId': 'child',
      'editionId': 'e1',
      'revision': 0,
      'records': <String, dynamic>{},
      'operations': <String>[],
    }),);

    final removed = await cleanup.deleteBookProgress(sha);

    expect(removed, 0);
    expect(box.get(badKey), '{not json');
    expect(box.get(missingKey), isNotNull);
  });

  test('无匹配键时返回 0，重复删除幂等', () async {
    final sha = 'd' * 64;
    expect(await cleanup.deleteBookProgress(sha), 0);
    box.put(
      'textbook_recognition_v1:digest-x',
      jsonEncode({
        'v': 1,
        'profileId': 'child',
        'bookId': sha,
        'editionId': 'e1',
        'revision': 0,
        'records': <String, dynamic>{},
        'audio': <String, dynamic>{},
        'operations': <String>[],
      }),
    );
    expect(await cleanup.deleteBookProgress(sha), 1);
    expect(await cleanup.deleteBookProgress(sha), 0);
  });
}
