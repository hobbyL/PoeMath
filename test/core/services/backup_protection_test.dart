import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/backup_history_service.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/cache_activity.dart';
import 'package:poemath/core/services/credential_configuration_access.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/restore_coordinator.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';

void main() {
  late Directory directory;
  late BackupService backup;
  late BackupHistoryService history;
  var now = DateTime(2026, 10, 16);
  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
    directory = await Directory.systemTemp.createTemp('backup_protection_');
    backup = BackupService();
    now = DateTime(2026, 10, 16);
    history = BackupHistoryService(
      keyProvider: () async => List<int>.generate(32, (i) => i),
      backup: backup,
      directoryProvider: () async => directory,
      clock: () => now,
      retention: 3,
    );
  });
  tearDown(() async {
    lockParentForTesting();
    await directory.delete(recursive: true);
    await tearDownHiveForTesting();
  });

  test('快照无凭据且有界，每日快照默认关与并发幂等', () async {
    await history.maybeCreateDaily();
    expect(await history.list(), isEmpty);
    await history.setDailyEnabled(true);
    // 自动快照在未配置/锁定时仍可运行，管理门禁只限制修改保护设置。
    await HiveBoxes.settings.put('parent_protection_enabled', false);
    await Future.wait(List.generate(8, (_) => history.maybeCreateDaily()));
    expect(await history.list(), hasLength(1));
    for (var index = 0; index < 4; index++) {
      now = now.add(const Duration(days: 1));
      await history.create();
    }
    final entries = await history.list();
    expect(entries, hasLength(3));
    expect(entries.first.createdAt, now);
    final payload = jsonDecode(
      await history.read(entries.first.id),
    ) as Map<String, dynamic>;
    expect(payload.containsKey('credentials'), isFalse);
    // parent_protection_enabled 现随备份迁移（换机后孩子仍受保护），
    // 因此快照里会出现。快照本身不含凭据这一点不变。
    expect(
      (payload['settings'] as Map).containsKey('parent_protection_enabled'),
      isTrue,
    );
    await expectLater(history.read('../escape.json'), throwsFormatException);
  });

  test('损坏旧历史隔离留存，不阻断跨日快照且不被保留数量清理', () async {
    final historyDirectory = await Directory('${directory.path}/backup_history')
        .create();
    const id = '1_daily_deadbeef.json';
    final bad = File('${historyDirectory.path}/$id');
    const original = '{"version":';
    await bad.writeAsString(original);
    await history.setDailyEnabled(true);
    for (var day = 0; day < 4; day++) {
      await history.maybeCreateDaily();
      now = now.add(const Duration(days: 1));
    }
    final entries = await history.list();
    expect(entries, hasLength(3));
    expect(entries.every((entry) => entry.reason == 'daily'), isTrue);
    expect(HiveBoxes.meta.get('last_daily_snapshot'), '2026-10-19');
    expect(await bad.exists(), isFalse);
    expect(
      await File('${historyDirectory.path}/unreadable/$id').readAsString(),
      original,
    );
    final restarted = BackupHistoryService(
      backup: backup,
      directoryProvider: () async => directory,
      keyProvider: () async => List<int>.filled(32, 7),
    );
    final overview = await restarted.overview();
    expect(overview.unreadableCount, 1);
    expect(overview.snapshots, hasLength(3));
  });

  test('预览纯读，协调恢复先保护旧数据且刷新镜像；历史可再恢复', () async {
    await HiveBoxes.settings.put('theme_mode', 'dark');
    final preview = backup.inspectJson(
      jsonEncode({
        'version': 1,
        'exportedAt': '2026-10-01T00:00:00Z',
        'settings': {'theme_mode': 'light'},
      }),
    );
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
      invalidate: () => refreshes++,
    );
    await coordinator.restore(preview);
    expect(HiveBoxes.settings.get('theme_mode'), 'light');
    expect(notifications, 1);
    expect(refreshes, 1);
    final protected = (await history.list()).single;
    expect(protected.reason, 'before_restore');
    await coordinator.restore(
      backup.inspectJson(await history.read(protected.id)),
    );
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

  test('协调恢复等待期间锁定再解锁，旧授权不能创建快照或恢复数据', () async {
    await HiveBoxes.settings.put('theme_mode', 'dark');
    final entered = Completer<void>();
    final release = Completer<void>();
    var refreshes = 0;
    final coordinator = RestoreCoordinator(
      backup: backup,
      history: history,
      assistantBarrier: (action) async {
        entered.complete();
        await release.future;
        return action();
      },
      reconcile: () async => true,
      invalidate: () => refreshes++,
    );
    final result = expectLater(
      coordinator.restore(
        backup.inspectJson('{"version":1,"settings":{"theme_mode":"light"}}'),
      ),
      throwsA(isA<ParentAccessDenied>()),
    );
    await entered.future;
    final parent = ParentAccessService.instance;
    parent.lock();
    expect(await parent.authenticate(testParentPin), isTrue);
    release.complete();
    await result;
    expect(HiveBoxes.settings.get('theme_mode'), 'dark');
    expect(await history.list(), isEmpty);
    expect(refreshes, 0);
  });

  test('底层恢复等待配置队列时锁定再解锁，旧请求不能替换数据', () async {
    await HiveBoxes.settings.put('theme_mode', 'dark');
    final entered = Completer<void>();
    final release = Completer<void>();
    final blocker = CredentialConfigurationAccess.exclusive(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final result = expectLater(
      backup.restoreFromJson('{"version":1,"settings":{"theme_mode":"light"}}'),
      throwsA(isA<ParentAccessDenied>()),
    );
    final parent = ParentAccessService.instance;
    parent.lock();
    expect(await parent.authenticate(testParentPin), isTrue);
    release.complete();
    await blocker;
    await result;
    expect(HiveBoxes.settings.get('theme_mode'), 'dark');
    expect(HiveBoxes.meta.containsKey('practice_draft_epoch'), isFalse);
  });

  test('文件恢复等待选择器缓存时锁定再解锁，旧请求不能重新取得授权', () async {
    await HiveBoxes.settings.put('theme_mode', 'dark');
    final file = File('${directory.path}/incoming.json');
    await file.writeAsString('{"version":1,"settings":{"theme_mode":"light"}}');
    final entered = Completer<void>();
    final release = Completer<void>();
    final blocker = CacheActivity.clear(TemporaryCacheKind.pickers, () async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final result = expectLater(
      backup.restoreFromFile(file.path),
      throwsA(isA<ParentAccessDenied>()),
    );
    final parent = ParentAccessService.instance;
    parent.lock();
    expect(await parent.authenticate(testParentPin), isTrue);
    release.complete();
    await blocker;
    await result;
    expect(HiveBoxes.settings.get('theme_mode'), 'dark');
    expect(HiveBoxes.meta.containsKey('practice_draft_epoch'), isFalse);
  });

  test('保护文件写入失败时数据及草稿不改变', () async {
    await HiveBoxes.settings.put('theme_mode', 'dark');
    final drafts = PracticeDraftRepository();
    await drafts.save('math', {'sessionId': 'original'});
    final unavailable = BackupHistoryService(
      keyProvider: () async => List<int>.generate(32, (i) => i),
      backup: backup,
      directoryProvider: () async =>
          throw const FileSystemException('disk unavailable'),
    );
    var refreshes = 0;
    final coordinator = RestoreCoordinator(
      backup: backup,
      history: unavailable,
      assistantBarrier: (action) => action(),
      reconcile: () async => true,
      invalidate: () => refreshes++,
    );
    await expectLater(
      coordinator.restore(
        backup.inspectJson('{"version":1,"settings":{"theme_mode":"light"}}'),
      ),
      throwsA(isA<FileSystemException>()),
    );
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
      invalidate: () => refreshed = true,
    );
    final result = await coordinator.restore(
      backup.inspectJson('{"version":1,"settings":{"theme_mode":"light"}}'),
    );
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
    final restore = backup.restoreFromJson(
      '{"version":1,"settings":{"theme_mode":"light"}}',
    );
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
