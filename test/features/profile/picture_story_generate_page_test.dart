import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/image_generation_client.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/picture_story_generation_service.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/image_generation_config.dart';
import 'package:poemath/data/models/picture_story_editor_draft.dart';
import 'package:poemath/data/models/picture_story_generation_draft.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_view.dart';
import 'package:poemath/features/profile/image_generation_settings_page.dart';
import 'package:poemath/features/profile/picture_story_candidate_editor_page.dart';
import 'package:poemath/features/profile/picture_story_generate_page.dart';
import 'package:poemath/features/profile/picture_story_management_page.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';
import '../../helpers/picture_story_fixture.dart';

class _GenerationFlow extends PictureStoryGenerationService {
  _GenerationFlow({
    required this.image,
    required PictureStoryRepository repository,
    required PictureStoryImageService images,
  }) : super(
          repository: repository,
          images: images,
          backup: BackupService(
            pictureStoryImages: images,
            pictureStoryRepository: repository,
          ),
        );
  final PictureStoryImage image;
  String? capturedPrompt;
  @override
  Future<void> run({
    required PictureStoryGenerationDraft draft,
    required LlmConfig config,
    required ImageGenerationConfig imageConfig,
    required bool Function() isActive,
    void Function()? onChanged,
    String? candidateId,
    String? reuseImageId,
    bool regenerateImage = false,
    String? promptOverride,
  }) async {
    if (!isActive()) throw const ImageGenerationCancelled();
    capturedPrompt = promptOverride;
    final items = [
      for (var i = 0; i < draft.options.count; i++) _candidate(draft, i),
    ];
    await HiveBoxes.settings.put(
      PictureStoryGenerationService.keyFor(draft.profileId),
      draft.copyWith(items).encode(),
    );
    onChanged?.call();
  }

  PictureStoryGenerationCandidate _candidate(
    PictureStoryGenerationDraft draft,
    int index,
  ) {
    final prompt = pictureStoryFixture(
      id: 'local-${draft.id}-$index',
      title: '生成题目 ${index + 1}',
      image: image,
    );
    final filled = PictureStoryEditorDraft.create(
      id: prompt.id,
      profileId: draft.profileId,
      original: prompt,
    );
    return PictureStoryGenerationCandidate(
      edit: PictureStoryEditorDraft(
        id: prompt.id,
        profileId: draft.profileId,
        fields: filled.fields,
        level: prompt.level,
        image: image,
      ),
      imagePrompt: '一个场景',
      requestId: 'request-$index',
      stage: PictureStoryGenerationStage.ready,
    );
  }
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.runAsync(() async {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
  }
  expect(condition(), isTrue);
  await tester.pumpAndSettle();
}

void main() {
  late PictureStoryRepository repository;
  late PictureStoryGenerationService service;
  late Directory directory;
  late PictureStoryImageService images;
  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
    directory =
        await Directory.systemTemp.createTemp('picture_story_generation_ui_');
    images = PictureStoryImageService(directoryProvider: () async => directory);
    repository = PictureStoryRepository(images: images);
    service =
        PictureStoryGenerationService(repository: repository, images: images);
    await HiveBoxes.settings.put('page_animations_enabled', false);
  });
  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForWidgetTesting();
    await directory.delete(recursive: true);
  });

  Future<GoRouter> mount(
    WidgetTester tester, {
    Size size = const Size(420, 900),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: AppRoutes.pictureStoryManagement,
      routes: [
        GoRoute(
          path: AppRoutes.pictureStoryManagement,
          builder: (context, state) => const ParentAccessBoundary(
            child: PictureStoryManagementPage(),
          ),
        ),
        GoRoute(
          path: AppRoutes.pictureStoryGenerate,
          builder: (context, state) =>
              const ParentAccessBoundary(child: PictureStoryGeneratePage()),
        ),
        GoRoute(
          path: AppRoutes.imageGenerationSettings,
          builder: (context, state) => const ParentAccessBoundary(
            child: ImageGenerationSettingsPage(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pictureStoryRepositoryProvider.overrideWithValue(repository),
          pictureStoryGenerationServiceProvider.overrideWithValue(service),
          pictureStoryImageServiceProvider.overrideWithValue(images),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.resolve(
            subject: AppSubject.poem,
            brightness: Brightness.light,
          ),
          builder: (context, child) => PageAnimationScope(
            enabled: false,
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('AI 出题'));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('真实题库入口可打开生成页；缺配置给出明确提示且不创建草稿', (tester) async {
    await mount(tester);
    expect(find.byType(PictureStoryGeneratePage), findsOneWidget);
    expect(find.text('主题（可多选）'), findsOneWidget);
    await tester.ensureVisible(find.text('生成图文题目'));
    await tester.runAsync(() => tester.tap(find.text('生成图文题目')));
    await _until(tester, () => find.text('请先配置图片生成服务').evaluate().isNotEmpty);
    expect(service.readDraft('default'), isNull);
    expect(repository.catalogState().versions, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await drainHiveWritesForTesting(tester);
  });

  Future<void> openCountSheet(WidgetTester tester) async {
    await tester.ensureVisible(find.text('题目数量'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('题目数量'));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('选择题目数量'), findsOneWidget);
  }

  Future<void> chooseCount(WidgetTester tester, int count) async {
    final option = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.widgetWithText(AppTile, '$count 道'),
    );
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(option);
      await tester.pump();
    });
    await _until(
      tester,
      () =>
          find.byType(BottomSheet).evaluate().isEmpty &&
          find.text('$count 道').evaluate().isNotEmpty,
    );
  }

  for (final (size, scale) in [
    (const Size(320, 1100), 2.0),
    (const Size(1200, 900), 1.0),
  ]) {
    testWidgets('生成表单在宽度 ${size.width}、字号 $scale 下可操作且不溢出', (tester) async {
      await mount(tester, size: size, scale: scale);
      expect(find.text('难度'), findsNothing);
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      expect(
        find.byType(DropdownButtonFormField<PictureStoryLevel>),
        findsNothing,
      );
      expect(find.text('生成会使用云端服务和每日额度。请家长预览、核对后入库。'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(PictureStoryGeneratePage),
          matching: find.byType(ColoredCard),
        ),
        findsNothing,
      );
      await openCountSheet(tester);
      final selected = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.widgetWithText(AppTile, '3 道'),
      );
      expect(tester.widget<AppTile>(selected).selected, isTrue);
      for (final element in find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(AppTile),
          )
          .evaluate()) {
        expect(
          tester.getSize(find.byWidget(element.widget)).height,
          greaterThanOrEqualTo(SpacingTokens.minTapTarget),
        );
      }
      await chooseCount(tester, 1);
      await openCountSheet(tester);
      await chooseCount(tester, 5);
      await openCountSheet(tester);
      final sheetContext = tester.element(find.byType(BottomSheet));
      await tester.runAsync(() async {
        Navigator.pop(sheetContext);
        await tester.pump();
      });
      await _until(tester, () => find.byType(BottomSheet).evaluate().isEmpty);
      expect(find.text('5 道'), findsOneWidget);
      await tester.ensureVisible(find.text('自然观察'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自然观察'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '自然观察'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '日常生活'))
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await drainHiveWritesForTesting(tester);
    });
  }

  for (final (size, scale, columns) in [
    (const Size(320, 1100), 2.0, 1),
    (const Size(700, 1100), 1.0, 2),
    (const Size(1200, 1100), 2.0, 3),
  ]) {
    testWidgets('预览在宽度 ${size.width}、字号 $scale 下自然排入 $columns 列并可勾选编辑',
        (tester) async {
      late List<PictureStoryGenerationCandidate> candidates;
      final level = PictureStoryLevel.values.last;
      await tester.runAsync(() async {
        final image = await images.importBytes(await pictureStoryPng());
        final draft = await service.createDraft(
          PictureStoryGenerationOptions(
            level: level,
            count: 5,
            themes: ['日常生活'],
          ),
        );
        candidates = [
          for (var index = 0; index < draft.options.count; index++)
            PictureStoryGenerationCandidate(
              edit: PictureStoryEditorDraft(
                id: 'local-layout-$index',
                profileId: draft.profileId,
                fields: {
                  ...PictureStoryEditorDraft.create(
                    id: 'local-layout-$index',
                    profileId: draft.profileId,
                    original: pictureStoryFixture(
                      id: 'local-layout-$index',
                      title: '预览题目 ${index + 1}',
                      image: image,
                    ),
                  ).fields,
                  if (index == 0)
                    PictureStoryEditorField.questions: [
                      for (var line = 1;
                          line <= PictureStoryPrompt.maxLines;
                          line++)
                        '请描述图中的第 $line 个细节',
                    ].join('\n'),
                },
                level: level,
                image: image,
              ),
              imagePrompt: '测试场景',
              requestId: 'layout-request-$index',
              stage: PictureStoryGenerationStage.ready,
            ),
        ];
        await HiveBoxes.settings.put(
          PictureStoryGenerationService.keyFor(draft.profileId),
          draft.copyWith(candidates).encode(),
        );
      });
      await mount(tester, size: size, scale: scale);
      final cards = [
        for (final candidate in candidates) find.byKey(ValueKey(candidate.id)),
      ];
      final rects = [for (final card in cards) tester.getRect(card)];
      for (final rect in rects) {
        expect(rect.width, closeTo(rects.first.width, 0.01));
        expect(rect.left, greaterThanOrEqualTo(SpacingTokens.md));
        expect(rect.right, lessThanOrEqualTo(size.width - SpacingTokens.md));
      }
      if (columns == 1) {
        for (var index = 1; index < rects.length; index++) {
          expect(rects[index].left, rects.first.left);
          expect(
            rects[index].top,
            closeTo(rects[index - 1].bottom + SpacingTokens.md, 0.01),
          );
        }
      } else {
        for (var index = 1; index < columns; index++) {
          expect(rects[index].top, closeTo(rects.first.top, 0.01));
          expect(
            rects[index].left,
            closeTo(rects[index - 1].right + SpacingTokens.md, 0.01),
          );
        }
        expect(rects[1].height, lessThan(rects.first.height));
        expect(rects[columns].left, closeTo(rects[1].left, 0.01));
        expect(
          rects[columns].top,
          closeTo(rects[1].bottom + SpacingTokens.md, 0.01),
        );
        expect(rects[columns].top, lessThan(rects.first.bottom));
      }
      final title = find.descendant(
        of: cards.first,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.textSpan?.toPlainText().startsWith('预览题目 1') == true,
        ),
      );
      final checkbox = find.descendant(
        of: cards.first,
        matching: find.byType(Checkbox),
      );
      final checkboxRect = tester.getRect(checkbox);
      final titleInset = tester.getRect(title).left - rects.first.left;
      final visibleCheckboxRight = checkboxRect.center.dx + Checkbox.width / 2;
      expect(titleInset, SpacingTokens.md);
      expect(
        rects.first.right - visibleCheckboxRight,
        closeTo(titleInset, 0.01),
      );
      expect(
        checkboxRect.width,
        greaterThanOrEqualTo(SpacingTokens.minTapTarget),
      );
      expect(
        checkboxRect.height,
        greaterThanOrEqualTo(SpacingTokens.minTapTarget),
      );
      // 点击靠近卡片边缘的点击区域，验证留白调整没有裁掉右侧手势。
      await tester.runAsync(
        () => tester.tapAt(
          Offset(rects.first.right - SpacingTokens.xs, checkboxRect.center.dy),
        ),
      );
      final selectedButton = find.widgetWithText(FilledButton, '确认入库（4 道）');
      await _until(
        tester,
        () =>
            !service.readDraft('default')!.candidates.first.selected &&
            selectedButton.evaluate().isNotEmpty &&
            tester.widget<FilledButton>(selectedButton).onPressed != null,
      );
      expect(
        service.readDraft('default')!.candidates.first.toJson(),
        candidates.first.copyWith(selected: false).toJson(),
      );
      expect(find.text('确认入库（4 道）'), findsOneWidget);
      final editButton = find.descendant(
        of: cards.first,
        matching: find.text('编辑内容'),
      );
      await tester.ensureVisible(editButton);
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(editButton));
      final editor = find.byType(PictureStoryCandidateEditorPage);
      await _until(tester, () => editor.evaluate().isNotEmpty);
      final editorCard = find.descendant(
        of: editor,
        matching: find.byType(ColoredCard),
      );
      final editorImage = find.descendant(
        of: editor,
        matching: find.byType(PictureStoryImageView),
      );
      final editorCardRect = tester.getRect(editorCard);
      final editorImageRect = tester.getRect(editorImage);
      expect(editorImageRect.left, closeTo(editorCardRect.left, 0.01));
      expect(editorImageRect.top, closeTo(editorCardRect.top, 0.01));
      expect(editorImageRect.right, closeTo(editorCardRect.right, 0.01));
      expect(
        find.byType(DropdownButtonFormField<PictureStoryLevel>),
        findsNothing,
      );
      final saveButton = find.byTooltip('保存修改');
      expect(
        find.ancestor(of: saveButton, matching: find.byType(AppBar)),
        findsOneWidget,
      );
      final titleField = find.byKey(const ValueKey('picture-story-title'));
      await tester.ensureVisible(titleField);
      await tester.pumpAndSettle();
      await tester.enterText(titleField, '瀑布流中修改的题目');
      await tester.runAsync(() => tester.tap(saveButton));
      final updatedTitle = find.descendant(
        of: cards.first,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.textSpan?.toPlainText().startsWith('瀑布流中修改的题目') == true,
        ),
      );
      await _until(
        tester,
        () => editor.evaluate().isEmpty && updatedTitle.evaluate().isNotEmpty,
      );
      final saved = service.readDraft('default')!;
      expect(
        saved.candidates.first.edit.fields[PictureStoryEditorField.title],
        '瀑布流中修改的题目',
      );
      expect(saved.candidates.first.edit.level, level);
      expect(saved.candidates.first.edit.image, candidates.first.edit.image);
      expect(saved.candidates.first.selected, isFalse);
      expect(
        [for (final candidate in saved.candidates.skip(1)) candidate.toJson()],
        [for (final candidate in candidates.skip(1)) candidate.toJson()],
      );
      expect(repository.catalogState().versions, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await drainHiveWritesForTesting(tester);
    });
  }

  testWidgets('点击重试出题只读取当前图片，不调用生图或处理其他候选', (tester) async {
    late PictureStoryImage image;
    late List<int> stored;
    late List<int> uploaded;
    late PictureStoryGenerationCandidate first;
    late PictureStoryGenerationCandidate other;
    var imageClients = 0;
    var imageRequests = 0;
    final captions = <Map<String, dynamic>>[];
    await tester.runAsync(() async {
      image = await images.importBytes(await pictureStoryNoisePng());
      stored = await images.readImage(image.value);
      uploaded = await images.readForVision(image.value);
      final settings = SettingsRepository();
      await settings.saveImageGenerationConfig(
        provider: const ImageGenerationProviderConfig(
          name: '测试',
          baseUrl: 'https://image.example.com/v1',
          model: 'image',
        ),
        apiKey: '',
      );
      await settings.saveLlmProviderConfig(
        id: 'vision',
        name: '看图',
        baseUrl: 'https://llm.example.com',
        model: 'gpt-4o-mini',
        apiKey: '',
      );
      service = PictureStoryGenerationService(
        repository: repository,
        images: images,
        llmFactory: (active) => LlmClient(
          isActive: active,
          httpClient: MockClient((request) async {
            captions.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'choices': [
                    {
                      'message': {
                        'content': jsonEncode({
                          'title': '复用已有图片的题目',
                          'questions': ['图中的孩子在做什么？'],
                        }),
                      },
                    },
                  ],
                }),
              ),
              200,
            );
          }),
        ),
        imageFactory: (active) {
          imageClients++;
          return ImageGenerationClient(
            isActive: active,
            httpClient: MockClient((request) async {
              imageRequests++;
              throw StateError('重试出题不能调用生图服务');
            }),
          );
        },
      );
      final draft = await service.createDraft(
        PictureStoryGenerationOptions(
          level: PictureStoryLevel.starter,
          count: 2,
          themes: ['日常生活'],
        ),
      );
      first = PictureStoryGenerationCandidate(
        edit: PictureStoryEditorDraft.create(
          id: 'local-retry-first',
          profileId: draft.profileId,
        ).copyWith(image: image),
        imagePrompt: '已有图片的场景',
        requestId: 'request-first',
        stage: PictureStoryGenerationStage.failed,
        error: '看图出题未完成',
      );
      other = PictureStoryGenerationCandidate(
        edit: PictureStoryEditorDraft.create(
          id: 'local-retry-other',
          profileId: draft.profileId,
        ),
        imagePrompt: '尚未生成图片的其他场景',
        requestId: 'request-other',
      );
      await HiveBoxes.settings.put(
        PictureStoryGenerationService.keyFor(draft.profileId),
        draft.copyWith([first, other]).encode(),
      );
    });
    await mount(tester);
    final retry = find.descendant(
      of: find.byKey(ValueKey(first.id)),
      matching: find.text('重试出题'),
    );
    await tester.scrollUntilVisible(
      retry,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(retry));
    final readyButton = find.widgetWithText(FilledButton, '确认入库（1 道）');
    await _until(
      tester,
      () =>
          service.readDraft('default')?.readyCount == 1 &&
          readyButton.evaluate().isNotEmpty &&
          tester.widget<FilledButton>(readyButton).onPressed != null,
    );
    expect(imageClients, 0);
    expect(imageRequests, 0);
    expect(captions, hasLength(1));
    final parts =
        ((captions.single['messages'] as List).last as Map)['content'] as List;
    final url = ((parts.last as Map)['image_url'] as Map)['url'];
    expect(url, 'data:image/png;base64,${base64Encode(uploaded)}');
    final saved = service.readDraft('default')!;
    expect(saved.candidates.first.id, first.id);
    expect(saved.candidates.first.edit.image, image);
    expect(saved.candidates.first.edit.toPrompt().title, '复用已有图片的题目');
    expect(saved.candidates.last.toJson(), other.toJson());
    expect(await tester.runAsync(() => images.readImage(image.value)), stored);
    expect(repository.catalogState().versions, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await drainHiveWritesForTesting(tester);
  });

  testWidgets('使用自定义提示词生成、编辑草稿、勾选后确认入库的真实页面链路', (tester) async {
    final png = await tester.runAsync(() => pictureStoryPng());
    // 测试使用已验证的本地图片，HTTP 图文生成由服务专项测试覆盖。
    final image = await tester.runAsync(() => images.importBytes(png!));
    service =
        _GenerationFlow(image: image!, repository: repository, images: images);
    await tester.runAsync(() async {
      final settings = SettingsRepository();
      await settings.setPictureStoryGenerationPrompt('用儿童水彩场景引导观察和表达');
      await settings.saveImageGenerationConfig(
        provider: const ImageGenerationProviderConfig(
          name: '测试',
          baseUrl: 'https://image.example.com/v1',
          model: 'image',
        ),
        apiKey: '',
      );
      await settings.saveLlmProviderConfig(
        id: 'vision',
        name: '看图',
        baseUrl: 'https://llm.example.com',
        model: 'gpt-4o-mini',
        apiKey: '',
      );
    });
    final router = await mount(tester);
    await openCountSheet(tester);
    await chooseCount(tester, 5);
    await tester.ensureVisible(find.text('生成图文题目'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('生成图文题目')));
    final readyButton = find.widgetWithText(FilledButton, '确认入库（5 道）');
    // 数据就绪不代表生成回调和页面刷新完成，等预览真正可操作。
    await _until(
      tester,
      () =>
          service.readDraft('default')?.readyCount == 5 &&
          readyButton.evaluate().isNotEmpty &&
          tester.widget<FilledButton>(readyButton).onPressed != null,
    );
    expect((service as _GenerationFlow).capturedPrompt, '用儿童水彩场景引导观察和表达');
    expect(service.readDraft('default')!.options.count, 5);
    expect(repository.catalogState().versions, isEmpty);
    final first = service.readDraft('default')!.candidates.first;
    final firstCard = find.byKey(ValueKey(first.id));
    final editButton =
        find.descendant(of: firstCard, matching: find.text('编辑内容'));
    await tester.scrollUntilVisible(
      editButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(editButton));
    await _until(
      tester,
      () => find.byType(PictureStoryCandidateEditorPage).evaluate().isNotEmpty,
    );
    final titleField = find.byKey(const ValueKey('picture-story-title'));
    await tester.ensureVisible(titleField);
    await tester.pumpAndSettle();
    await tester.enterText(titleField, '家长修改后的题目');
    await tester.runAsync(() async {
      ParentAccessService.instance.lock();
    });
    await _until(
      tester,
      () => find.byType(PictureStoryCandidateEditorPage).evaluate().isEmpty,
    );
    await tester.runAsync(() => unlockParentForTesting());
    await _until(
      tester,
      () => find.byType(PictureStoryCandidateEditorPage).evaluate().isNotEmpty,
    );
    expect(
      tester.widget<TextFormField>(titleField).controller!.text,
      '家长修改后的题目',
    );
    await tester.runAsync(() => tester.tap(find.byTooltip('保存修改')));
    await _until(
      tester,
      () => find.byType(PictureStoryCandidateEditorPage).evaluate().isEmpty,
    );
    expect(
      service
          .readDraft('default')!
          .candidates
          .first
          .edit
          .fields[PictureStoryEditorField.title],
      '家长修改后的题目',
    );
    expect(repository.catalogState().versions, isEmpty);
    final last = service.readDraft('default')!.candidates.last;
    final checkbox = find.descendant(
      of: find.byKey(ValueKey(last.id)),
      matching: find.byType(Checkbox),
    );
    await tester.scrollUntilVisible(
      checkbox,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(checkbox));
    await _until(
      tester,
      () => !service.readDraft('default')!.candidates.last.selected,
    );
    final selectedDraft = service.readDraft('default')!;
    expect(
      selectedDraft.selectedPrompts.length,
      4,
      reason: selectedDraft.candidates
          .map((candidate) => '${candidate.stage.name}:${candidate.selected}')
          .join(', '),
    );
    final publishButton = find.text('确认入库（4 道）');
    await _until(tester, () => publishButton.evaluate().isNotEmpty);
    await tester.runAsync(() => tester.tap(publishButton));
    await _until(tester, () => repository.catalogState().versions.length == 4);
    expect(repository.findPrompt(first.id)!.title, '家长修改后的题目');
    expect(repository.findPrompt(last.id), isNull);
    expect(repository.enabledByProfile()['default'], contains(first.id));
    expect(tester.takeException(), isNull);
    // 尚有未选题，因此预览页保留草稿，用户可继续处理。
    expect(
      router.routerDelegate.state.uri.path,
      AppRoutes.pictureStoryGenerate,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await drainHiveWritesForTesting(tester);
  });
}
