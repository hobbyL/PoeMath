import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/cache_activity.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/storage_management_service.dart';
import 'package:poemath/core/services/textbook_cover_cache.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/tts/narration_audio_cache.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/services/update/update_client.dart';
import 'package:poemath/core/services/update/update_models.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/narration_fakes.dart';
import '../../helpers/parent_access_test_helper.dart';
import '../../helpers/textbook_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory support;
  late Directory temporary;
  late TtsService tts;
  late TextbookFileService textbooks;
  late StorageManagementService service;
  final book = textbookFixture();
  final otherId = 'b' * 64;
  final uuid = '12345678-1234-1234-1234-123456789abc';

  Future<File> write(Directory base, String name, int bytes) async {
    final file = File('${base.path}/$name');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(bytes, 42));
    return file;
  }

  StorageManagementService create({
    void Function()? authorize,
    Future<Directory> Function()? temporaryDirectory,
    Future<void> Function()? preparePickerCleanup,
  }) =>
      StorageManagementService(
        textbooks: textbooks,
        tts: tts,
        supportDirectoryProvider: () async => support,
        temporaryDirectoryProvider: temporaryDirectory ?? () async => temporary,
        imageCache: ImageCache(),
        authorize: authorize ?? () {},
        preparePickerCleanup: preparePickerCleanup ?? () async {},
      );

  Future<void> seed() async {
    await write(support, 'textbooks/cache/${book.pdfSha256}/cover-v1.png', 3);
    await write(
      support,
      'textbooks/cache/${book.pdfSha256}/cover-v1.png.123.pending',
      2,
    );
    await write(support, 'textbooks/cache/${book.pdfSha256}/page-1.json', 4);
    await write(support, 'textbooks/cache/${book.pdfSha256}/layout-1.json', 5);
    await write(support, 'textbooks/cache/$otherId/cover-v0.png', 6);
    await write(support, 'textbooks/cache/$otherId/toc.json', 3);
    await write(temporary, 'textbook-audio/${book.pdfSha256}/sample.mp3', 7);
    await write(
      temporary,
      'textbook-audio/${book.pdfSha256}/sample.mp3.json',
      11,
    );
    await write(temporary, 'textbook-audio/$otherId/sample.wav.pending', 5);
    await write(temporary, 'poemath_update/app.apk', 1024);
    await write(temporary, 'file_picker/123/original.pdf', 10);
    await write(temporary, '$uuid/photo.jpg', 11);
    await write(temporary, '${uuid}123.jpg', 14);
    await write(temporary, 'scaled_photo.jpg', 13);
    await write(temporary, 'IMAGE_20261102_001.jpg', 12);
    await write(temporary, 'share_plus/shared.json', 6);
    await write(temporary, 'poemath_backup_20261102.json', 2);
    await write(temporary, 'poemath_diagnostics_20261102.txt', 1);
    await write(temporary, 'textbook-tts-pending/tts-1.wav', 4);
    await write(support, 'speech_models/old.onnx', 7);
    // 正式文件和未知临时路径应完全保留。
    await write(support, 'textbooks/${book.pdfSha256}.pdf', book.fileSize);
    await write(support, 'textbooks/courses/${book.pdfSha256}.json', 8);
    await write(support, 'picture_story/images/${book.pdfSha256}.png', 9);
    await write(support, 'picture_story_audio/practice.wav', 17);
    await write(support, 'backups/snapshot.json', 10);
    await write(temporary, 'keep.txt', 11);
    await write(temporary, 'unknown/keep.jpg', 12);
    textbooks.contentCache(book);
  }

  Future<Map<StorageCacheKind, int>> bytes() async => {
        for (final entry in (await service.scan()).entries)
          entry.kind: entry.usage!.bytes,
      };

  setUp(() async {
    root = await Directory.systemTemp.createTemp('poemath-storage-management-');
    support = await Directory('${root.path}/support').create();
    temporary = await Directory('${root.path}/temporary').create();
    tts = TtsService(NarrationSettings(), flutterTts: NarrationEngine());
    textbooks = TextbookFileService(
      directoryProvider: () async => support,
      narrationAudioCache:
          NarrationAudioCache(directoryProvider: () async => temporary),
    );
    TextbookCoverCache.clearMemory();
    service = create();
  });

  tearDown(() async {
    TextbookCoverCache.clearMemory();
    tts.dispose();
    await root.delete(recursive: true);
  });

  test('空目录显示真实零占用且不会创建缓存文件', () async {
    final snapshot = await service.scan();
    expect(
      snapshot.entries.map((entry) => entry.kind),
      StorageCacheKind.values
          .where((kind) => kind != StorageCacheKind.legacySpeechModels),
    );
    expect(snapshot.hasErrors, isFalse);
    expect(snapshot.diskBytes, 0);
    expect(snapshot.memoryBytes, 0);
    expect(await support.list().length, 0);
    expect(await temporary.list().length, 0);
  });

  test('按实际目录完整统计封面、解析、校验文件和各类临时副本', () async {
    await seed();
    final snapshot = await service.scan();
    expect(snapshot.hasErrors, isFalse);
    expect(snapshot.diskBytes, 1159);
    expect(snapshot.memoryBytes, 0);
    expect(await bytes(), {
      StorageCacheKind.textbookCovers: 11,
      StorageCacheKind.textbookContent: 12,
      StorageCacheKind.textbookAudio: 23,
      StorageCacheKind.cloudAudio: 0,
      StorageCacheKind.images: 0,
      StorageCacheKind.pictureStoryImages: 9,
      StorageCacheKind.updates: 1024,
      StorageCacheKind.pickers: 60,
      StorageCacheKind.sharing: 9,
      StorageCacheKind.systemTts: 4,
      StorageCacheKind.legacySpeechModels: 7,
    });
    expect(
      snapshot.entries
          .singleWhere((entry) => entry.kind == StorageCacheKind.pickers)
          .usage!
          .entries,
      5,
    );
  });

  for (final kind in StorageCacheKind.values
      .where((kind) => !kind.isMemory && kind.canClear)) {
    test('单独清理 ${kind.name}，保留其他缓存和正式文件', () async {
      await seed();
      final before = await bytes();
      await service.clear(kind);
      final after = await bytes();
      expect(after[kind] ?? 0, 0);
      for (final entry in before.entries.where((entry) => entry.key != kind)) {
        expect(after[entry.key], entry.value, reason: '${entry.key.name} 应保留');
      }
      for (final entry in {
        'textbooks/${book.pdfSha256}.pdf': book.fileSize,
        'textbooks/courses/${book.pdfSha256}.json': 8,
        'picture_story/images/${book.pdfSha256}.png': 9,
        'picture_story_audio/practice.wav': 17,
        'backups/snapshot.json': 10,
      }.entries) {
        expect(
          await File('${support.path}/${entry.key}').readAsBytes(),
          List.filled(entry.value, 42),
        );
      }
      expect(
        await File('${temporary.path}/keep.txt').readAsBytes(),
        List.filled(11, 42),
      );
      expect(
        await File('${temporary.path}/unknown/keep.jpg').readAsBytes(),
        List.filled(12, 42),
      );
    });
  }

  test('清理解析会失效现有对象和晚到结果，下次仍能重新提取', () async {
    final started = Completer<void>();
    final gate = Completer<String>();
    final cache = textbooks.contentCache(book);
    final loading = cache.pageText(1, () {
      started.complete();
      return gate.future;
    });
    await started.future;
    await service.clear(StorageCacheKind.textbookContent);
    gate.complete('旧结果');
    expect(await loading, '旧结果');
    expect((await textbooks.cacheUsage()).content.entries, 0);
    expect(await cache.pageText(1, () async => '重新提取'), '重新提取');
    expect((await textbooks.cacheUsage()).content.entries, 1);
  });

  test('图片内存统计与磁盘分开，清理只释放缓存持有的副本', () async {
    await seed();
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
        .drawRect(const ui.Rect.fromLTWH(0, 0, 2, 3), ui.Paint());
    final picture = recorder.endRecording();
    final image = await picture.toImage(2, 3);
    picture.dispose();
    addTearDown(image.dispose);
    const TextbookCoverCache()
        .remember('${support.path}/textbooks/${book.pdfSha256}.pdf', image);
    final snapshot = await service.scan();
    expect(snapshot.memoryBytes, 24);
    expect(snapshot.diskBytes, 1159);
    await service.clear(StorageCacheKind.images);
    expect((await service.scan()).memoryBytes, 0);
    expect((await service.scan()).diskBytes, 1159);
    expect(image.debugDisposed, isFalse);
  });

  test('扫描失败显示未知占用，不能把故障伪装为零缓存', () async {
    final blocked = await write(support, 'textbooks/cache', 5);
    final snapshot = await service.scan();
    expect(snapshot.hasErrors, isTrue);
    expect(
      snapshot.entries
          .singleWhere(
            (entry) => entry.kind == StorageCacheKind.textbookCovers,
          )
          .usage,
      isNull,
    );
    expect(
      snapshot.entries
          .singleWhere(
            (entry) => entry.kind == StorageCacheKind.textbookContent,
          )
          .usage,
      isNull,
    );
    await expectLater(
      service.clear(StorageCacheKind.textbookCovers),
      throwsA(isA<FileSystemException>()),
    );
    expect(await blocked.readAsBytes(), List.filled(5, 42));
  });

  test('题图单独统计文件数量和磁盘占用，服务边界拒绝清理', () async {
    await seed();
    await write(
      support,
      'picture_story/images/$otherId.png.123-456.pending',
      5,
    );
    await write(support, 'picture_story/images/unknown.png', 17);
    final entry = (await service.scan()).entries.singleWhere(
          (entry) => entry.kind == StorageCacheKind.pictureStoryImages,
        );
    expect(entry.usage!.entries, 2);
    expect(entry.usage!.bytes, 14);
    expect(entry.kind.isMemory, isFalse);
    expect(entry.kind.canClear, isFalse);
    await expectLater(
      service.clear(StorageCacheKind.pictureStoryImages),
      throwsUnsupportedError,
    );
    expect(
      await File('${support.path}/picture_story/images/${book.pdfSha256}.png')
          .length(),
      9,
    );
    expect(
      await File(
        '${support.path}/picture_story/images/$otherId.png.123-456.pending',
      ).length(),
      5,
    );
  });

  test('不扫描或清理缓存目录中的符号链接目标', () async {
    final original = await write(support, 'original/private.pdf', 23);
    final cache = await Directory('${temporary.path}/file_picker').create();
    await Link('${cache.path}/outside').create(original.parent.path);
    expect(
      (await service.scan())
          .entries
          .singleWhere((entry) => entry.kind == StorageCacheKind.pickers)
          .usage!
          .entries,
      0,
    );
    await service.clear(StorageCacheKind.pickers);
    expect(await original.readAsBytes(), List.filled(23, 42));
  });

  test('导入恢复完成后再清理选择副本，恢复保存的正式图片保留', () async {
    final picked = await write(temporary, '$uuid/photo.jpg', 13);
    var recovered = false;
    service = create(
      preparePickerCleanup: () async {
        await write(support, 'picture_story/images/restored.png', 13);
        recovered = true;
      },
    );
    await service.clear(StorageCacheKind.pickers);
    expect(recovered, isTrue);
    expect(await picked.exists(), isFalse);
    expect(
      await File('${support.path}/picture_story/images/restored.png')
          .readAsBytes(),
      List.filled(13, 42),
    );
  });

  test('真实下载在途时不允许删除安装包，下载结束后可清理', () async {
    final file = await write(temporary, 'poemath_update/active.apk', 20);
    final started = Completer<void>();
    final gate = Completer<void>();
    final transport = MockClient.streaming((request, body) async {
      started.complete();
      await gate.future;
      return http.StreamedResponse(Stream.value(List.filled(20, 1)), 200);
    });
    addTearDown(transport.close);
    final client = UpdateClient(
      updateUrl: 'https://updates.example.com/latest.json',
      temporaryDirectoryProvider: () async => temporary,
      client: transport,
    );
    final producer = client.downloadApk(
      AppUpdateInfo(
        packageName: 'com.poemath.app',
        versionName: '1.2.0',
        versionCode: 2,
        tagName: 'v1.2.0',
        channel: 'stable',
        apkUrl: 'https://updates.example.com/app.apk',
        apkSha256: 'a' * 64,
        apkSize: 20,
        mandatory: false,
        notes: '测试更新',
      ),
    );
    await started.future;
    await expectLater(
      service.clear(StorageCacheKind.updates),
      throwsA(isA<CacheInUseException>()),
    );
    expect(await file.exists(), isTrue);
    gate.complete();
    final downloaded = await producer;
    expect(await downloaded.readAsBytes(), List.filled(20, 1));
    await service.clear(StorageCacheKind.updates);
    expect(await file.exists(), isFalse);
    expect(await downloaded.exists(), isFalse);
  });

  group('真实家长授权与学习数据保护', () {
    setUp(() async {
      await setUpHiveForTesting();
      await unlockParentForTesting();
      service = create(authorize: ParentAccessService.instance.assertAllowed);
    });
    tearDown(() async {
      lockParentForTesting();
      await tearDownHiveForTesting();
    });

    test('所有缓存清理保留 Hive 书目、学习记录和家长设置，重开仍在', () async {
      await seed();
      final repository = TextbookRepository();
      await repository.addIfAbsent(book);
      await HiveBoxes.mathSessions.put(
        'storage-test-session',
        MathSession(
          id: 'storage-test-session',
          profileId: 'default',
          grade: 3,
          problemType: 'addition',
          totalProblems: 10,
          correctCount: 8,
          startedAt: DateTime.utc(2026, 11, 2),
        ),
      );
      final before = {
        for (final key in HiveBoxes.settings.keys)
          key: HiveBoxes.settings.get(key),
      };
      for (final kind
          in StorageCacheKind.values.where((kind) => kind.canClear)) {
        await service.clear(kind);
      }
      await HiveBoxes.close();
      await HiveBoxes.init();
      expect(
        {
          for (final key in HiveBoxes.settings.keys)
            key: HiveBoxes.settings.get(key),
        },
        before,
      );
      expect(
        TextbookRepository().find(book.pdfSha256)!.toJson(),
        book.toJson(),
      );
      expect(
        HiveBoxes.mathSessions.get('storage-test-session')!.correctCount,
        8,
      );
      expect(
        HiveBoxes.mathSessions.get('storage-test-session')!.totalProblems,
        10,
      );
      expect(ParentAccessService.instance.isUnlocked, isTrue);
    });

    test('锁定时所有入口拒绝清理，异步扫描后过期也保留文件', () async {
      final file = await write(temporary, 'poemath_update/app.apk', 20);
      final requested = Completer<void>();
      final directory = Completer<Directory>();
      service = create(
        authorize: ParentAccessService.instance.assertAllowed,
        temporaryDirectory: () {
          requested.complete();
          return directory.future;
        },
      );
      final clear = service.clear(StorageCacheKind.updates);
      final denied = expectLater(clear, throwsA(isA<ParentAccessDenied>()));
      await requested.future;
      lockParentForTesting();
      directory.complete(temporary);
      await denied;
      for (final kind in StorageCacheKind.values) {
        await expectLater(
          service.clear(kind),
          throwsA(isA<ParentAccessDenied>()),
        );
      }
      await expectLater(service.scan(), throwsA(isA<ParentAccessDenied>()));
      expect(await file.readAsBytes(), List.filled(20, 42));
    });
  });
}
