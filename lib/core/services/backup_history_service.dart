import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';

class BackupSnapshot {
  const BackupSnapshot(this.id, this.createdAt, this.reason);
  final String id;
  final DateTime createdAt;
  final String reason;
  String get label => switch (reason) {
        'before_restore' => '恢复前保护',
        'daily' => '每日快照',
        _ => '手动快照',
      };
}

/// 本地回退文件始终不含 credentials，不与外部备份或云同步时间线混用。
class BackupHistoryService {
  BackupHistoryService(
      {required BackupService backup,
      Future<Directory> Function()? directoryProvider,
      DateTime Function()? clock,
      this.retention = 10,})
      : _backup = backup,
        _directoryProvider =
            directoryProvider ?? getApplicationSupportDirectory,
        _clock = clock ?? DateTime.now;
  final BackupService _backup;
  final Future<Directory> Function() _directoryProvider;
  final DateTime Function() _clock;
  final int retention;
  static Future<void> _tail = Future<void>.value();
  static final _validId =
      RegExp(r'^\d+_(manual|daily|before_restore)_[a-f0-9]{8}\.json$');

  bool get dailyEnabled =>
      HiveBoxes.settings.get('daily_snapshot_enabled', defaultValue: false) ==
      true;
  bool get reminderEnabled =>
      HiveBoxes.settings.get('external_backup_reminder', defaultValue: true) ==
      true;
  DateTime? get lastExternalBackup => DateTime.tryParse(
      HiveBoxes.meta.get('last_external_backup') as String? ?? '',);
  bool get externalBackupDue =>
      reminderEnabled &&
      (lastExternalBackup == null ||
          _clock().difference(lastExternalBackup!) >= const Duration(days: 7));
  Future<void> setDailyEnabled(bool enabled) {
    ParentAccessService.instance.assertAllowed();
    return HiveBoxes.settings.put('daily_snapshot_enabled', enabled);
  }

  Future<void> setReminderEnabled(bool enabled) {
    ParentAccessService.instance.assertAllowed();
    return HiveBoxes.settings.put('external_backup_reminder', enabled);
  }

  Future<void> markExternalBackup() =>
      HiveBoxes.meta.put('last_external_backup', _clock().toIso8601String());

  Future<Directory> _directory() async {
    final root = await _directoryProvider();
    return Directory('${root.path}/backup_history').create(recursive: true);
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    try {
      await previous;
      return await action();
    } finally {
      done.complete();
    }
  }

  Future<List<BackupSnapshot>> list() async {
    final directory = await _directory();
    final result = <BackupSnapshot>[];
    await for (final file in directory.list()) {
      final id = file.uri.pathSegments.last;
      if (file is! File || !_validId.hasMatch(id)) continue;
      final match = _validId.firstMatch(id)!;
      final micros = int.tryParse(id.split('_').first);
      if (micros == null) continue;
      try {
        result.add(BackupSnapshot(
            id, DateTime.fromMicrosecondsSinceEpoch(micros), match.group(1)!,),);
      } on ArgumentError {
        continue;
      }
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  Future<String> read(String id) async {
    if (!_validId.hasMatch(id)) throw const FormatException('快照标识无效');
    final directory = await _directory();
    return File('${directory.path}/$id').readAsString();
  }

  Future<BackupSnapshot> create({String reason = 'manual'}) =>
      _exclusive(() => _create(reason));
  Future<BackupSnapshot> _create(String reason) async {
    PracticeDraftRepository.assertSnapshotAllowed();
    if (!const ['manual', 'daily', 'before_restore'].contains(reason) ||
        retention < 1) {
      throw ArgumentError('快照参数无效');
    }
    final json = await _backup.exportToJson();
    final created = _clock();
    final suffix =
        Random.secure().nextInt(0x100000000).toRadixString(16).padLeft(8, '0');
    final id = '${created.microsecondsSinceEpoch}_${reason}_$suffix.json';
    final directory = await _directory();
    final pending = File('${directory.path}/$id.pending');
    await pending.writeAsString(json, flush: true);
    await pending.rename('${directory.path}/$id');
    final entries = await list();
    // 设备时钟回拨也必须保留刚写成的恢复前保护文件。
    for (final old
        in entries.where((entry) => entry.id != id).skip(retention - 1)) {
      await File('${directory.path}/${old.id}').delete();
    }
    return BackupSnapshot(id, created, reason);
  }

  Future<void> maybeCreateDaily() async {
    if (!dailyEnabled || PracticeDraftRepository.isRestoring) return;
    await _exclusive(() async {
      final now = _clock();
      final key = '${now.year}-${now.month}-${now.day}';
      if (HiveBoxes.meta.get('last_daily_snapshot') == key) return;
      await _create('daily');
      await HiveBoxes.meta.put('last_daily_snapshot', key);
    });
  }
}
