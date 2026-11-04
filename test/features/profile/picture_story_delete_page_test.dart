import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/cache_activity.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_tile.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/profile/picture_story_detail_page.dart';
import 'package:poemath/features/profile/picture_story_management_page.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';
import '../../helpers/picture_story_fixture.dart';

class _Repository extends PictureStoryRepository {
  _Repository(this.ioZone);

  final Zone ioZone;
  Future<void>? lastDelete;
  Completer<void>? deleteGate;
  var deleteCalls = 0;
  bool failNextDelete = false;
  bool failNextImageCleanup = false;

  @override
  Future<void> deletePrompt({
    required PictureStoryPrompt prompt,
    required String profileId,
  }) {
    deleteCalls++;
    // 排队回调固定在 setUp 的真实异步域，避免共享队列留在已结束的 FakeAsync 中。
    return lastDelete = _runIo<void>(() async {
      await deleteGate?.future;
      if (failNextDelete) {
        failNextDelete = false;
        throw HiveError('模拟删除写入失败');
      }
      await super.deletePrompt(prompt: prompt, profileId: profileId);
      if (failNextImageCleanup) {
        failNextImageCleanup = false;
        throw PictureStoryImageCleanupException(HiveError('模拟题图清理失败'));
      }
    });
  }

  @override
  Future<PictureStoryPrompt> savePrompt({
    required PictureStoryPrompt prompt,
    required String profileId,
    PictureStoryPrompt? original,
    bool enableForProfile = true,
  }) {
    return _runIo<PictureStoryPrompt>(
      () => super.savePrompt(
        prompt: prompt,
        profileId: profileId,
        original: original,
        enableForProfile: enableForProfile,
      ),
    );
  }

  Future<T> _runIo<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    // 仓储队列运行在真实 IO 域；成功或失败回送调用者，跨 error zone 不丢失异常。
    unawaited(
      ioZone.run(() async {
        try {
          result.complete(await operation());
        } on Object catch (error, stackTrace) {
          result.completeError(error, stackTrace);
        }
      }),
    );
    return result.future;
  }
}

void main() {
  late _Repository repository;
  final prompts = List.generate(
    3,
    (index) => pictureStoryFixture(
      id: 'local-delete-${index + 1}',
      title: '已保存的题目 ${index + 1}',
    ),
  );

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    await unlockParentForTesting();
    repository = _Repository(Zone.current);
    for (final prompt in prompts) {
      await repository.savePrompt(prompt: prompt, profileId: 'default');
    }
  });
  tearDown(() async {
    lockParentForTesting();
    ProfileScope.reset();
    await tearDownHiveForWidgetTesting();
  });

  Future<(GoRouter, ProviderContainer)> pumpFlow(
    WidgetTester tester, {
    String location = AppRoutes.pictureStoryManagement,
    Size size = const Size(420, 900),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [pictureStoryRepositoryProvider.overrideWithValue(repository)],
    );
    final router = createAppRouter(initialLocation: location);
    addTearDown(container.dispose);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.resolve(
            subject: AppSubject.poem,
            brightness: Brightness.light,
          ),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (router, container);
  }

  Future<void> openPrompt(
    WidgetTester tester,
    PictureStoryPrompt prompt,
  ) async {
    await tester.tap(find.widgetWithText(AppTile, prompt.title));
    await tester.pumpAndSettle();
    expect(find.byType(PictureStoryDetailPage), findsOneWidget);
  }

  Future<void> openDelete(WidgetTester tester) async {
    await tester.runAsync(() => tester.tap(find.byTooltip('删除题目')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  }

  Future<void> confirmDelete(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await repository.lastDelete!.timeout(const Duration(seconds: 5));
    });
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await drainHiveWritesForTesting(tester);
  }

  testWidgets('真实题库详情可取消删除，确认后返回题库并刷新启用数量', (tester) async {
    final (router, container) = await pumpFlow(tester);
    final prompt = prompts.first;
    final before = repository.storageSnapshot();
    await openPrompt(tester, prompt);
    await openDelete(tester);
    expect(
      find.text('「${prompt.title}」将从所有孩子的题库中移除，并清理不再使用的题图。练习历史及其题图会保留。'),
      findsOneWidget,
    );
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(TextButton, '取消')),
    );
    await tester.pumpAndSettle();
    expect(repository.deleteCalls, 0);
    expect(repository.storageSnapshot(), before);
    expect(
      router.routerDelegate.state.uri.path,
      AppRoutes.pictureStoryDetailOf(prompt.id),
    );
    await openDelete(tester);
    await confirmDelete(tester);
    expect(
      router.routerDelegate.state.uri.path,
      AppRoutes.pictureStoryManagement,
    );
    expect(find.byType(PictureStoryManagementPage), findsOneWidget);
    expect(find.widgetWithText(AppTile, prompt.title), findsNothing);
    expect(find.text('题目已删除'), findsOneWidget);
    expect(container.read(pictureStoryPromptCountProvider), 2);
    expect(repository.findPrompt(prompt.id), isNull);
    expect(
      repository.findPrompt(prompt.id, version: prompt.version)!.toJson(),
      prompt.toJson(),
    );
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('删除写入失败保留题目并提示，按钮恢复后可重试', (tester) async {
    final prompt = prompts.first;
    await pumpFlow(tester, location: AppRoutes.pictureStoryDetailOf(prompt.id));
    repository.failNextDelete = true;
    await openDelete(tester);
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await expectLater(repository.lastDelete!, throwsA(isA<HiveError>()));
    });
    await tester.pumpAndSettle();
    expect(find.text('题目没有删除，请重试'), findsOneWidget);
    expect(repository.findPrompt(prompt.id), isNotNull);
    expect(tester.takeException(), isNull);
    await openDelete(tester);
    await confirmDelete(tester);
    expect(repository.findPrompt(prompt.id), isNull);
    expect(repository.deleteCalls, 2);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('题图清理失败仍返回题库，如实提示题目已删除', (tester) async {
    final (router, _) = await pumpFlow(tester);
    final prompt = prompts.first;
    repository.failNextImageCleanup = true;
    await openPrompt(tester, prompt);
    await openDelete(tester);
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await expectLater(
        repository.lastDelete!,
        throwsA(isA<PictureStoryImageCleanupException>()),
      );
    });
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.state.uri.path,
      AppRoutes.pictureStoryManagement,
    );
    expect(repository.findPrompt(prompt.id), isNull);
    expect(find.text('题目已删除，题图清理未完成'), findsOneWidget);
    expect(find.text('题目没有删除，请重试'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('题图正在导入时取消删除并显示稍后重试，释放租约后可正常删除', (tester) async {
    await pumpFlow(tester);
    final prompt = prompts.first;
    await openPrompt(tester, prompt);
    await openDelete(tester);
    final gate = Completer<void>();
    final active = CacheActivity.use(
      TemporaryCacheKind.pictureStoryImages,
      () => gate.future,
    );
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await expectLater(
        repository.lastDelete!,
        throwsA(isA<CacheInUseException>()),
      );
    });
    await tester.pumpAndSettle();
    expect(find.text('正在处理题图，请完成后再删除'), findsOneWidget);
    expect(repository.findPrompt(prompt.id), isNotNull);
    gate.complete();
    await active;
    await openDelete(tester);
    await confirmDelete(tester);
    expect(repository.findPrompt(prompt.id), isNull);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('确认期间切换孩子档案不会删除题目', (tester) async {
    final prompt = prompts.first;
    await pumpFlow(tester, location: AppRoutes.pictureStoryDetailOf(prompt.id));
    final before = repository.storageSnapshot();
    await openDelete(tester);
    ProfileScope.switchTo('child-b');
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      if (repository.lastDelete != null) {
        await expectLater(repository.lastDelete!, throwsFormatException);
      }
    });
    await tester.pumpAndSettle();
    expect(repository.storageSnapshot(), before);
    expect(repository.findPrompt(prompt.id), isNotNull);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('确认期间家长重新锁定，不访问已销毁页面也不删除题目', (tester) async {
    final prompt = prompts.first;
    await pumpFlow(tester, location: AppRoutes.pictureStoryDetailOf(prompt.id));
    final before = repository.storageSnapshot();
    await openDelete(tester);
    lockParentForTesting();
    await tester.pumpAndSettle();
    if (find.widgetWithText(TextButton, '删除').evaluate().isNotEmpty) {
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(TextButton, '删除')),
      );
      await tester.pumpAndSettle();
    }
    expect(repository.deleteCalls, 0);
    expect(repository.storageSnapshot(), before);
    expect(repository.findPrompt(prompt.id), isNotNull);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('重复点击只弹出一次确认，保存期间编辑与删除按钮均禁用', (tester) async {
    final prompt = prompts.first;
    await pumpFlow(tester, location: AppRoutes.pictureStoryDetailOf(prompt.id));
    repository.deleteGate = repository.ioZone.run(() => Completer<void>());
    try {
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('删除题目'));
        await tester.tap(find.byTooltip('删除题目'), warnIfMissed: false);
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(TextButton, '删除')),
      );
      await tester.pumpAndSettle();
      expect(repository.deleteCalls, 1);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.delete_outline),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.edit_outlined),
            )
            .onPressed,
        isNull,
      );
    } finally {
      await tester.runAsync(() async {
        repository.deleteGate!.complete();
        await repository.lastDelete?.timeout(const Duration(seconds: 5));
      });
    }
    await tester.pumpAndSettle();
    expect(repository.deleteCalls, 1);
    expect(repository.findPrompt(prompt.id), isNull);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('全部删除后显示可新增的空题库', (tester) async {
    final (_, container) = await pumpFlow(tester);
    for (final prompt in prompts) {
      await openPrompt(tester, prompt);
      await openDelete(tester);
      await confirmDelete(tester);
    }
    expect(find.text('题库还是空的'), findsOneWidget);
    expect(find.byTooltip('新增题目'), findsOneWidget);
    expect(find.byType(AppTile), findsNothing);
    expect(container.read(pictureStoryPromptCountProvider), 0);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('窄屏两倍字号与长题名下删除确认可滚动且操作不溢出', (tester) async {
    final prompt = (await tester.runAsync(
      () => repository.savePrompt(
        prompt: pictureStoryFixture(title: List.filled(80, '题').join()),
        profileId: 'default',
      ),
    ))!;
    await pumpFlow(
      tester,
      location: AppRoutes.pictureStoryDetailOf(prompt.id),
      size: const Size(320, 900),
      textScale: 2,
    );
    await openDelete(tester);
    expect(
      tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable,
      isTrue,
    );
    expect(find.widgetWithText(TextButton, '删除'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(TextButton, '取消')),
    );
    await tester.pumpAndSettle();
    expect(repository.deleteCalls, 0);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}
