import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/backup_history_service.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/core/services/restore_coordinator.dart';
import 'package:poemath/data/providers/provider_invalidation.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/assistant/assistant_session_provider.dart';

final backupHistoryProvider =
    Provider<BackupHistoryService>((ref) => BackupHistoryService(
          backup: ref.watch(backupServiceProvider),
        ),);

RestoreCoordinator createRestoreCoordinator(Ref ref,
        {NotificationService? notifications,}) =>
    RestoreCoordinator(
      backup: ref.read(backupServiceProvider),
      history: ref.read(backupHistoryProvider),
      assistantBarrier:
          ref.read(assistantSessionProvider.notifier).whileRestoring<int>,
      reconcile: (notifications ?? NotificationService.instance)
          .reconcileWithStoredSettings,
      invalidate: () => invalidateAllHiveProviders(ref.invalidate),
    );

final restoreCoordinatorProvider =
    Provider.family<RestoreCoordinator, NotificationService?>(
        (ref, notifications) =>
            createRestoreCoordinator(ref, notifications: notifications),);
