import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/picture_story_editor_service.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_tile.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/picture_story_editor_draft.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_view.dart';
import 'package:poemath/features/profile/picture_story_detail_page.dart';
import 'package:poemath/features/profile/picture_story_editor_page.dart';
import 'package:poemath/features/profile/picture_story_management_page.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/picture_story_fixture.dart';

class _Repository extends PictureStoryRepository {
  _Repository({required super.images, super.authorize});
  Future<PictureStoryPrompt>? lastSave;
  Future<void>? lastToggle;
  PictureStoryPrompt? lastCandidate;
  Completer<void>? saveGate;
  bool failNextSave = false;
  var saveCalls = 0;

  @override
  Future<PictureStoryPrompt> savePrompt({
    required PictureStoryPrompt prompt,
    required String profileId,
    PictureStoryPrompt? original,
    bool enableForProfile = true,
  }) {
    saveCalls++;
    lastCandidate = prompt;
    return lastSave = () async {
      await saveGate?.future;
      if (failNextSave) {
        failNextSave = false;
        throw HiveError('模拟保存失败');
      }
      return super.savePrompt(
        prompt: prompt,
        profileId: profileId,
        original: original,
        enableForProfile: enableForProfile,
      );
    }();
  }

  @override
  Future<void> setEnabled(String promptId, bool enabled) =>
      lastToggle = super.setEnabled(promptId, enabled);
}

class _Editor extends PictureStoryEditorService {
  _Editor(
      {required PictureStoryImageService super.images,
      super.pickPath,})
      : super(supportsLostData: false);
  Future<void>? lastPick;
  Future<void>? lastDiscard;
  @override
  Future<void> chooseImage(
    PictureStoryEditorDraft draft,
    PictureStoryImageSource source,
  ) =>
      lastPick = super.chooseImage(draft, source);

  @override
  Future<void> discardDraft(PictureStoryEditorDraft draft) =>
      lastDiscard = super.discardDraft(draft);
}

class _ParentAccess extends ParentAccessService {
  var unlocked = true;
  @override
  bool get enabled => true;
  @override
  bool get isUnlocked => unlocked;
  @override
  Future<void> initialize() async {}
  @override
  void observeLifecycle() {}
  @override
  void lock() {
    unlocked = false;
    notifyListeners();
  }

  void unlock() {
    unlocked = true;
    notifyListeners();
  }
}

void main() {
  late Directory directory;
  late PictureStoryImageService images;
  late _Repository repository;
  late _Editor editor;

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    directory =
        await Directory.systemTemp.createTemp('picture_story_editor_ui_');
    images = PictureStoryImageService(directoryProvider: () async => directory);
    repository = _Repository(images: images);
    editor = _Editor(images: images, pickPath: (_) async => null);
  });
  tearDown(() async {
    editor.dispose();
    ProfileScope.reset();
    await tearDownHiveForTesting();
    await directory.delete(recursive: true);
  });

  Future<(GoRouter, ProviderContainer)> pumpFlow(
    WidgetTester tester, {
    String location = AppRoutes.pictureStoryManagement,
    Size size = const Size(420, 900),
    double textScale = 1,
    _ParentAccess? access,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        pictureStoryImageServiceProvider.overrideWithValue(images),
        pictureStoryRepositoryProvider.overrideWithValue(repository),
        pictureStoryEditorServiceProvider.overrideWithValue(editor),
      ],
    );
    final router = access == null
        ? createAppRouter(initialLocation: location)
        : GoRouter(
            initialLocation: location,
            routes: [
              GoRoute(
                path: AppRoutes.pictureStoryManagement,
                builder: (_, state) => const PictureStoryManagementPage(),
              ),
              GoRoute(
                path: AppRoutes.pictureStoryEdit,
                builder: (_, state) => ParentAccessBoundary(
                  service: access,
                  child: PictureStoryEditorPage(
                    promptId: state.pathParameters['id']!,
                  ),
                ),
              ),
              GoRoute(
                path: AppRoutes.pictureStoryDetail,
                builder: (_, state) => ParentAccessBoundary(
                  service: access,
                  child: PictureStoryDetailPage(
                    promptId: state.pathParameters['id']!,
                  ),
                ),
              ),
            ],
          );
    addTearDown(router.dispose);
    addTearDown(container.dispose);
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

  Future<void> enter(WidgetTester tester, String field, String text) async {
    final finder = find.byKey(ValueKey('picture-story-$field'));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.enterText(finder, text);
    await tester.pump();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(finder));
    await tester.pumpAndSettle();
  }

  Future<void> useBuiltin(WidgetTester tester, String title) async {
    await tapVisible(tester, find.text('使用内置插图'));
    expect(find.text('选择内置插图'), findsOneWidget);
    await tapVisible(tester, find.text(title));
  }

  Future<void> finishSave(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('保存题目'));
      await repository.lastSave!.timeout(const Duration(seconds: 5));
      await editor.lastDiscard!.timeout(const Duration(seconds: 5));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('真实路由新增题目：必填校验、选图、保存详情和数量即时刷新', (tester) async {
    final (router, container) = await pumpFlow(tester);
    await tester.tap(find.byTooltip('新增题目'));
    await tester.pumpAndSettle();
    expect(find.byType(PictureStoryEditorPage), findsOneWidget);
    await tester.tap(find.text('保存题目'));
    await tester.pumpAndSettle();
    expect(repository.saveCalls, 0);
    expect(find.text('请填写题目标题'), findsOneWidget);
    expect(find.text('请至少填写一条引导问题'), findsOneWidget);
    expect(find.text('请选择题目图片'), findsOneWidget);
    await enter(tester, 'title', '窗前的小猫');
    await enter(tester, 'questions', '小猫在哪里？\n它看到了什么？');
    await useBuiltin(tester, '公园里的风筝');
    await finishSave(tester);
    expect(find.byType(PictureStoryDetailPage), findsOneWidget);
    expect(find.text('窗前的小猫'), findsOneWidget);
    expect(repository.saveCalls, 1);
    final saved = repository.listPrompts().last;
    expect(saved.id, startsWith('local-'));
    expect(saved.version, 1);
    expect(saved.questions, ['小猫在哪里？', '它看到了什么？']);
    expect(saved.sceneFacts, isEmpty);
    expect(saved.goals, isEmpty);
    expect(saved.reference, isEmpty);
    expect(saved.image, const PictureStoryImage.builtin('kite'));
    expect(container.read(pictureStoryPromptCountProvider), 4);
    expect(
      HiveBoxes.settings.containsKey(PictureStoryEditorService.draftKey),
      isFalse,
    );
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(PictureStoryManagementPage), findsOneWidget);
    expect(find.text('窗前的小猫'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('新增题可关闭当前孩子启用，其他孩子默认仍只有内置题', (tester) async {
    final (_, container) =
        await pumpFlow(tester, location: AppRoutes.pictureStoryCreate);
    await enter(tester, 'title', '暂时不练习的新题');
    await enter(tester, 'questions', '图里有什么？');
    await useBuiltin(tester, '雨天送伞');
    await tapVisible(tester, find.byType(Switch));
    await finishSave(tester);
    final id = repository.lastCandidate!.id;
    expect(
      repository.findPrompt(id)!.image,
      const PictureStoryImage.builtin('umbrella'),
    );
    expect(repository.isEnabled(id), isFalse);
    expect(container.read(pictureStoryPromptCountProvider), 3);
    ProfileScope.switchTo('another-child');
    expect(repository.isEnabled(id), isFalse);
    expect(repository.listPrompts().length, 4);
    expect(container.read(pictureStoryPromptCountProvider), 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('卡片内容进入详情，开关独立启用；编辑保留旧版本和启用选择', (tester) async {
    final (router, _) = await pumpFlow(tester);
    final title = PictureStoryCatalog.prompts.first.title;
    final tile =
        find.ancestor(of: find.text(title), matching: find.byType(AppTile));
    final toggle = find.descendant(of: tile, matching: find.byType(Switch));
    await tester.runAsync(() async {
      await tester.tap(toggle);
      await repository.lastToggle!;
    });
    await tester.pumpAndSettle();
    expect(find.byType(PictureStoryManagementPage), findsOneWidget);
    expect(repository.isEnabled('kite-in-the-park'), isFalse);
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    expect(find.byType(PictureStoryDetailPage), findsOneWidget);
    expect(find.byType(PictureStoryImageView), findsOneWidget);
    await tester.tap(find.byTooltip('编辑题目'));
    await tester.pumpAndSettle();
    await enter(tester, 'title', '风筝飞得很高');
    await finishSave(tester);
    expect(find.byType(PictureStoryDetailPage), findsOneWidget);
    expect(find.text('风筝飞得很高'), findsOneWidget);
    expect(repository.findPrompt('kite-in-the-park')!.version, 2);
    expect(
      repository.findPrompt('kite-in-the-park', version: 1)!.toJson(),
      PictureStoryCatalog.prompts.first.toJson(),
    );
    expect(repository.isEnabled('kite-in-the-park'), isFalse);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('风筝飞得很高'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('取消编辑先确认，继续编辑保留文字，明确放弃后不改已保存题目', (tester) async {
    final original = PictureStoryCatalog.prompts.first;
    await pumpFlow(tester, location: AppRoutes.pictureStoryEditOf(original.id));
    await enter(tester, 'title', '尚未发布的修改');
    await tester.runAsync(() => tester.tap(find.byTooltip('返回')));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('继续编辑')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('picture-story-title')),
          )
          .controller!
          .text,
      '尚未发布的修改',
    );
    await tester.runAsync(() => tester.tap(find.byTooltip('返回')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('放弃修改')));
    await tester.pumpAndSettle();
    expect(find.byType(PictureStoryManagementPage), findsOneWidget);
    expect(repository.findPrompt(original.id)!.toJson(), original.toJson());
    expect(repository.saveCalls, 0);
    expect(repository.storageSnapshot(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存失败保留表单可重试，重复点击只提交一次并沿用新题标识', (tester) async {
    await pumpFlow(tester, location: AppRoutes.pictureStoryCreate);
    await enter(tester, 'title', '重试后保存的小猫');
    await enter(tester, 'questions', '小猫在做什么？');
    await useBuiltin(tester, '一起收拾玩具');
    repository.failNextSave = true;
    await tester.runAsync(() async {
      await tester.tap(find.text('保存题目'));
      await expectLater(repository.lastSave!, throwsA(isA<HiveError>()));
    });
    await tester.pumpAndSettle();
    expect(find.text('保存失败，填写的内容已保留。请检查设备存储空间后重试。'), findsOneWidget);
    final id = repository.lastCandidate!.id;
    expect(repository.findPrompt(id), isNull);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('picture-story-title')),
          )
          .controller!
          .text,
      '重试后保存的小猫',
    );
    await tester.runAsync(() async {
      repository.saveGate = Completer<void>();
      await tester.tap(find.text('保存题目'));
      await tester.tap(find.text('保存题目'));
      expect(repository.saveCalls, 2);
      repository.saveGate!.complete();
      await repository.lastSave!.timeout(const Duration(seconds: 5));
    });
    await tester.pumpAndSettle();
    expect(find.byType(PictureStoryDetailPage), findsOneWidget);
    expect(repository.lastCandidate!.id, id);
    expect(repository.findPrompt(id)!.version, 1);
    expect(repository.listPrompts().length, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选图离开前台拆毁编辑页，解锁后恢复新文字和图片，等待明确保存', (tester) async {
    final access = _ParentAccess();
    addTearDown(access.dispose);
    repository = _Repository(images: images, authorize: access.assertAllowed);
    final (reached, picked) = (await tester.runAsync(
      () async => (Completer<void>(), Completer<String?>()),
    ))!;
    editor.dispose();
    editor = _Editor(
      images: images,
      pickPath: (_) {
        reached.complete();
        return picked.future;
      },
    );
    final source = File('${directory.path}/chosen.png');
    await tester.runAsync(() async {
      await source.writeAsBytes(await pictureStoryPng(width: 11, height: 7));
    });
    final original = PictureStoryCatalog.prompts.first;
    final (_, container) = await pumpFlow(
      tester,
      location: AppRoutes.pictureStoryEditOf(original.id),
      access: access,
    );
    await enter(tester, 'title', '选图前刚刚填写的标题');
    await enter(tester, 'questions', '这是新的引导问题吗？\n小狗在哪里？');
    await tapVisible(tester, find.text('从文件选择'));
    await tester.runAsync(() => reached.future);
    expect(
      editor.readDraft()!.fields[PictureStoryEditorField.title],
      '选图前刚刚填写的标题',
    );
    access.lock();
    await tester.pumpAndSettle();
    expect(find.byType(PictureStoryEditorPage), findsNothing);
    expect(find.text('请由家长解锁后继续'), findsOneWidget);
    await tester.runAsync(() async {
      picked.complete(source.path);
      await editor.lastPick;
    });
    await tester.pumpAndSettle();
    expect(repository.findPrompt(original.id)!.toJson(), original.toJson());
    expect(repository.saveCalls, 0);
    expect(editor.readDraft()!.image!.isLocal, isTrue);
    await tester.runAsync(() async {
      final id = editor.readDraft()!.image!.value;
      final subscription =
          container.listen(pictureStoryImageBytesProvider(id), (_, __) {});
      addTearDown(subscription.close);
      await container.read(pictureStoryImageBytesProvider(id).future);
    });
    access.unlock();
    await tester.pumpAndSettle();
    expect(find.byType(PictureStoryEditorPage), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('picture-story-title')),
          )
          .controller!
          .text,
      '选图前刚刚填写的标题',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('picture-story-questions')),
          )
          .controller!
          .text,
      '这是新的引导问题吗？\n小狗在哪里？',
    );
    await finishSave(tester);
    expect(repository.findPrompt(original.id)!.title, '选图前刚刚填写的标题');
    expect(repository.findPrompt(original.id)!.image.isLocal, isTrue);
    expect(repository.findPrompt(original.id)!.version, 2);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 900),
    const Size(600, 1000),
    const Size(1100, 1000),
  ]) {
    testWidgets('大字号编辑长内容可滚动且无溢出 ${size.width}', (tester) async {
      final original = PictureStoryCatalog.prompts.first;
      final edited = original.copyWith(
        title: List.filled(10, '风筝和小狗的故事').join(),
        questions: [List.filled(30, '小狗和孩子正在做什么？').join()],
        reference: List.filled(40, '风筝在天空中飞，小狗在草地上跑。').join(),
      );
      await tester.runAsync(
        () => repository.savePrompt(
          prompt: edited,
          original: original,
          profileId: 'default',
        ),
      );
      await pumpFlow(
        tester,
        location: AppRoutes.pictureStoryEditOf(original.id),
        size: size,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      final reference = find.byKey(const ValueKey('picture-story-reference'));
      await tester.ensureVisible(reference);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(reference).controller!.text,
        edited.reference,
      );
      expect(tester.getRect(reference).width, greaterThan(0));
      expect(find.text('保存题目'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('不存在题目的编辑深链显示中文返回入口，不生成题库或练习草稿', (tester) async {
    await pumpFlow(
      tester,
      location: AppRoutes.pictureStoryEditOf('missing-prompt'),
    );
    expect(find.text('题目不存在，请返回题库选择其他题目。'), findsOneWidget);
    expect(find.text('保存题目'), findsNothing);
    expect(repository.storageSnapshot(), isEmpty);
    expect(HiveBoxes.pictureStoryPractice.isEmpty, isTrue);
    expect(tester.takeException(), isNull);
  });
}
