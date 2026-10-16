import 'package:poemath/core/services/backup_history_service.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';

class RestoreResult {
  const RestoreResult(this.count, this.notificationsApplied);
  final int count;
  final bool notificationsApplied;
}

class RestoreCoordinator {
  RestoreCoordinator(
      {required this.backup,
      required this.history,
      required this.assistantBarrier,
      required this.reconcile,
      required this.invalidate,
      ParentAccessService? parent,})
      : parent = parent ?? ParentAccessService.instance;
  final BackupService backup;
  final BackupHistoryService history;
  final Future<int> Function(Future<int> Function()) assistantBarrier;
  final Future<bool> Function() reconcile;
  final void Function() invalidate;
  final ParentAccessService parent;
  static bool _restoring = false;

  Future<RestoreResult> restore(BackupPreview preview,
      {String? passphrase,}) async {
    parent.assertAllowed();
    if (_restoring) throw StateError('正在恢复数据');
    _restoring = true;
    var restoreAttempted = false;
    try {
      // 错口令不会生成保护文件，更不会触碰学习数据。
      await backup.validateRestoreCredentials(preview, passphrase: passphrase);
      final count = await assistantBarrier(() =>
          PracticeDraftRepository.whileRestoring(() async {
            await history.create(reason: 'before_restore');
            parent.assertAllowed();
            restoreAttempted = true;
            return backup.restoreFromJson(preview.json, passphrase: passphrase);
          }),);
      var notificationsApplied = false;
      try {
        notificationsApplied = await reconcile();
      } on Object catch (error, stackTrace) {
        AppLogger.e('数据恢复成功，通知镜像更新失败',
            tag: 'Backup', error: error, stackTrace: stackTrace,);
      }
      return RestoreResult(count, notificationsApplied);
    } finally {
      try {
        if (restoreAttempted) invalidate();
      } finally {
        _restoring = false;
      }
    }
  }
}
