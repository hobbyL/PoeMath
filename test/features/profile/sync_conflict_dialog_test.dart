// test/features/profile/sync_conflict_dialog_test.dart
//
// 跨设备同步冲突确认框：两个方向的文案指向、时间展示、返回约定。
// 返回约定尤其重要 —— 调用方把非 true 一律视为「中止操作」，
// 任何一条分支返回错值都会导致用户取消后仍被覆盖。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/features/profile/widgets/sync_conflict_dialog.dart';

void main() {
  /// 打开对话框并返回结果容器；关闭后 `value` 即返回值。
  Future<ValueNotifier<bool?>> pumpAndOpen(
    WidgetTester tester, {
    required SyncConflictDirection direction,
    required DateTime remoteExportedAt,
    required DateTime localSyncedAt,
  }) async {
    final result = ValueNotifier<bool?>(null);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result.value = await showSyncConflictDialog(
                    context,
                    direction: direction,
                    remoteExportedAt: remoteExportedAt,
                    localSyncedAt: localSyncedAt,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  final remote = DateTime(2026, 10, 13, 15, 45);
  final local = DateTime(2026, 10, 12, 8, 5);

  testWidgets('下载方向：说明覆盖本机、展示两端时间，确认返回 true', (tester) async {
    final result = await pumpAndOpen(
      tester,
      direction: SyncConflictDirection.download,
      remoteExportedAt: remote,
      localSyncedAt: local,
    );

    expect(find.text('⚠️ 云端数据比本机新'), findsOneWidget);
    expect(find.textContaining('继续下载会用云端数据覆盖本机'), findsOneWidget);
    expect(find.text('云端备份时间：'), findsOneWidget);
    expect(find.text('本机上次同步：'), findsOneWidget);
    // 时间展示到分钟（本地时区）。
    expect(find.text('2026-10-13 15:45'), findsOneWidget);
    expect(find.text('2026-10-12 08:05'), findsOneWidget);

    await tester.tap(find.text('仍然下载覆盖'));
    await tester.pumpAndSettle();
    expect(result.value, isTrue);
  });

  testWidgets('上传方向：说明覆盖云端，确认返回 true', (tester) async {
    final result = await pumpAndOpen(
      tester,
      direction: SyncConflictDirection.upload,
      remoteExportedAt: remote,
      localSyncedAt: local,
    );

    expect(find.textContaining('继续上传会用本机数据覆盖云端'), findsOneWidget);
    expect(find.text('本机数据时间：'), findsOneWidget);
    await tester.tap(find.text('仍然上传覆盖'));
    await tester.pumpAndSettle();
    expect(result.value, isTrue);
  });

  testWidgets('取消返回 false（调用方据此保证两端零变更）', (tester) async {
    final result = await pumpAndOpen(
      tester,
      direction: SyncConflictDirection.download,
      remoteExportedAt: remote,
      localSyncedAt: local,
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result.value, isFalse);
  });

  testWidgets('点遮罩关闭返回 null（同样视为中止）', (tester) async {
    final result = await pumpAndOpen(
      tester,
      direction: SyncConflictDirection.download,
      remoteExportedAt: remote,
      localSyncedAt: local,
    );

    // 点对话框外区域 → barrierDismissible 默认关闭对话框并返回 null。
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(result.value, isNull);
  });
}
