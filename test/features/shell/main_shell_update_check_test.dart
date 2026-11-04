import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/update/android_update_installer.dart';
import 'package:poemath/core/services/update/update_check_controller.dart';
import 'package:poemath/core/services/update/update_client.dart';
import 'package:poemath/core/services/update/update_models.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/data/models/textbook_catalog.dart';
import 'package:poemath/data/repositories/textbook_download_repository.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/features/shell/main_shell.dart';
import 'package:poemath/features/textbook/providers/textbook_download_controller.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/textbook_fixture.dart';

class _SpyDownloads extends TextbookDownloadController {
  _SpyDownloads() : super(TextbookFileService(), TextbookRepository(), (_) {});
  final restoredIds = <List<String>>[];
  @override
  Future<void> restorePending(List<TextbookCatalogEntry> catalog) async {
    restoredIds.add([for (final entry in catalog) entry.book.pdfSha256]);
  }
}

/// 记录 maybeCheck 调用次数的 spy 控制器（基类依赖从不执行）。
class _SpyUpdateController extends UpdateCheckController {
  _SpyUpdateController()
    : super(
        updateCheckConfigured: true,
        client: _NoopUpdateClient(),
        installer: AndroidUpdateInstaller(isAndroid: false),
        onAvailable: (update, current) {},
      );

  int checkCount = 0;

  @override
  Future<void> maybeCheck() async {
    checkCount++;
  }
}

class _NoopUpdateClient extends UpdateClient {
  _NoopUpdateClient() : super(updateUrl: 'https://example.com/latest.json');
}

/// 恒返回新版本的客户端 fake（fetch 计数供抑制断言）。
class _NewerVersionClient extends UpdateClient {
  _NewerVersionClient() : super(updateUrl: 'https://example.com/latest.json');

  int fetchCount = 0;

  @override
  Future<AppUpdateInfo> fetchLatest() async {
    fetchCount++;
    return AppUpdateInfo(
      packageName: 'com.poemath.app',
      versionName: '2.0.0',
      versionCode: 200,
      tagName: 'v2.0.0',
      channel: 'stable',
      apkUrl: 'https://example.com/poemath.apk',
      apkSha256: 'a' * 64,
      apkSize: 4,
      mandatory: false,
      notes: '修复若干问题。',
    );
  }
}

/// 恒返回旧版本当前信息的安装器 fake（isAndroid: true → isSupported）。
class _OldVersionInstaller extends AndroidUpdateInstaller {
  _OldVersionInstaller() : super(isAndroid: true);

  @override
  Future<AppVersionInfo> getCurrentVersion() async => const AppVersionInfo(
    packageName: 'com.poemath.app',
    versionName: '1.0.0',
    versionCode: 100,
  );
}

GoRouter _router(UpdateCheckControllerFactory factory) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => MainShell(
          updateControllerFactory: factory,
          child: const Scaffold(body: Center(child: Text('tab-child'))),
        ),
      ),
    ],
  );
}

// MainShell 是 ConsumerStatefulWidget，dialog push 会触发其
// didChangeDependencies 重查容器——测试树须与生产同构地提供 ProviderScope。
Future<void> _pumpShell(
  WidgetTester tester,
  GoRouter router, {
  List<Override> overrides = const [],
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

void main() {
  // MainShell 现经 assistantEnabledProvider 读 settings box（默认关闭，不挂
  // 气泡），须先初始化 Hive 否则 build 抛 LateInitializationError。
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('有未完成任务时，主界面冷启动和返回前台均触发下载恢复', (tester) async {
    final book = textbookFixture();
    await tester.runAsync(
      () => TextbookDownloadRepository().markPending(book.pdfSha256),
    );
    final entry = TextbookCatalogEntry(
      book: book,
      downloadUrl: Uri.parse('https://example.com/sample.pdf'),
      sourceRepository: 'test/books',
      sourceCommit: 'a' * 40,
      sourcePath: 'sample.pdf',
      editionLabel: '合成测试',
      evidencePdfPages: const [1],
    );
    final downloads = _SpyDownloads();
    final router = _router((_) => _SpyUpdateController());
    addTearDown(router.dispose);
    await _pumpShell(
      tester,
      router,
      overrides: [
        textbookDownloadsProvider.overrideWith((ref) => downloads),
        textbookCatalogProvider.overrideWith((ref) async => [entry]),
      ],
    );
    await tester.pump();
    expect(downloads.restoredIds, [
      [book.pdfSha256],
    ]);
    expect(find.text('tab-child'), findsOneWidget);

    final binding = TestWidgetsFlutterBinding.instance;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(downloads.restoredIds, [
      [book.pdfSha256],
      [book.pdfSha256],
    ]);
    await drainHiveWritesForTesting(tester);
  });

  testWidgets('冷启动首帧后恰触发一次自动检测', (tester) async {
    final spy = _SpyUpdateController();
    final router = _router((_) => spy);
    addTearDown(router.dispose);

    await _pumpShell(tester, router);
    // postFrameCallback 在 pumpWidget 的帧末已执行。
    expect(spy.checkCount, 1);

    // 后续帧不重复触发。
    await tester.pump();
    expect(spy.checkCount, 1);

    expect(find.text('tab-child'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
  });

  testWidgets('前台恢复再次触发检测', (tester) async {
    final spy = _SpyUpdateController();
    final router = _router((_) => spy);
    addTearDown(router.dispose);

    await _pumpShell(tester, router);
    expect(spy.checkCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(spy.checkCount, 2);
  });

  testWidgets('销毁后不再接收生命周期回调且重新挂载无异常', (tester) async {
    final spy = _SpyUpdateController();
    final router = _router((_) => spy);
    addTearDown(router.dispose);

    await _pumpShell(tester, router);
    expect(spy.checkCount, 1);

    // 移除 MainShell（触发 dispose → removeObserver）。
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(spy.checkCount, 1);

    // 重新挂载新的 MainShell + 新控制器，正常工作。
    final spy2 = _SpyUpdateController();
    final router2 = _router((_) => spy2);
    addTearDown(router2.dispose);
    await _pumpShell(tester, router2);
    await tester.pump();
    expect(spy2.checkCount, 1);
    expect(find.text('tab-child'), findsOneWidget);
  });

  // 集成链路：真实 controller + MainShell 抑制分支（dismissed == false →
  // markDismissedByUser）。此前 3 个 spy 用例不经过 _onUpdateAvailable，
  // 该分支写反测试仍会全绿，故必须走工厂注入完整链路。
  testWidgets('弹窗取消后本进程内 resumed 不再自动检测（抑制分支集成）', (tester) async {
    final client = _NewerVersionClient();
    final installer = _OldVersionInstaller();
    final router = _router(
      (onAvailable) => UpdateCheckController(
        updateCheckConfigured: true,
        client: client,
        installer: installer,
        // 关闭时间间隔守卫：隔离出 dismissedByUser 是唯一拦截者。
        recheckInterval: Duration.zero,
        onAvailable: onAvailable,
      ),
    );
    addTearDown(router.dispose);

    await _pumpShell(tester, router);
    // 检测（fetch + 比较）完成 + 弹窗入场动画。
    await tester.pumpAndSettle();

    expect(client.fetchCount, 1);
    expect(find.text('发现新版本'), findsOneWidget);

    // 未开始下载直接取消 → pop(false) → markDismissedByUser。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsNothing);

    // resumed（时间守卫已 Duration.zero 放行）仍不再检测且不再弹窗。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(client.fetchCount, 1);
    expect(find.text('发现新版本'), findsNothing);
  });
}
