import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/backup_history_service.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/restore_coordinator.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  late Directory directory;
  late BackupService backup;
  late BackupHistoryService history;
  var now = DateTime(2026, 10, 16);
  setUp(() async {
    await setUpHiveForTesting();
    directory = await Directory.systemTemp.createTemp('backup_protection_');
    backup = BackupService();
    now = DateTime(2026, 10, 16);
    history = BackupHistoryService(
        backup: backup,
        directoryProvider: () async => directory,
        clock: () => now,
        retention: 3,);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
    await tearDownHiveForTesting();
  });

  test('快照无凭据且有界，每日快照默认关与并发幂等', () async {
    await HiveBoxes.settings.put('parent_protection_enabled', false);
    await history.maybeCreateDaily();
    expect(await history.list(), isEmpty);
    await history.setDailyEnabled(true);
    await Future.wait(List.generate(8, (_) => history.maybeCreateDaily()));
    expect(await history.list(), hasLength(1));
    for (var index = 0; index < 4; index++) {
      now = now.add(const Duration(days: 1));
      await history.create();
    }
    final entries = await history.list();
    expect(entries, hasLength(3));
    expect(entries.first.createdAt, now);
    final payload = jsonDecode(await history.read(entries.first.id))
        as Map<String, dynamic>;
    expect(payload.containsKey('credentials'), isFalse);
    expect(
        (payload['settings'] as Map).containsKey('parent_protection_enabled'),
        isFalse,);
    await expectLater(history.read('../escape.json'), throwsFormatException);
  });

  test('预览纯读，协调恢复先保护旧数据且刷新镜像；历史可再恢复', () async {
    await HiveBoxes.settings.put('theme_mode', 'dark');
    final preview = backup.inspectJson(jsonEncode({
      'version': 1,
      'exportedAt': '2026-10-01T00:00:00Z',
      'settings': {'theme_mode': 'light'},
    }),);
    expect(HiveBoxes.settings.get('theme_mode'), 'dark');
    expect(await history.list(), isEmpty);
    var refreshes = 0;
    var notifications = 0;
    final coordinator = RestoreCoordinator(
        backup: backup,
        history: history,
        assistantBarrier: (action) => action(),
        reconcile: () async {
          notifications++;
          return true;
        },
        invalidate: () => refreshes++,);
    await coordinator.restore(preview);
    expect(HiveBoxes.settings.get('theme_mode'), 'light');
    expect(notifications, 1);
    expect(refreshes, 1);
    final protected = (await history.list()).single;
    expect(protected.reason, 'before_restore');
    await coordinator
        .restore(backup.inspectJson(await history.read(protected.id)));
    expect(HiveBoxes.settings.get('theme_mode'), 'dark');
  });

  test('设备时间回拨也保留新写成的恢复前保护快照', () async {
    for (var index = 0; index < 3; index++) {
      now = now.add(const Duration(days: 1));
      await history.create();
    }
    now = DateTime(2020);
    final fresh = await history.create(reason: 'before_restore');
    final retained = await history.list();
    expect(retained, hasLength(3));
    expect(retained.map((e) => e.id), contains(fresh.id));
    expect(await history.read(fresh.id), contains('"version"'));
  });

  test('保护文件写入失败时数据及草稿不改变', () async {
    await HiveBoxes.settings.put('theme_mode', 'dark');
    final drafts = PracticeDraftRepository();
    await drafts.save('math', {'sessionId': 'original'});
    final unavailable = BackupHistoryService(
        backup: backup,
        directoryProvider: () async =>
            throw const FileSystemException('disk unavailable'),);
    var refreshes = 0;
    final coordinator = RestoreCoordinator(
        backup: backup,
        history: unavailable,
        assistantBarrier: (action) => action(),
        reconcile: () async => true,
        invalidate: () => refreshes++,);
    await expectLater(
        coordinator.restore(backup
            .inspectJson('{"version":1,"settings":{"theme_mode":"light"}}'),),
        throwsA(isA<FileSystemException>()),);
    expect(HiveBoxes.settings.get('theme_mode'), 'dark');
    expect(drafts.get('math')?['sessionId'], 'original');
    expect(refreshes, 0);
  });

  test('通知刷新失败仍报告数据恢复成功并刷新界面镜像', () async {
    var refreshed = false;
    final coordinator = RestoreCoordinator(
        backup: backup,
        history: history,
        assistantBarrier: (action) => action(),
        reconcile: () async => throw StateError('notification unavailable'),
        invalidate: () => refreshed = true,);
    final result = await coordinator.restore(
        backup.inspectJson('{"version":1,"settings":{"theme_mode":"light"}}'),);
    expect(result.notificationsApplied, isFalse);
    expect(HiveBoxes.settings.get('theme_mode'), 'light');
    expect(refreshed, isTrue);
  });

  test('恢复屏障内仅协调器能创建快照，后台每日快照跳过', () async {
    await history.setDailyEnabled(true);
    final entered = Completer<void>();
    final release = Completer<void>();
    final restoration = PracticeDraftRepository.whileRestoring(() async {
      entered.complete();
      await release.future;
      return history.create(reason: 'before_restore');
    });
    await entered.future;
    await history.maybeCreateDaily();
    await expectLater(history.create(), throwsStateError);
    expect(await history.list(), isEmpty);
    release.complete();
    await restoration;
    expect(await history.list(), hasLength(1));
  });

  test('底层直调恢复排空在途练习，阻止新写，成功后旧代次不可重放', () async {
    final drafts = PracticeDraftRepository();
    await drafts.save('math', {'sessionId': 'original'});
    final entered = Completer<void>();
    final release = Completer<void>();
    final active = drafts.guard(() async {
      entered.complete();
      await release.future;
      await HiveBoxes.settings.put('theme_mode', 'dark');
    });
    final activeResult = expectLater(active, throwsStateError);
    await entered.future;
    final restore = backup
        .restoreFromJson('{"version":1,"settings":{"theme_mode":"light"}}');
    await Future<void>.delayed(Duration.zero);
    expect(() => drafts.assertCurrent(), throwsStateError);
    release.complete();
    await activeResult;
    await restore;
    expect(HiveBoxes.settings.get('theme_mode'), 'light');
    expect(drafts.get('math'), isNull);
    expect(() => drafts.assertCurrent(), throwsStateError);
  });
}
