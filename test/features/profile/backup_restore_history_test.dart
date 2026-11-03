import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/backup_history_service.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/backup_protection_providers.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/profile/backup_restore_page.dart';

import '../../helpers/hive_test_helper.dart';

class _History extends BackupHistoryService {
  _History() : super(backup: BackupService());
  @override
  Future<BackupHistoryOverview> overview() async => (
    snapshots: [
      BackupSnapshot('1_daily_deadbeef.json', DateTime(2026, 11, 3), 'daily'),
    ],
    unreadableCount: 1,
  );
}

class _Store extends SecureCredentialStore {
  @override
  Future<String?> readBackupPassphrase() async => null;
}

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  testWidgets('历史隔离提示可见，正常快照仍提供恢复入口', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupHistoryProvider.overrideWithValue(_History()),
          secureCredentialStoreProvider.overrideWithValue(_Store()),
        ],
        child: const MaterialApp(home: BackupRestorePage()),
      ),
    );
    await tester.pumpAndSettle();
    final notice = find.text('有 1 份历史备份无法读取，原始文件已保留。其他备份可正常使用。');
    expect(notice, findsOneWidget);
    expect(
      find.ancestor(of: notice, matching: find.byType(ColoredCard)),
      findsOneWidget,
    );
    expect(find.text('每日快照'), findsOneWidget);
    await tester.ensureVisible(notice);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
