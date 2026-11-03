import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/profile/ai_settings_page.dart';
import 'package:poemath/features/profile/llm_provider_settings_page.dart';
import 'package:poemath/features/profile/parent_protection_page.dart';
import 'package:poemath/features/profile/profile_page.dart';
import 'package:poemath/features/profile/picture_story_detail_page.dart';
import 'package:poemath/features/profile/picture_story_editor_page.dart';
import 'package:poemath/features/profile/picture_story_management_page.dart';
import 'package:poemath/features/profile/picture_story_generate_page.dart';
import 'package:poemath/features/profile/image_generation_settings_page.dart';
import 'package:poemath/features/profile/settings_page.dart';
import 'package:poemath/features/profile/speech_recognition_settings_page.dart';
import 'package:poemath/features/textbook/textbook_course_review_page.dart';
import 'package:poemath/features/textbook/textbook_detail_page.dart';
import 'package:poemath/features/textbook/textbook_management_page.dart';

import '../../helpers/day_key_override.dart';
import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';

class _HeldStore extends SecureCredentialStore {
  String? record;
  int reads = 0;
  Completer<void>? nextRead;
  Completer<void>? readEntered;

  @override
  Future<String?> readParentProtection() async {
    reads++;
    final pending = nextRead;
    nextRead = null;
    readEntered?.complete();
    readEntered = null;
    await pending?.future;
    return record;
  }

  @override
  Future<void> saveParentProtection(String value) async => record = value;

  @override
  Future<void> deleteParentProtection() async => record = null;
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() completed) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!completed() && DateTime.now().isBefore(deadline)) {
    await tester.runAsync(() async {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
  }
  expect(completed(), isTrue, reason: '等待实际页面/操作完成');
  await tester.runAsync(() => tester.pump(const Duration(milliseconds: 400)));
}

Future<void> _drainFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 5; frame++) {
    await tester.runAsync(() async {
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
  }
}

Future<void> _background(WidgetTester tester) async {
  final binding = TestWidgetsFlutterBinding.instance;
  // 在 inactive 的最后可见帧检查锁定；paused 时 Flutter 已停止出帧。
  binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await _drainFrames(tester);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

Future<void> _foreground(WidgetTester tester) async {
  final binding = TestWidgetsFlutterBinding.instance;
  binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await _drainFrames(tester);
}

Finder get _unlockButton => find.widgetWithText(FilledButton, '解锁');
Finder get _setupButton => find.widgetWithText(FilledButton, '设置家长密码');

Future<void> _mount(
  WidgetTester tester,
  GoRouter router, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(router.dispose);
  addTearDown(() async {
    await tester.runAsync(() => tester.pumpWidget(const SizedBox.shrink()));
    await _drainFrames(tester);
  });
  await tester.runAsync(
    () => tester.pumpWidget(
      ProviderScope(
        overrides: [staticDayKeyOverride(), ...overrides],
        child: MaterialApp.router(routerConfig: router),
      ),
    ),
  );
  await _drainFrames(tester);
}

Future<void> _configurePin(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextField, '新的 6 位数字 PIN'),
    testParentPin,
  );
  await tester.enterText(
    find.widgetWithText(TextField, '再次输入 PIN'),
    testParentPin,
  );
  await tester.runAsync(() => tester.tap(_setupButton));
  await _pumpUntil(tester, () => find.text('保存一次性恢复码').evaluate().isNotEmpty);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final access = ParentAccessService.instance;

  setUp(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    FlutterSecureStorage.setMockInitialValues({});
    await setUpHiveForTesting();
    access.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await access.initialize();
    access.lock();
  });

  tearDown(() async {
    access.lock();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tearDownHiveForTesting();
  });

  for (final (location, pageType) in <(String, Type)>[
    (AppRoutes.settings, SettingsPage),
    (AppRoutes.llmSettings, LlmProviderSettingsPage),
    (AppRoutes.speechRecognitionSettings, SpeechRecognitionSettingsPage),
    (AppRoutes.textbookManagement, TextbookManagementPage),
    (AppRoutes.textbookManageDetailOf('synthetic'), TextbookDetailPage),
    (AppRoutes.textbookReviewOf('synthetic'), TextbookCourseReviewPage),
    (AppRoutes.pictureStoryManagement, PictureStoryManagementPage),
    (AppRoutes.pictureStoryCreate, PictureStoryEditorPage),
    (AppRoutes.pictureStoryGenerate, PictureStoryGeneratePage),
    (AppRoutes.imageGenerationSettings, ImageGenerationSettingsPage),
    (AppRoutes.pictureStoryDetailOf('synthetic'), PictureStoryDetailPage),
    (AppRoutes.pictureStoryEditOf('synthetic'), PictureStoryEditorPage),
  ]) {
    testWidgets('未设置密码的真实入口先到家长设置且目标未挂载：$location', (tester) async {
      var settingsReads = 0;
      final router = createAppRouter(initialLocation: location);
      await _mount(
        tester,
        router,
        overrides: [
          settingsRepositoryProvider.overrideWith((ref) {
            settingsReads++;
            return SettingsRepository();
          }),
        ],
      );
      await _pumpUntil(
        tester,
        () => find.byType(ParentProtectionPage).evaluate().isNotEmpty,
      );
      expect(router.routerDelegate.state.uri.path, AppRoutes.parentProtection);
      expect(find.byType(pageType, skipOffstage: false), findsNothing);
      expect(settingsReads, 0);
      expect(find.text('查看历史'), findsNothing);
      expect(find.textContaining('今日云请求用量'), findsNothing);
      expect(access.isUnlocked, isFalse);
      expect(access.assertAllowed, throwsA(isA<ParentAccessDenied>()));
    });
  }

  testWidgets('Navigator设置页未配置时先引导家长，确认后保留原导航页面', (tester) async {
    final router = createAppRouter(initialLocation: AppRoutes.profile);
    await _mount(tester, router);
    final profile = tester.element(find.byType(NavigationBar));
    await tester.runAsync(() async {
      unawaited(
        Navigator.of(profile, rootNavigator: true).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const ParentAccessBoundary(
              child: LlmProviderSettingsPage(),
            ),
          ),
        ),
      );
    });
    await _pumpUntil(
      tester,
      () => find.byType(ParentProtectionPage).evaluate().isNotEmpty,
    );
    expect(
      find.byType(LlmProviderSettingsPage, skipOffstage: false),
      findsNothing,
    );
    expect(access.isUnlocked, isFalse);
    await _configurePin(tester);
    expect(
      find.byType(LlmProviderSettingsPage, skipOffstage: false),
      findsNothing,
    );
    await tester.runAsync(() => tester.tap(find.text('我已保存')));
    await _pumpUntil(
      tester,
      () =>
          find.byType(LlmProviderSettingsPage).evaluate().isNotEmpty &&
          find.byType(ParentProtectionPage).evaluate().isEmpty,
    );
    expect(router.routerDelegate.state.uri.path, AppRoutes.profile);
    await tester.runAsync(() => tester.pageBack());
    await _pumpUntil(
      tester,
      () =>
          find.byType(LlmProviderSettingsPage).evaluate().isEmpty &&
          find.byType(NavigationBar).evaluate().isNotEmpty,
    );
    expect(find.byType(LlmProviderSettingsPage), findsNothing);
  });

  testWidgets('首次设置校验确认PIN，保存恢复码后回到原设置入口', (tester) async {
    final router = createAppRouter(initialLocation: AppRoutes.settings);
    await _mount(tester, router);
    await _pumpUntil(
      tester,
      () => find.byType(ParentProtectionPage).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.widgetWithText(TextField, '新的 6 位数字 PIN'),
      testParentPin,
    );
    await tester.enterText(
      find.widgetWithText(TextField, '再次输入 PIN'),
      '123456',
    );
    await tester.tap(_setupButton);
    await tester.pump();
    expect(find.text('请输入两次相同的 6 位数字 PIN'), findsOneWidget);
    expect(access.enabled, isFalse);
    await _configurePin(tester);
    expect(find.byType(SettingsPage, skipOffstage: false), findsNothing);
    await tester.runAsync(() => tester.tap(find.text('我已保存')));
    await _pumpUntil(
      tester,
      () =>
          find.byType(SettingsPage).evaluate().isNotEmpty &&
          find.byType(ParentProtectionPage).evaluate().isEmpty,
    );
    expect(router.routerDelegate.state.uri.path, AppRoutes.settings);
    expect(find.byType(ParentProtectionPage), findsNothing);
    expect(access.isUnlocked, isTrue);
    await tester.runAsync(() => tester.tap(find.text('AI 与语音')));
    await _pumpUntil(tester, () => find.text('AI 设置').evaluate().isNotEmpty);
    await tester.runAsync(() => tester.tap(find.text('AI 设置')));
    await _pumpUntil(
      tester,
      () => find.byType(AiSettingsPage).evaluate().isNotEmpty,
    );
    expect(_unlockButton, findsNothing);
  });

  testWidgets('直接访问家长设置只开放首次PIN，配置确认后留在家长页', (tester) async {
    final router = createAppRouter(initialLocation: AppRoutes.parentProtection);
    await _mount(tester, router);
    await _pumpUntil(
      tester,
      () => find.byType(ParentProtectionPage).evaluate().isNotEmpty,
    );
    expect(find.text('查看历史'), findsNothing);
    await _configurePin(tester);
    await tester.runAsync(() => tester.tap(find.text('我已保存')));
    await _drainFrames(tester);
    expect(router.routerDelegate.state.uri.path, AppRoutes.parentProtection);
    expect(find.byType(ParentProtectionPage), findsOneWidget);
    expect(find.text('查看历史'), findsOneWidget);
  });

  testWidgets('取消首次配置回到锁定入口，不自动循环，重试只推一个家长页', (tester) async {
    final router = createAppRouter(initialLocation: AppRoutes.llmSettings);
    await _mount(tester, router);
    await _pumpUntil(
      tester,
      () => find.byType(ParentProtectionPage).evaluate().isNotEmpty,
    );
    await tester.runAsync(() => tester.pageBack());
    await _drainFrames(tester);
    expect(router.routerDelegate.state.uri.path, AppRoutes.llmSettings);
    expect(
      find.byType(ParentProtectionPage, skipOffstage: false),
      findsNothing,
    );
    expect(
      find.byType(LlmProviderSettingsPage, skipOffstage: false),
      findsNothing,
    );
    await tester.runAsync(() async {
      await tester.tap(_setupButton);
      await tester.tap(_setupButton);
    });
    await _pumpUntil(
      tester,
      () => find.byType(ParentProtectionPage).evaluate().isNotEmpty,
    );
    expect(
      find.byType(ParentProtectionPage, skipOffstage: false),
      findsOneWidget,
    );
    await tester.runAsync(() => tester.pageBack());
    await _drainFrames(tester);
    expect(router.routerDelegate.state.uri.path, AppRoutes.llmSettings);
  });

  testWidgets('取消验证返回我的，错误PIN保持锁定，正确PIN跨设置复用15分钟窗口', (tester) async {
    await tester.runAsync(unlockParentForTesting);
    access.lock();
    final router = createAppRouter(initialLocation: AppRoutes.settings);
    await _mount(tester, router);
    await _pumpUntil(tester, () => _unlockButton.evaluate().isNotEmpty);
    await tester.enterText(
      find.widgetWithText(TextField, '6 位数字 PIN'),
      '000000',
    );
    await tester.runAsync(() => tester.tap(_unlockButton));
    await _pumpUntil(tester, () => find.text('PIN 不正确').evaluate().isNotEmpty);
    expect(find.byType(SettingsPage, skipOffstage: false), findsNothing);
    await tester.runAsync(() => tester.tap(find.text('取消')));
    await _drainFrames(tester);
    expect(router.routerDelegate.state.uri.path, AppRoutes.profile);
    expect(access.isUnlocked, isFalse);
    expect(find.byType(SettingsPage, skipOffstage: false), findsNothing);
    await tester.runAsync(() async {
      unawaited(router.push<void>(AppRoutes.settings));
    });
    await _pumpUntil(tester, () => _unlockButton.evaluate().isNotEmpty);
    await tester.enterText(
      find.widgetWithText(TextField, '6 位数字 PIN'),
      testParentPin,
    );
    await tester.runAsync(() => tester.tap(_unlockButton));
    await _pumpUntil(
      tester,
      () => find.byType(SettingsPage).evaluate().isNotEmpty,
    );
    await tester.runAsync(() => tester.tap(find.text('AI 与语音')));
    await _pumpUntil(tester, () => find.text('语音识别设置').evaluate().isNotEmpty);
    expect(_unlockButton, findsNothing);
    await tester.runAsync(() => tester.pageBack());
    await _drainFrames(tester);
    await tester.runAsync(() => tester.tap(find.text('家长与数据')));
    await _pumpUntil(
      tester,
      () => find.text('家长保护与云额度').evaluate().isNotEmpty,
    );
    expect(_unlockButton, findsNothing);
    await tester.runAsync(() => tester.pageBack());
    await _drainFrames(tester);
    await tester.runAsync(() => tester.tap(find.text('AI 与语音')));
    await _pumpUntil(tester, () => find.text('AI 设置').evaluate().isNotEmpty);
    await tester.runAsync(() => tester.tap(find.text('AI 设置')));
    await _pumpUntil(
      tester,
      () => find.byType(AiSettingsPage).evaluate().isNotEmpty,
    );
    expect(_unlockButton, findsNothing);
    await tester.runAsync(() => tester.tap(find.text('供应商设置')));
    await _pumpUntil(
      tester,
      () => find.byType(LlmProviderSettingsPage).evaluate().isNotEmpty,
    );
    expect(_unlockButton, findsNothing);
  });

  testWidgets('多层设置与AI出题授权失效后只验证一次，取消直接返回我的', (tester) async {
    await tester.runAsync(unlockParentForTesting);
    final router = createAppRouter(initialLocation: AppRoutes.profile);
    await _mount(tester, router);
    await tester.runAsync(() => tester.tap(find.byTooltip('设置')));
    await _pumpUntil(tester, () => find.text('学习与内容').evaluate().isNotEmpty);
    await tester.runAsync(() => tester.tap(find.text('学习与内容')));
    await _pumpUntil(tester, () => find.text('看图说话题库').evaluate().isNotEmpty);
    await tester.runAsync(() => tester.tap(find.text('看图说话题库')));
    await _pumpUntil(
      tester,
      () => find.byType(PictureStoryManagementPage).evaluate().isNotEmpty,
    );
    await tester.runAsync(() => tester.tap(find.byTooltip('AI 出题')));
    await _pumpUntil(
      tester,
      () => find.byType(PictureStoryGeneratePage).evaluate().isNotEmpty,
    );
    expect(_unlockButton, findsNothing);
    expect(find.byType(Slider), findsOneWidget);
    // 精确15分钟边界由服务测试验证；失效通知沿用同一 lock() 路径。
    await tester.runAsync(() async => access.lock());
    await _pumpUntil(tester, () => _unlockButton.evaluate().isNotEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.byType(PictureStoryGeneratePage, skipOffstage: false),
      findsNothing,
    );
    await tester.runAsync(() => tester.tap(find.text('取消')));
    await _drainFrames(tester);
    expect(router.routerDelegate.state.uri.path, AppRoutes.profile);
    expect(find.byType(ProfilePage), findsOneWidget);
    expect(
      find.byType(ParentAccessBoundary, skipOffstage: false),
      findsNothing,
    );
    expect(find.byType(SettingsPage, skipOffstage: false), findsNothing);
    expect(
      find.byType(PictureStoryManagementPage, skipOffstage: false),
      findsNothing,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(router.canPop(), isFalse);
    expect(access.isUnlocked, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final navigatorPush in [false, true]) {
    testWidgets(
        '${navigatorPush ? 'Navigator' : 'GoRouter'}子页复用有效授权，首帧不显示保护页且不重复读取安全存储',
        (tester) async {
      final store = _HeldStore();
      final controlled = ParentAccessService(store: store);
      addTearDown(controlled.dispose);
      await tester.runAsync(() async {
        await controlled.configure(testParentPin);
        controlled.lock();
        expect(await controlled.authenticate(testParentPin), isTrue);
      });
      var authorizedActions = 0;
      Widget childPage() => ParentAccessBoundary(
            service: controlled,
            child: Builder(
              builder: (context) => Scaffold(
                appBar: AppBar(title: const Text('真实子页面')),
                body: FilledButton(
                  onPressed: () async {
                    if (await ensureParentAccess(
                      context,
                      service: controlled,
                    )) {
                      authorizedActions++;
                    }
                  },
                  child: const Text('管理操作'),
                ),
              ),
            ),
          );

      final router = GoRouter(
        initialLocation: AppRoutes.settings,
        routes: [
          GoRoute(
            path: AppRoutes.settings,
            builder: (_, state) => ParentAccessBoundary(
              service: controlled,
              child: Builder(
                builder: (context) => Scaffold(
                  appBar: AppBar(title: const Text('已解锁的设置')),
                  body: FilledButton(
                    onPressed: () {
                      if (navigatorPush) {
                        unawaited(
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => childPage(),
                            ),
                          ),
                        );
                      } else {
                        unawaited(context.push<void>(AppRoutes.llmSettings));
                      }
                    },
                    child: const Text('进入子页'),
                  ),
                ),
              ),
            ),
          ),
          GoRoute(
            path: AppRoutes.llmSettings,
            builder: (_, state) => childPage(),
          ),
        ],
      );
      await _mount(tester, router);
      final readsBeforeNavigation = store.reads;
      final release = Completer<void>();
      store.nextRead = release;
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });

      await tester.runAsync(() => tester.tap(find.text('进入子页')));
      await tester.runAsync(() => tester.pump());
      expect(
        find.byType(ParentAccessBoundary, skipOffstage: false),
        findsNWidgets(2),
      );
      expect(find.text('真实子页面', skipOffstage: false), findsOneWidget);
      expect(find.text('家长保护', skipOffstage: false), findsNothing);
      expect(store.reads, readsBeforeNavigation);

      // 安全存储即使两秒后仍未响应，也不应阻塞仍有效的授权。
      await tester.runAsync(() => tester.pump(const Duration(seconds: 2)));
      await tester.runAsync(() => tester.tap(find.text('管理操作')));
      await _drainFrames(tester);
      expect(find.text('真实子页面'), findsOneWidget);
      expect(authorizedActions, 1);
      expect(store.reads, readsBeforeNavigation);
      expect(find.text('家长保护', skipOffstage: false), findsNothing);
      expect(controlled.isUnlocked, isTrue);
    });
  }

  testWidgets('授权精确到期后新页面重新验证，读取期间不挂载管理内容', (tester) async {
    final store = _HeldStore();
    var now = DateTime(2026, 11, 3, 10);
    final controlled = ParentAccessService(store: store, clock: () => now);
    addTearDown(controlled.dispose);
    await tester.runAsync(() => controlled.configure(testParentPin));
    expect(controlled.isUnlocked, isTrue);
    now = now.add(ParentAccessService.unlockDuration);
    expect(controlled.isUnlocked, isFalse);

    final release = Completer<void>();
    final entered = Completer<void>();
    store.nextRead = release;
    store.readEntered = entered;
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final router = GoRouter(
      initialLocation: AppRoutes.llmSettings,
      routes: [
        GoRoute(
          path: AppRoutes.llmSettings,
          builder: (_, state) => ParentAccessBoundary(
            service: controlled,
            child: const Scaffold(body: Text('已过期授权不能查看的管理内容')),
          ),
        ),
      ],
    );
    await _mount(tester, router);
    expect(entered.isCompleted, isTrue);
    expect(
      find.text('已过期授权不能查看的管理内容', skipOffstage: false),
      findsNothing,
    );
    await tester.runAsync(() async => release.complete());
    await _pumpUntil(tester, () => _unlockButton.evaluate().isNotEmpty);
    expect(controlled.isUnlocked, isFalse);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text('已过期授权不能查看的管理内容', skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('一次性恢复码只进入重设，保持原目标锁定且不会误退底层页', (tester) async {
    final recovery = await tester.runAsync(unlockParentForTesting);
    access.lock();
    final router = createAppRouter(initialLocation: AppRoutes.llmSettings);
    await _mount(tester, router);
    await _pumpUntil(tester, () => _unlockButton.evaluate().isNotEmpty);
    await tester.tap(find.text('忘记 PIN，使用恢复码'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, '恢复码'), recovery!);
    await tester.runAsync(() => tester.tap(_unlockButton));
    await _pumpUntil(
      tester,
      () => find.byType(ParentProtectionPage).evaluate().isNotEmpty,
    );
    expect(router.routerDelegate.state.uri.path, AppRoutes.parentProtection);
    expect(access.enabled, isFalse);
    expect(access.isUnlocked, isFalse);
    expect(
      find.byType(LlmProviderSettingsPage, skipOffstage: false),
      findsNothing,
    );
    await tester.runAsync(() => tester.pageBack());
    await _drainFrames(tester);
    expect(router.routerDelegate.state.uri.path, AppRoutes.llmSettings);
    expect(
      find.byType(LlmProviderSettingsPage, skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('修改家长密码保持保护生效，新PIN与恢复码替换旧凭据', (tester) async {
    final oldRecovery = (await tester.runAsync(unlockParentForTesting))!;
    const newPin = '135790';
    final router = createAppRouter(initialLocation: AppRoutes.settings);
    await _mount(tester, router);
    await _pumpUntil(
      tester,
      () => find.byType(SettingsPage).evaluate().isNotEmpty,
    );
    await tester.runAsync(() => tester.tap(find.text('家长与数据')));
    await _pumpUntil(
      tester,
      () => find.text('家长保护与云额度').evaluate().isNotEmpty,
    );
    await tester.runAsync(() => tester.tap(find.text('家长保护与云额度')));
    await _pumpUntil(
      tester,
      () => find.byType(ParentProtectionPage).evaluate().isNotEmpty,
    );
    expect(find.text('移除家长密码'), findsNothing);
    expect(
      find.widgetWithText(TextField, '新的 6 位数字 PIN'),
      findsNothing,
    );
    await tester.runAsync(() => tester.tap(find.byTooltip('修改家长密码')));
    await _pumpUntil(
      tester,
      () => find.widgetWithText(AlertDialog, '修改家长密码').evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.widgetWithText(TextField, '新的 6 位数字 PIN'),
      newPin,
    );
    await tester.enterText(
      find.widgetWithText(TextField, '再次输入 PIN'),
      testParentPin,
    );
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(FilledButton, '保存')),
    );
    await _pumpUntil(
      tester,
      () => find.text('请输入两次相同的 6 位数字 PIN').evaluate().isNotEmpty,
    );
    expect(find.text('保存一次性恢复码'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, '再次输入 PIN'),
      newPin,
    );
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(FilledButton, '保存')),
    );
    await _pumpUntil(
      tester,
      () => find.text('保存一次性恢复码').evaluate().isNotEmpty,
    );
    final newRecovery = tester
        .widget<SelectableText>(
          find.descendant(
            of: find.widgetWithText(AlertDialog, '保存一次性恢复码'),
            matching: find.byType(SelectableText),
          ),
        )
        .data!;
    expect(newRecovery, isNot(oldRecovery));
    await tester.runAsync(() => tester.tap(find.text('我已保存')));
    await _pumpUntil(
      tester,
      () => find.text('保存一次性恢复码').evaluate().isEmpty,
    );
    expect(access.enabled, isTrue);
    expect(access.isUnlocked, isTrue);
    await tester.runAsync(() => tester.pageBack());
    await _pumpUntil(
      tester,
      () => find.byType(SettingsPage).evaluate().isNotEmpty,
    );
    // 退出页面后，用新旧凭据检查实际保存结果。
    await tester.runAsync(() => tester.pumpWidget(const SizedBox.shrink()));
    await _drainFrames(tester);
    await tester.runAsync(() async {
      access.lock();
      expect(await access.authenticate(testParentPin), isFalse);
      expect(await access.authenticate(oldRecovery, recovery: true), isFalse);
      expect(access.enabled, isTrue);
      expect(await access.authenticate(newPin), isTrue);
      access.lock();
      expect(await access.authenticate(newRecovery, recovery: true), isTrue);
    });
    expect(access.enabled, isFalse);
    expect(access.isUnlocked, isFalse);
    expect(access.canSetPin, isTrue);
  });

  testWidgets('修改密码弹窗取消或提交后立即转后台都保留原凭据', (tester) async {
    await tester.runAsync(unlockParentForTesting);
    final store = SecureCredentialStore();
    final oldRecord = (await tester.runAsync(store.readParentProtection))!;
    const newPin = '135790';
    final router = createAppRouter(initialLocation: AppRoutes.parentProtection);
    await _mount(tester, router);
    await _pumpUntil(
      tester,
      () => find.byType(ParentProtectionPage).evaluate().isNotEmpty,
    );
    // 在窄屏上同时检查输入弹窗与导航图标仍可操作。
    tester.view.physicalSize = const Size(360, 640);
    await _drainFrames(tester);
    await tester.runAsync(() => tester.tap(find.byTooltip('修改家长密码')));
    await _pumpUntil(
      tester,
      () => find.widgetWithText(AlertDialog, '修改家长密码').evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.widgetWithText(TextField, '新的 6 位数字 PIN'),
      newPin,
    );
    await tester.enterText(
      find.widgetWithText(TextField, '再次输入 PIN'),
      newPin,
    );
    await tester.runAsync(() => tester.tap(find.text('取消')));
    await _pumpUntil(tester, () => find.byType(AlertDialog).evaluate().isEmpty);
    expect(await tester.runAsync(store.readParentProtection), oldRecord);
    expect(access.enabled, isTrue);
    expect(access.isUnlocked, isTrue);

    await tester.runAsync(() => tester.tap(find.byTooltip('修改家长密码')));
    await _pumpUntil(
      tester,
      () => find.widgetWithText(AlertDialog, '修改家长密码').evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.widgetWithText(TextField, '新的 6 位数字 PIN'),
      newPin,
    );
    await tester.enterText(
      find.widgetWithText(TextField, '再次输入 PIN'),
      newPin,
    );
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(FilledButton, '保存')),
    );
    await _background(tester);
    await _drainFrames(tester);
    expect(await tester.runAsync(store.readParentProtection), oldRecord);
    expect(access.enabled, isTrue);
    expect(access.isUnlocked, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.byType(ParentProtectionPage, skipOffstage: false),
      findsNothing,
    );

    await _foreground(tester);
    await tester
        .runAsync(() => tester.tap(find.widgetWithText(FilledButton, '家长解锁')));
    await _pumpUntil(tester, () => _unlockButton.evaluate().isNotEmpty);
    await tester.enterText(
      find.widgetWithText(TextField, '6 位数字 PIN'),
      testParentPin,
    );
    await tester.runAsync(() => tester.tap(_unlockButton));
    await _pumpUntil(
      tester,
      () => find.byType(ParentProtectionPage).evaluate().isNotEmpty,
    );
    expect(access.isUnlocked, isTrue);
    expect(find.byTooltip('修改家长密码'), findsOneWidget);
    expect(find.text('保存一次性恢复码'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('在家长设置页使用恢复码只切换为重设，不叠加自身路由', (tester) async {
    final recovery = await tester.runAsync(unlockParentForTesting);
    access.lock();
    final router = createAppRouter(initialLocation: AppRoutes.parentProtection);
    await _mount(tester, router);
    await _pumpUntil(tester, () => _unlockButton.evaluate().isNotEmpty);
    await tester.tap(find.text('忘记 PIN，使用恢复码'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, '恢复码'), recovery!);
    await tester.runAsync(() => tester.tap(_unlockButton));
    await _pumpUntil(
      tester,
      () => find.byType(ParentProtectionPage).evaluate().isNotEmpty,
    );
    expect(router.routerDelegate.currentConfiguration.matches, hasLength(1));
    expect(
      find.byType(ParentProtectionPage, skipOffstage: false),
      findsOneWidget,
    );
    expect(access.isUnlocked, isFalse);
    expect(find.text('查看历史'), findsNothing);
  });

  for (final configured in [false, true]) {
    testWidgets('安全记录损坏时${configured ? '已设置' : '首次设置'}入口保持锁定，可重试缺失记录',
        (tester) async {
      if (configured) await tester.runAsync(unlockParentForTesting);
      // 损坏记录模拟新一轮验证；已验证且未过期的会话在跨页时复用。
      access.lock();
      FlutterSecureStorage.setMockInitialValues({'parent_protection': '{}'});
      final router = createAppRouter(initialLocation: AppRoutes.settings);
      await _mount(tester, router);
      await _pumpUntil(
        tester,
        () => find.widgetWithText(FilledButton, '重试').evaluate().isNotEmpty,
      );
      expect(find.byType(SettingsPage, skipOffstage: false), findsNothing);
      expect(
        find.byType(ParentProtectionPage, skipOffstage: false),
        findsNothing,
      );
      expect(access.isUnlocked, isFalse);
      expect(access.canSetPin, isFalse);
      expect(access.needsResetNotice, isFalse);
      FlutterSecureStorage.setMockInitialValues({});
      await tester
          .runAsync(() => tester.tap(find.widgetWithText(FilledButton, '重试')));
      await _pumpUntil(
        tester,
        () => find.byType(ParentProtectionPage).evaluate().isNotEmpty,
      );
      expect(access.enabled, isFalse);
      expect(access.isUnlocked, isFalse);
      expect(access.needsResetNotice, configured);
    });
  }

  testWidgets('迁移确认缺少摘要时直接重设，设置成功前目标仍未挂载', (tester) async {
    await tester.runAsync(
      () => HiveBoxes.settings.put('parent_protection_enabled', true),
    );
    final router = createAppRouter(initialLocation: AppRoutes.settings);
    await _mount(tester, router);
    await _pumpUntil(
      tester,
      () => find.byType(ParentProtectionPage).evaluate().isNotEmpty,
    );
    expect(access.needsResetNotice, isTrue);
    expect(find.byType(SettingsPage, skipOffstage: false), findsNothing);
    expect(access.isUnlocked, isFalse);
    await _configurePin(tester);
    await tester.runAsync(() => tester.tap(find.text('我已保存')));
    await _pumpUntil(
      tester,
      () => find.byType(SettingsPage).evaluate().isNotEmpty,
    );
    expect(access.needsResetNotice, isFalse);
  });

  testWidgets('后台立即移除设置内容和弹窗，返回前台需要重新验证', (tester) async {
    await tester.runAsync(unlockParentForTesting);
    final router = createAppRouter(initialLocation: AppRoutes.settings);
    await _mount(tester, router);
    await _pumpUntil(
      tester,
      () => find.byType(SettingsPage).evaluate().isNotEmpty,
    );
    final context = tester.element(find.byType(SettingsPage));
    await tester.runAsync(() async {
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(title: Text('有待保存的设置')),
        ),
      );
    });
    await _drainFrames(tester);
    expect(find.text('有待保存的设置'), findsOneWidget);
    await _background(tester);
    await _drainFrames(tester);
    expect(find.byType(SettingsPage, skipOffstage: false), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await _foreground(tester);
    await _drainFrames(tester);
    await tester
        .runAsync(() => tester.tap(find.widgetWithText(FilledButton, '家长解锁')));
    await _pumpUntil(tester, () => _unlockButton.evaluate().isNotEmpty);
    expect(find.byType(SettingsPage, skipOffstage: false), findsNothing);
  });

  testWidgets('首次恢复码确认中后台锁定后，家长页可重新验证并返回原目标', (tester) async {
    final router = createAppRouter(initialLocation: AppRoutes.settings);
    await _mount(tester, router);
    await _pumpUntil(
      tester,
      () => find.byType(ParentProtectionPage).evaluate().isNotEmpty,
    );
    await _configurePin(tester);
    await _background(tester);
    await _drainFrames(tester);
    expect(find.text('保存一次性恢复码'), findsNothing);
    expect(
      find.byType(ParentProtectionPage, skipOffstage: false),
      findsNothing,
    );
    expect(find.byType(SettingsPage, skipOffstage: false), findsNothing);
    await _foreground(tester);
    await tester
        .runAsync(() => tester.tap(find.widgetWithText(FilledButton, '家长解锁')));
    await _pumpUntil(tester, () => _unlockButton.evaluate().isNotEmpty);
    await tester.enterText(
      find.widgetWithText(TextField, '6 位数字 PIN'),
      testParentPin,
    );
    await tester.runAsync(() => tester.tap(_unlockButton));
    await _pumpUntil(
      tester,
      () => find.byType(ParentProtectionPage).evaluate().isNotEmpty,
    );
    await tester.runAsync(() => tester.pageBack());
    await _pumpUntil(
      tester,
      () => find.byType(SettingsPage).evaluate().isNotEmpty,
    );
    expect(router.routerDelegate.state.uri.path, AppRoutes.settings);
  });

  testWidgets('后台关闭验证弹窗后晚到结果不会再弹出或误退底层路由', (tester) async {
    final store = _HeldStore();
    final controlled = ParentAccessService(store: store);
    addTearDown(controlled.dispose);
    await tester.runAsync(() => controlled.configure(testParentPin));
    controlled.lock();
    final router = GoRouter(
      initialLocation: AppRoutes.settings,
      routes: [
        GoRoute(
          path: AppRoutes.settings,
          builder: (_, state) => ParentAccessBoundary(
            service: controlled,
            child: const Scaffold(body: Text('受保护的编辑内容')),
          ),
        ),
      ],
    );
    await _mount(tester, router);
    await _pumpUntil(tester, () => _unlockButton.evaluate().isNotEmpty);
    final release = Completer<void>();
    final entered = Completer<void>();
    store.nextRead = release;
    store.readEntered = entered;
    await tester.enterText(
      find.widgetWithText(TextField, '6 位数字 PIN'),
      testParentPin,
    );
    await tester.runAsync(() => tester.tap(_unlockButton));
    await _pumpUntil(tester, () => entered.isCompleted);
    await _background(tester);
    await _drainFrames(tester);
    await _foreground(tester);
    await tester.runAsync(() async => release.complete());
    await _drainFrames(tester);
    expect(router.routerDelegate.state.uri.path, AppRoutes.settings);
    expect(controlled.isUnlocked, isFalse);
    expect(find.text('受保护的编辑内容', skipOffstage: false), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未设置PIN时儿童书籍详情仍能独立打开', (tester) async {
    final router = createAppRouter(
      initialLocation: AppRoutes.textbookDetailOf('synthetic-child'),
    );
    await _mount(tester, router);
    await _pumpUntil(
      tester,
      () => find.byType(TextbookDetailPage).evaluate().isNotEmpty,
    );
    expect(find.byType(ParentProtectionPage), findsNothing);
    expect(_unlockButton, findsNothing);
    expect(access.enabled, isFalse);
  });

  testWidgets('验证等待时离开再进入设置，旧页面的结果不能跳过新验证', (tester) async {
    final store = _HeldStore();
    final controlled = ParentAccessService(store: store);
    addTearDown(controlled.dispose);
    await tester.runAsync(() => controlled.configure(testParentPin));
    controlled.lock();
    final router = GoRouter(
      initialLocation: AppRoutes.settings,
      routes: [
        GoRoute(
          path: AppRoutes.settings,
          builder: (_, state) => ParentAccessBoundary(
            service: controlled,
            child: const Scaffold(body: Text('受保护的编辑内容')),
          ),
        ),
        GoRoute(
          path: AppRoutes.profile,
          builder: (_, state) => const Scaffold(body: Text('个人页')),
        ),
      ],
    );
    await _mount(tester, router);
    await _pumpUntil(tester, () => _unlockButton.evaluate().isNotEmpty);
    final release = Completer<void>();
    final entered = Completer<void>();
    store.nextRead = release;
    store.readEntered = entered;
    await tester.enterText(
      find.widgetWithText(TextField, '6 位数字 PIN'),
      testParentPin,
    );
    await tester.runAsync(() => tester.tap(_unlockButton));
    await _pumpUntil(tester, () => entered.isCompleted);
    router.go(AppRoutes.profile);
    await _pumpUntil(tester, () => find.text('个人页').evaluate().isNotEmpty);
    router.go(AppRoutes.settings);
    await _drainFrames(tester);
    await tester.runAsync(() async => release.complete());
    await _pumpUntil(tester, () => _unlockButton.evaluate().isNotEmpty);
    expect(controlled.isUnlocked, isFalse);
    expect(find.text('受保护的编辑内容', skipOffstage: false), findsNothing);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(router.routerDelegate.state.uri.path, AppRoutes.settings);
  });
}
