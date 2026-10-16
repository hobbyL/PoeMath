import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/backup_history_service.dart';
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
    await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),);
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

  testWidgets('取消备份预览不生成快照、不覆盖学习数据', (tester) async {
    late Directory root;
    await tester.runAsync(() async {
      await setUpHiveForTesting();
      root = await Directory.systemTemp.createTemp('preview_cancel_');
      await HiveBoxes.settings.put('theme_mode', 'dark');
    });
    addTearDown(() => tester.runAsync(() async {
          await root.delete(recursive: true);
          await tearDownHiveForTesting();
        }),);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          backupHistoryProvider.overrideWith((ref) => BackupHistoryService(
              backup: ref.read(backupServiceProvider),
              directoryProvider: () async => root,),),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: Consumer(
                    builder: (context, ref, _) => TextButton(
                        onPressed: () => previewAndRestoreBackup(context, ref,
                            '{"version":1,"settings":{"theme_mode":"light"}}',),
                        child: const Text('导入'),),),),),),);
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
