import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/picture_story_generation_controller.dart';
import 'package:poemath/core/services/picture_story_generation_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/image_generation_config.dart';
import 'package:poemath/data/models/picture_story_generation_draft.dart';
import 'package:poemath/data/models/picture_story_prompt.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';
import '../../helpers/picture_story_generation_harness.dart';

class _FailingDraftService extends PictureStoryGenerationService {
  int attempts = 0;
  @override
  Future<PictureStoryGenerationDraft> createDraft(
    PictureStoryGenerationOptions options,
  ) async {
    attempts++;
    throw StateError('synthetic draft storage failure');
  }
}

class _ProgressSettings extends SettingsRepository {
  @override
  Future<ImageGenerationConfig?> readImageGenerationConfig() async =>
      const ImageGenerationConfig(
        provider: ImageGenerationProviderConfig(
          name: '测试',
          baseUrl: 'https://image.example.com/v1',
          model: 'image',
        ),
        apiKey: '',
      );

  @override
  Future<LlmConfig?> readLlmConfigForScenario(LlmScenario scenario) async =>
      const LlmConfig(
        baseUrl: 'https://chat.example.com/v1',
        apiKey: '',
        model: 'gpt-4o',
      );
}

/// 仅控制请求边界，让进度计时可用虚拟时间验证，不依赖网络或磁盘等待。
class _ProgressService extends PictureStoryGenerationService {
  _ProgressService(this.draft);
  final PictureStoryGenerationDraft draft;
  final done = Completer<void>();
  void Function(int, int)? captionAttempt;

  @override
  PictureStoryGenerationDraft? readDraft(String profileId) => draft;

  @override
  void pause(String profileId) {
    if (!done.isCompleted) done.complete();
  }

  @override
  Future<void> run({
    required PictureStoryGenerationDraft draft,
    required LlmConfig config,
    required ImageGenerationConfig imageConfig,
    required bool Function() isActive,
    void Function()? onChanged,
    void Function(int attempt)? onPlanningAttempt,
    void Function(String signature)? onLlmSelectionSaved,
    void Function(int index, int attempt)? onImageAttempt,
    void Function(int index, int attempt)? onCaptionAttempt,
    Future<void> Function(ImageGenerationConfig successful)? onImageSuccess,
    String? candidateId,
    String? reuseImageId,
    bool regenerateImage = false,
    String? imagePromptOverride,
    String? questionPromptOverride,
  }) {
    captionAttempt = onCaptionAttempt;
    onPlanningAttempt?.call(1);
    return done.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PictureStoryGenerationHarness harness;
  late ProviderContainer container;
  late PictureStoryGenerationController controller;
  final tasks = <Future<void>>[];
  var disposed = false;

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    await unlockParentForTesting();
    harness = await PictureStoryGenerationHarness.create();
    container = ProviderContainer(
      overrides: [
        pictureStoryGenerationServiceProvider.overrideWithValue(
          harness.service,
        ),
        settingsRepositoryProvider.overrideWithValue(harness.settings),
      ],
    );
    controller = container.read(pictureStoryGenerationControllerProvider);
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    tasks.clear();
    disposed = false;
  });

  tearDown(() async {
    if (!disposed) container.dispose();
    harness.releaseAll();
    await Future.wait(tasks).timeout(const Duration(seconds: 5));
    lockParentForTesting();
    ProfileScope.reset();
    await harness.dispose();
    await tearDownHiveForTesting();
  });

  Future<void> start({int count = 2, String? id, String? image}) {
    final task = controller.start(
      profileId: ProfileScope.currentId,
      profileRevision: ProfileScope.revision,
      options: PictureStoryGenerationOptions(
        level: PictureStoryLevel.starter,
        count: count,
        themes: ['自然观察'],
        requirements: '孩子观察花朵',
      ),
      candidateId: id,
      reuseImageId: image,
    );
    tasks.add(task);
    return task;
  }

  testWidgets('等待提示随时间更新，切换请求重新计时，后台暂停后停止计时', (tester) async {
    final options = PictureStoryGenerationOptions(
      level: PictureStoryLevel.starter,
      count: 3,
      themes: ['自然观察'],
    );
    final service = _ProgressService(
      PictureStoryGenerationDraft(
        id: 'batch-progress',
        profileId: 'default',
        options: options,
        candidates: [],
      ),
    );
    final progress = PictureStoryGenerationController(
      service: service,
      settings: _ProgressSettings(),
    );
    progress.didChangeAppLifecycleState(AppLifecycleState.resumed);
    try {
      final pending = progress.start(
        profileId: 'default',
        profileRevision: ProfileScope.revision,
        options: options,
      );
      await tester.pump();
      expect(progress.stateFor('default').progress, '正在规划场景…');
      expect(progress.stateFor('default').waitMessage, isNull);
      await tester.pump(const Duration(seconds: 10));
      expect(progress.stateFor('default').waitMessage, '本次请求已等待 10 秒');
      await tester.pump(const Duration(seconds: 20));
      expect(progress.stateFor('default').waitMessage, contains('可随时暂停'));
      service.captionAttempt!(0, 2);
      expect(progress.stateFor('default').progress, contains('重试看图出题'));
      expect(progress.stateFor('default').waitMessage, isNull);
      await tester.pump(const Duration(seconds: 10));
      expect(progress.stateFor('default').elapsed.inSeconds, 10);
      progress.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();
      await pending;
      expect(progress.stateFor('default').phase, PictureStoryRunPhase.paused);
      await tester.pump(const Duration(seconds: 60));
      expect(progress.stateFor('default').elapsed, Duration.zero);
      expect(progress.stateFor('default').waitMessage, isNull);
    } finally {
      progress.dispose();
    }
  });

  for (final step in ['config', 'plan', 'image:1', 'caption:1']) {
    test('没有页面监听时继续完成，$step 期间重复启动不会重复请求', () async {
      final gate = harness.hold(step);
      final work = start();
      await gate.entered.future.timeout(const Duration(seconds: 5));
      final duplicate = start(count: 5);
      expect(identical(work, duplicate), isTrue);
      expect(controller.stateFor('default').options!.count, 2);
      expect(controller.stateFor('default').isBusy, isTrue);
      gate.release();
      await work;
      final draft = harness.service.readDraft('default')!;
      expect(draft.readyCount, 2);
      expect(draft.options.requirements, '孩子观察花朵');
      expect(draft.candidates.map((c) => c.edit.toPrompt().title), [
        '观察花朵 1',
        '观察花朵 2',
      ]);
      expect(harness.order, [
        'plan',
        'image:1',
        'caption:1',
        'image:2',
        'caption:2',
      ]);
      expect(harness.settings.imageConfigReads, 1);
      expect(
        controller.stateFor('default').phase,
        PictureStoryRunPhase.finished,
      );
      expect(harness.repository.catalogState().versions, isEmpty);
      expect(
        CloudUsageService.instance.used(CloudUsageKind.imageGeneration),
        2,
      );
      expect(CloudUsageService.instance.used(CloudUsageKind.llm), 3);
    });
  }

  test('生图跨模型厂商恢复后整批继续，自动回写不打断后续看图模型切换', () async {
    await harness.settings.saveImageGenerationProviderConfig(
      id: 'backup',
      name: '备用生图',
      baseUrl: 'https://backup.example.com/v1',
      model: 'backup-bad',
      models: ['backup-bad', 'backup-good'],
      apiKey: '',
    );
    harness.imageFallback = true;
    harness.fallbackTwice = true;
    final progress = <String>[];
    controller.addListener(
      () => progress.add(controller.stateFor('default').progress),
    );
    await start(count: 3);
    expect(harness.service.readDraft('default')!.readyCount, 3);
    expect(harness.imageModels, [
      'image',
      'backup-bad',
      'backup-good',
      'backup-good',
      'backup-good',
    ]);
    expect(harness.settings.imageGenerationActiveProviderId, 'backup');
    expect(harness.settings.imageGenerationProvider!.model, 'backup-good');
    expect(harness.settings.llmProviders.single.model, 'gpt-4.1');
    expect(controller.stateFor('default').phase, PictureStoryRunPhase.finished);
    expect(progress, contains('第 1 道题正在切换生图模型重试（第 2 次）…'));
    expect(progress, contains('第 1 道题正在重试看图出题（第 2 次）…'));
    expect(progress, contains('正在根据第 3 张图片出题…'));
    expect(CloudUsageService.instance.used(CloudUsageKind.imageGeneration), 5);
    expect(harness.repository.catalogState().versions, isEmpty);
  });

  test('看图 DNS 全部失败立即停止后续生图，网络恢复后复用图片继续三题', () async {
    harness.captionDnsFailure = true;
    await start(count: 3);
    final interrupted = harness.service.readDraft('default')!;
    final image = interrupted.candidates.first.edit.image!.value;
    expect(
      interrupted.candidates.first.stage,
      PictureStoryGenerationStage.failed,
    );
    expect(interrupted.candidates.first.error, contains('无法解析看图服务地址'));
    expect(interrupted.candidates.skip(1).map((item) => item.stage), [
      PictureStoryGenerationStage.planned,
      PictureStoryGenerationStage.planned,
    ]);
    expect(harness.imageCalls, 1);
    expect(harness.captionCalls, 1);
    harness.captionDnsFailure = false;
    await start(count: 3);
    final completed = harness.service.readDraft('default')!;
    expect(completed.readyCount, 3);
    expect(completed.candidates.first.edit.image!.value, image);
    expect(harness.imageCalls, 3);
    expect(harness.planningCalls, 1);
  });

  test('生图切换候选期间手动改配置，旧成功响应不回写默认且不再请求', () async {
    await harness.settings.saveImageGenerationProviderConfig(
      id: 'backup',
      name: '备用生图',
      baseUrl: 'https://backup.example.com/v1',
      model: 'backup-good',
      apiKey: '',
    );
    harness.imageFallback = true;
    final gate = harness.hold('image:2');
    final work = start();
    await gate.entered.future.timeout(const Duration(seconds: 5));
    await harness.settings.saveImageGenerationProviderConfig(
      id: 'manual',
      name: '手动设置',
      baseUrl: 'https://manual.example.com/v1',
      model: 'manual',
      apiKey: '',
    );
    await harness.settings.setImageGenerationActiveProvider('manual');
    gate.release();
    await work;
    expect(harness.settings.imageGenerationActiveProviderId, 'manual');
    expect(harness.settings.imageGenerationProvider!.model, 'manual');
    expect(harness.imageCalls, 2);
    expect(harness.captionCalls, 0);
    expect(controller.stateFor('default').phase, PictureStoryRunPhase.paused);
  });

  for (final stop in ['background', 'lock', 'profile', 'pause', 'dispose']) {
    test('页面不存在时 $stop 终止批次，原图保留且不自动复活', () async {
      final gate = harness.hold('caption:1');
      final work = start();
      await gate.entered.future.timeout(const Duration(seconds: 5));
      final before = harness.service.readDraft('default')!;
      final image = before.candidates.first.edit.image!;
      final bytes = await harness.images.readImage(image.value);
      switch (stop) {
        case 'background':
          controller.didChangeAppLifecycleState(AppLifecycleState.paused);
          controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        case 'lock':
          lockParentForTesting();
          await ParentAccessService.instance.authenticate(testParentPin);
        case 'profile':
          ProfileScope.switchTo('child-b');
          ProfileScope.switchTo('default');
        case 'pause':
          controller.pause('default');
          expect(identical(start(), work), isTrue);
        case 'dispose':
          container.dispose();
          disposed = true;
      }
      // 客户端取消必须能独立结束，不能等服务器释放响应。
      await work.timeout(const Duration(seconds: 5));
      gate.release();
      await Future<void>.delayed(Duration.zero);
      final draft = harness.service.readDraft('default')!;
      expect(draft.id, before.id);
      expect(
        draft.candidates.first.stage,
        PictureStoryGenerationStage.imageReady,
      );
      expect(draft.candidates.first.edit.image, image);
      expect(await harness.images.readImage(image.value), bytes);
      expect(draft.candidates.last.edit.image, isNull);
      expect(harness.order, ['plan', 'image:1', 'caption:1']);
      expect(harness.service.isRunning('default'), isFalse);
      expect(harness.repository.catalogState().versions, isEmpty);
      if (!disposed) {
        expect(
          controller.stateFor('default').phase,
          PictureStoryRunPhase.paused,
        );
        await start(id: draft.candidates.first.id, image: image.value);
        expect(harness.imageCalls, 1);
        expect(harness.captionCalls, 2);
        expect(harness.service.readDraft('default')!.readyCount, 1);
      }
    });
  }

  test('读取配置时暂停保留停止态，返回前台和再次点击不另起任务', () async {
    final gate = harness.hold('config');
    final work = start();
    await gate.entered.future;
    controller.pause('default');
    expect(controller.stateFor('default').phase, PictureStoryRunPhase.stopping);
    expect(identical(start(), work), isTrue);
    gate.release();
    await work;
    expect(harness.order, isEmpty);
    expect(harness.service.readDraft('default'), isNull);
    expect(controller.stateFor('default').phase, PictureStoryRunPhase.paused);
  });

  test('设置仓储刷新不重建应用级任务，已有请求继续完成', () async {
    final gate = harness.hold('caption:1');
    final work = start();
    await gate.entered.future;
    container.invalidate(settingsRepositoryProvider);
    container.updateOverrides([
      pictureStoryGenerationServiceProvider.overrideWithValue(harness.service),
      settingsRepositoryProvider.overrideWithValue(SettingsRepository()),
    ]);
    await container.pump();
    expect(
      identical(
        container.read(pictureStoryGenerationControllerProvider),
        controller,
      ),
      isTrue,
    );
    expect(controller.stateFor('default').isBusy, isTrue);
    gate.release();
    await work;
    expect(harness.service.readDraft('default')!.readyCount, 2);
    expect(harness.order, [
      'plan',
      'image:1',
      'caption:1',
      'image:2',
      'caption:2',
    ]);
  });

  test('任务不会延长管理页退出后的五分钟授权，过期保留原图', () async {
    var now = DateTime(2026, 11, 6);
    final parent = ParentAccessService(clock: () => now);
    expect(await parent.authenticate(testParentPin), isTrue);
    parent.enterManagementPage();
    parent.leaveManagementPage();
    final scoped = PictureStoryGenerationController(
      service: harness.service,
      settings: harness.settings,
      parent: parent,
    );
    scoped.didChangeAppLifecycleState(AppLifecycleState.resumed);
    final gate = harness.hold('caption:1');
    final work = scoped.start(
      profileId: 'default',
      profileRevision: ProfileScope.revision,
      options: PictureStoryGenerationOptions(
        level: PictureStoryLevel.starter,
        count: 2,
        themes: ['自然观察'],
      ),
    );
    tasks.add(work);
    try {
      await gate.entered.future;
      now = now.add(ParentAccessService.unlockDuration);
      expect(parent.isUnlocked, isFalse);
      gate.release();
      await work;
      expect(scoped.stateFor('default').phase, PictureStoryRunPhase.paused);
      expect(harness.order, ['plan', 'image:1', 'caption:1']);
      expect(
        harness.service.readDraft('default')!.candidates.first.stage,
        PictureStoryGenerationStage.imageReady,
      );
    } finally {
      scoped.dispose();
      parent.dispose();
    }
  });

  test('草稿写入抛出 Error 仍释放忙碌状态，允许主动重试', () async {
    final failing = _FailingDraftService();
    final scoped = PictureStoryGenerationController(
      service: failing,
      settings: harness.settings,
    );
    scoped.didChangeAppLifecycleState(AppLifecycleState.resumed);
    try {
      for (var i = 0; i < 2; i++) {
        await scoped.start(
          profileId: 'default',
          profileRevision: ProfileScope.revision,
          options: PictureStoryGenerationOptions(
            level: PictureStoryLevel.starter,
            count: 1,
            themes: ['自然观察'],
          ),
        );
        expect(scoped.stateFor('default').isBusy, isFalse);
        expect(scoped.stateFor('default').phase, PictureStoryRunPhase.failed);
        expect(scoped.stateFor('default').message, '生成未完成，已保存内容会保留，请稍后重试');
      }
      expect(failing.attempts, 2);
      expect(harness.order, isEmpty);
      expect(harness.service.readDraft('default'), isNull);
    } finally {
      scoped.dispose();
    }
  });

  test('自动选择两次模型仍完成，人工配置变化在下一请求前停止', () async {
    harness.fallbackTwice = true;
    await start();
    expect(harness.promotions, 2);
    expect(harness.models, [
      'gpt-4o',
      'gpt-4o-mini',
      'gpt-4o-mini',
      'gpt-4.1',
      'gpt-4.1',
    ]);
    expect(harness.settings.llmProviders.single.model, 'gpt-4.1');
    expect(harness.service.readDraft('default')!.readyCount, 2);
    await harness.service.discardDraft(harness.service.readDraft('default')!);
    final gate = harness.hold('plan');
    final work = start();
    await gate.entered.future;
    await harness.settings.setPictureStoryQuestionGenerationPrompt('先描述人物动作');
    gate.release();
    await work;
    expect(harness.imageCalls, 2);
    expect(harness.service.readDraft('default')!.candidates, isEmpty);
    expect(controller.stateFor('default').phase, PictureStoryRunPhase.paused);
  });

  test('配置和规划错误转为可恢复状态，新容器读取草稿不自动运行', () async {
    harness.settings.failRead = true;
    await start();
    expect(controller.stateFor('default').phase, PictureStoryRunPhase.failed);
    expect(harness.service.readDraft('default'), isNull);
    harness.settings.failRead = false;
    harness.invalidPlan = true;
    await start();
    expect(controller.stateFor('default').phase, PictureStoryRunPhase.failed);
    final draft = harness.service.readDraft('default')!;
    expect(draft.candidates, isEmpty);
    expect(harness.imageCalls, 0);
    final before = List<String>.of(harness.order);
    container.dispose();
    container = ProviderContainer(
      overrides: [
        pictureStoryGenerationServiceProvider.overrideWithValue(
          harness.service,
        ),
        settingsRepositoryProvider.overrideWithValue(harness.settings),
      ],
    );
    controller = container.read(pictureStoryGenerationControllerProvider);
    await Future<void>.delayed(Duration.zero);
    expect(controller.stateFor('default').phase, PictureStoryRunPhase.idle);
    expect(harness.service.readDraft('default')!.encode(), draft.encode());
    expect(harness.order, before);
  });
}
