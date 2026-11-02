import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/cache_activity.dart';
import 'package:poemath/core/services/cache_file_storage.dart';
import 'package:poemath/core/services/storage_management_service.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/widgets/app_tile.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/features/profile/settings_page.dart';
import 'package:poemath/features/profile/storage_management_page.dart';
import 'package:poemath/features/profile/storage_management_provider.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/narration_fakes.dart';
import '../../helpers/parent_access_test_helper.dart';

class _StorageService extends StorageManagementService {
  _StorageService()
      : super(
          textbooks: TextbookFileService(),
          tts: TtsService(NarrationSettings(), flutterTts: NarrationEngine()),
        );

  final usages = <StorageCacheKind, CacheUsage?>{
    for (final kind in StorageCacheKind.values)
      if (kind != StorageCacheKind.legacySpeechModels)
        kind: kind == StorageCacheKind.textbookCovers ||
                kind == StorageCacheKind.textbookContent
            ? const CacheUsage(bytes: 1024, entries: 2)
            : const CacheUsage(),
  };
  final cleared = <StorageCacheKind>[];
  int scans = 0;
  Object? scanError;
  Object? clearError;
  Completer<void>? clearGate;
  bool partialFailure = false;

  @override
  Future<StorageCacheSnapshot> scan() async {
    scans++;
    if (scanError case final error?) throw error;
    return StorageCacheSnapshot([
      for (final entry in usages.entries)
        StorageCacheEntry(kind: entry.key, usage: entry.value),
    ]);
  }

  @override
  Future<void> clear(StorageCacheKind kind) async {
    cleared.add(kind);
    await clearGate?.future;
    if (clearError case final error?) {
      if (partialFailure) {
        usages[kind] = const CacheUsage(bytes: 512, entries: 1);
      }
      throw error;
    }
    usages[kind] = const CacheUsage();
  }
}

Finder _clearOf(String label) => find.descendant(
      of: find.ancestor(
        of: find.textContaining(label),
        matching: find.byType(AppTile),
      ),
      matching: find.widgetWithText(TextButton, '清理'),
    );

Finder get _refreshButton => find.ancestor(
      of: find.byTooltip('刷新缓存占用'),
      matching: find.byType(IconButton),
    );

void main() {
  late _StorageService service;
  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
    service = _StorageService();
  });
  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForTesting();
  });

  Future<void> show(
    WidgetTester tester, {
    Widget? home,
    bool largeText = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageManagementServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
          builder: (context, child) => largeText
              ? MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                )
              : child!,
          home: home ?? const StorageManagementPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('从家长与数据进入存储管理，列出实际缓存占用', (tester) async {
    await show(tester, home: const SettingsPage());
    await tester.tap(find.text('家长与数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('存储管理'));
    await tester.pumpAndSettle();
    expect(find.byType(StorageManagementPage), findsOneWidget);
    expect(find.text('磁盘缓存 2.0 KB'), findsOneWidget);
    expect(find.text('内存缓存 0 B'), findsOneWidget);
    expect(find.textContaining('教材封面'), findsOneWidget);
    expect(find.textContaining('2个文件 · 1.0 KB'), findsNWidgets(2));
    expect(service.scans, 1);
    expect(service.cleared, isEmpty);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('取消不清理，确认只清理选中项并刷新占用', (tester) async {
    await show(tester);
    await tester.tap(_clearOf('教材封面'));
    await tester.pumpAndSettle();
    expect(find.text('清理教材封面？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(service.cleared, isEmpty);
    expect(service.scans, 1);
    await tester.tap(_clearOf('教材封面'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '清理缓存'));
    await tester.pumpAndSettle();
    expect(service.cleared, [StorageCacheKind.textbookCovers]);
    expect(service.scans, 2);
    expect(find.text('磁盘缓存 1.0 KB'), findsOneWidget);
    expect(find.textContaining('2个文件 · 1.0 KB'), findsOneWidget);
    expect(tester.widget<TextButton>(_clearOf('教材封面')).onPressed, isNull);
    expect(tester.widget<TextButton>(_clearOf('教材解析')).onPressed, isNotNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('确认和清理期间防止重复操作，异步完成后按钮恢复', (tester) async {
    service.clearGate = Completer<void>();
    await show(tester);
    await tester.tap(_clearOf('教材封面'));
    await tester.tap(_clearOf('教材封面'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '清理缓存'));
    await tester.pumpAndSettle();
    expect(service.cleared, [StorageCacheKind.textbookCovers]);
    expect(find.text('清理中…'), findsOneWidget);
    expect(tester.widget<TextButton>(_clearOf('教材解析')).onPressed, isNull);
    expect(
      tester.widget<IconButton>(_refreshButton).onPressed,
      isNull,
    );
    service.clearGate!.complete();
    await tester.pumpAndSettle();
    expect(service.scans, 2);
    expect(tester.widget<TextButton>(_clearOf('教材解析')).onPressed, isNotNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('清理在用缓存提示重试，部分失败会刷新实际剩余占用', (tester) async {
    service.clearError = const CacheInUseException();
    await show(tester);
    await tester.tap(_clearOf('教材封面'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '清理缓存'));
    await tester.pumpAndSettle();
    expect(find.text('缓存正在使用，请在操作完成后重试'), findsOneWidget);
    expect(service.scans, 1);
    service.clearError = StateError('第二个文件未清理');
    service.partialFailure = true;
    await tester.tap(_clearOf('教材封面'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '清理缓存'));
    await tester.pumpAndSettle();
    expect(find.text('清理未完成，请刷新后重试'), findsOneWidget);
    expect(find.textContaining('1个文件 · 512 B'), findsOneWidget);
    expect(find.text('磁盘缓存 1.5 KB'), findsOneWidget);
    expect(service.scans, 2);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('统计失败可刷新，单项失败与零占用明确区分', (tester) async {
    service.scanError = StateError('目录无法读取');
    await show(tester);
    expect(find.text('暂时无法读取缓存，请刷新重试。'), findsOneWidget);
    expect(
      tester.widget<IconButton>(_refreshButton).onPressed,
      isNotNull,
    );
    service.scanError = null;
    service.usages[StorageCacheKind.textbookCovers] = null;
    await tester.tap(find.byTooltip('刷新缓存占用'));
    await tester.pumpAndSettle();
    expect(find.textContaining('统计失败，请刷新重试'), findsOneWidget);
    expect(find.text('部分缓存暂时无法统计，以上为已统计占用。'), findsOneWidget);
    expect(tester.widget<TextButton>(_clearOf('教材封面')).onPressed, isNull);
    expect(tester.widget<TextButton>(_clearOf('教材解析')).onPressed, isNotNull);
    expect(service.scans, 2);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('确认窗口中家长锁定会关闭窗口，不能继续清理', (tester) async {
    await show(
      tester,
      home: const ParentAccessBoundary(child: StorageManagementPage()),
    );
    await tester.tap(_clearOf('教材封面'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    lockParentForTesting();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '清理缓存'), findsNothing);
    expect(find.widgetWithText(FilledButton, '解锁'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(StorageManagementPage), findsNothing);
    expect(service.cleared, isEmpty);
    expect(find.text('请由家长解锁后继续'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('卡片随宽度分列，窄屏和大字号仍能显示长分类与操作按钮', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final (width, largeText, columns) in [
      (320.0, false, 1),
      (800.0, false, 2),
      (1200.0, false, 3),
      (320.0, true, 1),
      (1200.0, true, 1),
    ]) {
      tester.view.physicalSize = Size(width, 1000);
      await show(tester, largeText: largeText);
      final cards = [
        for (final label in ['教材封面', '教材解析', '教材朗读'])
          tester.getRect(
            find.ancestor(
              of: _clearOf(label),
              matching: find.byType(AppTile),
            ),
          ),
      ];
      for (var column = 1; column < columns; column++) {
        expect(cards[column].top, cards.first.top);
        expect(cards[column].left, greaterThan(cards[column - 1].right));
        expect(cards[column].width, closeTo(cards.first.width, 0.1));
      }
      if (columns < cards.length) {
        expect(cards[columns].top, greaterThan(cards.first.bottom));
      }
      await tester.scrollUntilVisible(find.textContaining('文件与图片选择'), 280);
      await tester.pumpAndSettle();
      expect(find.textContaining('文件与图片选择'), findsOneWidget);
      expect(_clearOf('文件与图片选择'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 2));
    }
  });
}
