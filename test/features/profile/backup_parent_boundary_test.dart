import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/backup_history_service.dart';
import 'package:poemath/core/services/backup_payload_cipher.dart';
import 'package:poemath/core/services/backup_credentials_cipher.dart';
import 'package:poemath/core/services/restore_coordinator.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/providers/backup_protection_providers.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/profile/widgets/backup_import_flow.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  testWidgets('直接访问设置路由也需家长验证，取消后不能挂载设置页', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'parent_protection': '{}'});
    await tester.runAsync(() async {
      await setUpHiveForTesting();
      await HiveBoxes.settings.put('parent_protection_enabled', true);
    });
    final router = createAppRouter(initialLocation: AppRoutes.settings);
    addTearDown(() => tester.runAsync(tearDownHiveForTesting));
    addTearDown(router.dispose);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pump();
    });
    await tester.pumpAndSettle();
    expect(find.text('家长解锁'), findsWidgets);
    expect(find.text('家长保护与云额度'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('请由家长解锁后继续'), findsOneWidget);
    expect(find.text('家长保护与云额度'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    ParentAccessService.instance.lock();
  });

  testWidgets('整包解密后可选择跳过未来版本凭据并恢复学习设置', (tester) async {
    late Directory root;
    late String encrypted;
    await tester.runAsync(() async {
      await setUpHiveForTesting();
      root = await Directory.systemTemp.createTemp('encrypted_preview_');
      await HiveBoxes.settings.put('theme_mode', 'dark');
      final credentialNode = await encryptCredentials(
          {'future_vendor_key': 'synthetic-key'}, 'synthetic-passphrase',);
      encrypted = await encryptBackupPayload(
        jsonEncode({
          'version': 1,
          'settings': {'theme_mode': 'light'},
          'credentials': credentialNode,
        }),
        passphrase: 'synthetic-passphrase',
      );
    });
    addTearDown(
      () => tester.runAsync(() async {
        await root.delete(recursive: true);
        await tearDownHiveForTesting();
      }),
    );
    RestoreResult? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupHistoryProvider.overrideWith(
            (ref) => BackupHistoryService(
              backup: ref.read(backupServiceProvider),
              keyProvider: () async => List<int>.generate(32, (i) => i),
              directoryProvider: () async => root,
            ),
          ),
          restoreCoordinatorProvider(null).overrideWith(
            (ref) => RestoreCoordinator(
              backup: BackupService(),
              history: ref.read(backupHistoryProvider),
              assistantBarrier: (action) => action(),
              reconcile: () async => true,
              invalidate: () {},
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () async {
                  result =
                      await previewAndRestoreBackup(context, ref, encrypted);
                },
                child: const Text('导入'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('导入'));
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'synthetic-passphrase');
    await tester.runAsync(() async {
      await tester.tap(find.text('恢复'));
    });
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (find.text('备份预览').evaluate().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('备份预览'), findsOneWidget);
    expect(HiveBoxes.settings.get('theme_mode'), 'dark');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    await tester.runAsync(() async {
      await tester.tap(find.text('确认覆盖'));
    });
    for (var i = 0; i < 250 && result == null; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(result, isNotNull);
    expect(HiveBoxes.settings.get('theme_mode'), 'light');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('取消备份预览不生成快照、不覆盖学习数据', (tester) async {
    late Directory root;
    await tester.runAsync(() async {
      await setUpHiveForTesting();
      root = await Directory.systemTemp.createTemp('preview_cancel_');
      await HiveBoxes.settings.put('theme_mode', 'dark');
    });
    addTearDown(
      () => tester.runAsync(() async {
        await root.delete(recursive: true);
        await tearDownHiveForTesting();
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupHistoryProvider.overrideWith(
            (ref) => BackupHistoryService(
              keyProvider: () async => List<int>.generate(32, (i) => i),
              backup: ref.read(backupServiceProvider),
              directoryProvider: () async => root,
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => previewAndRestoreBackup(
                  context,
                  ref,
                  '{"version":1,"settings":{"theme_mode":"light"}}',
                ),
                child: const Text('导入'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    expect(find.text('备份预览'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(HiveBoxes.settings.get('theme_mode'), 'dark');
    expect(await tester.runAsync(() => root.list().toList()), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
