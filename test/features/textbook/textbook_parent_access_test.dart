import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/textbook_management_page.dart';
import 'package:poemath/features/textbook/widgets/textbook_cache_manager_sheet.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/textbook_fixture.dart';

class _MissingFiles extends TextbookFileService {
  final removed = <String>[];
  int imports = 0;
  int clears = 0;

  @override
  Future<String?> installedPath(Textbook book) async => null;

  @override
  Future<TextbookStorageUsage> storageUsage(Textbook book) async =>
      const TextbookStorageUsage(
        pdfBytes: 0,
        coverBytes: 5,
        contentBytes: 0,
        contentFiles: 0,
        audioBytes: 0,
        audioFiles: 0,
        courseBytes: 0,
      );

  @override
  Future<void> removePdf(String id) async => removed.add(id);

  @override
  Future<void> clearDerived(Textbook book) async => clears++;

  @override
  Future<ImportedTextbookFile> importPdf({
    required String sourcePath,
    required TextbookImportToken token,
    TextbookImportProgress? onProgress,
  }) async {
    token.check();
    imports++;
    throw StateError('No PDF should be imported in this test');
  }

  @override
  Future<void> discardPickerCopy(String sourcePath) async {}
}

class _ObservedDeleteRepository extends TextbookRepository {
  final deleted = Completer<void>();

  @override
  Future<void> delete(String id) async {
    await super.delete(id);
    deleted.complete();
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final access = ParentAccessService.instance;
  final book = textbookFixture();
  const progressKey = 'textbook_exercise_v1:synthetic-parent-access';
  late TextbookRepository repo;
  late _MissingFiles files;
  late Directory directory;
  late TextbookCourseRepository courses;

  setUp(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    FlutterSecureStorage.setMockInitialValues({});
    await setUpHiveForTesting();
    await access.initialize();
    repo = TextbookRepository();
    files = _MissingFiles();
    directory = await Directory.systemTemp.createTemp('textbook-parent-');
    courses =
        TextbookCourseRepository(directoryProvider: () async => directory);
    await repo.addIfAbsent(book);
    await repo.savePage('default', book, 2);
    await HiveBoxes.settings
        .put(progressKey, jsonEncode({'bookId': book.pdfSha256}));
    await access.configure('246810');
  });
  tearDown(() async {
    access.lock();
    await tearDownHiveForTesting();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  List<Override> overrides() => [
        textbookRepositoryProvider.overrideWithValue(repo),
        textbookFileServiceProvider.overrideWithValue(files),
        textbookCourseRepositoryProvider.overrideWithValue(courses),
        textbookCourseProvider(book.pdfSha256)
            .overrideWith((ref) async => null),
        textbookCatalogProvider.overrideWith((ref) async => []),
      ];

  Future<void> mount(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      await drainHiveWritesForTesting(tester);
    });
    await tester.runAsync(
      () => tester.pumpWidget(
        ProviderScope(overrides: overrides(), child: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> waitForUnlockDialog(WidgetTester tester) async {
    final unlock = find.widgetWithText(FilledButton, '解锁');
    for (var attempt = 0; attempt < 50 && unlock.evaluate().isEmpty; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(unlock, findsOneWidget);
  }

  void expectPreserved() {
    expect(repo.find(book.pdfSha256)!.toJson(), book.toJson());
    expect(repo.reading('default', book.pdfSha256).page, 2);
    expect(
      jsonDecode(HiveBoxes.settings.get(progressKey) as String),
      {'bookId': book.pdfSha256},
    );
    expect(files.removed, isEmpty);
  }

  testWidgets('锁定时孩子仍可打开缺失PDF详情，管理入口必须解锁且数据保留', (tester) async {
    access.lock();
    final router = createAppRouter(
      initialLocation: AppRoutes.textbookDetailOf(book.pdfSha256),
    );
    await mount(tester, MaterialApp.router(routerConfig: router));
    expect(find.text('打开书籍管理'), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('打开书籍管理')));
    await tester.pumpAndSettle();
    await waitForUnlockDialog(tester);
    expect(find.byType(TextbookManagementPage), findsNothing);
    expect(find.text('请由家长解锁后继续'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '解锁'), findsOneWidget);
    expectPreserved();
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    await drainHiveWritesForTesting(tester);
  });

  for (final location in [
    AppRoutes.textbookManageDetailOf(book.pdfSha256),
    AppRoutes.textbookReviewOf(book.pdfSha256),
  ]) {
    testWidgets('教材管理深链锁定时不构造可编辑页面：$location', (tester) async {
      access.lock();
      final router = createAppRouter(initialLocation: location);
      await mount(tester, MaterialApp.router(routerConfig: router));
      await waitForUnlockDialog(tester);
      expect(find.text('请由家长解锁后继续'), findsOneWidget);
      expect(find.text('内容审核'), findsNothing);
      expectPreserved();
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      await drainHiveWritesForTesting(tester);
    });
  }

  for (final deleting in [false, true]) {
    testWidgets('${deleting ? '删除本书' : '清理缓存'}确认等待期间锁定，确认后无写入', (tester) async {
      // Mount without the route boundary to verify the handler itself rechecks.
      await mount(
        tester,
        MaterialApp(home: Scaffold(body: TextbookCacheSheet(book: book))),
      );
      final key = ValueKey(deleting ? 'cache-delete-book' : 'cache-clear-all');
      await tester.runAsync(() => tester.tap(find.byKey(key)));
      await tester.pumpAndSettle();
      access.lock();
      final confirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, deleting ? '删除本书' : '清理'),
      );
      await tester.runAsync(() => tester.tap(confirm));
      await tester.pumpAndSettle();
      expectPreserved();
      expect(files.clears, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await drainHiveWritesForTesting(tester);
    });
  }

  testWidgets('家长正常授权删除按实际仓储清除书目和学习记录', (tester) async {
    final observedRepo = _ObservedDeleteRepository();
    repo = observedRepo;
    await mount(
      tester,
      MaterialApp(home: Scaffold(body: TextbookCacheSheet(book: book))),
    );
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('cache-delete-book'))),
    );
    await tester.pumpAndSettle();
    final confirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, '删除本书'),
    );
    await tester.runAsync(() => tester.tap(confirm));
    // 书目消失只是中间状态；交替推进真实 IO 和虚拟时钟，等完整删除结束。
    for (var attempt = 0;
        attempt < 100 && !observedRepo.deleted.isCompleted;
        attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(observedRepo.deleted.isCompleted, isTrue, reason: '书目和阅读位置应已完整删除');
    await tester.pumpAndSettle();
    expect(repo.find(book.pdfSha256), isNull);
    expect(HiveBoxes.settings.containsKey(progressKey), isFalse);
    expect(repo.reading('default', book.pdfSha256).page, 1);
    expect(files.removed, [book.pdfSha256]);
    await tester.pumpWidget(const SizedBox.shrink());
    await drainHiveWritesForTesting(tester);
  });

  testWidgets('文件选择等待期间锁定，晚返回不能导入PDF或登记书目', (tester) async {
    final picked = Completer<PlatformFile?>();
    await mount(
      tester,
      MaterialApp(
        home: TextbookManagementPage(pickPdf: () => picked.future),
      ),
    );
    await tester.tap(find.byTooltip('导入'));
    await tester.pump();
    access.lock();
    picked.complete(
      PlatformFile(name: 'synthetic.pdf', size: 10, path: '/synthetic.pdf'),
    );
    await tester.pumpAndSettle();
    expect(files.imports, 0);
    expect(find.text('教材登记'), findsNothing);
    expectPreserved();
    await tester.pumpWidget(const SizedBox.shrink());
    await drainHiveWritesForTesting(tester);
  });
}
