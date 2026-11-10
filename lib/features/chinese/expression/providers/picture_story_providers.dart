import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/services/picture_story_editor_service.dart';
import 'package:poemath/core/services/picture_story_generation_service.dart';
import 'package:poemath/core/services/picture_story_generation_controller.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/providers/llm_runtime_providers.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/picture_story_audio_service.dart';

final pictureStoryAudioServiceProvider = Provider<PictureStoryAudioService>(
  (ref) => PictureStoryAudioService(),
);

final pictureStoryImageServiceProvider = Provider<PictureStoryImageService>(
  (ref) => PictureStoryImageService.instance,
);

final pictureStoryEditorServiceProvider = Provider<PictureStoryEditorService>(
  (ref) => PictureStoryEditorService.instance,
);

final pictureStoryImageBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, id) {
      return ref.watch(pictureStoryImageServiceProvider).readImage(id);
    });

final pictureStoryRepositoryProvider = Provider<PictureStoryRepository>((ref) {
  return PictureStoryRepository(
    images: ref.watch(pictureStoryImageServiceProvider),
  );
});

final pictureStoryGenerationServiceProvider =
    Provider<PictureStoryGenerationService>((ref) {
      final httpClient = ref.read(llmExplainHttpClientProvider);
      final settings = ref.read(settingsRepositoryProvider);
      final selectionVersion = ref.read(llmSelectionVersionProvider.notifier);
      return PictureStoryGenerationService(
        images: ref.watch(pictureStoryImageServiceProvider),
        repository: ref.watch(pictureStoryRepositoryProvider),
        llmFactory: (active) => createRuntimeLlmClient(
          chatTimeout: PictureStoryGenerationService.requestTimeout,
          httpClient: httpClient,
          settings: settings,
          isActive: active,
          onSelectionChanged: () => selectionVersion.state++,
        ),
      );
    });

/// 普通 Provider 随应用存续；无页面监听时任务和生命周期订阅仍有效。
final pictureStoryGenerationControllerProvider =
    Provider<PictureStoryGenerationController>((ref) {
      final controller = PictureStoryGenerationController(
        // Controller 是应用级任务所有者；用 read 避免设置 Provider 刷新时重建它。
        service: ref.read(pictureStoryGenerationServiceProvider),
        settings: ref.read(settingsRepositoryProvider),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

final pictureStoryCatalogProvider = Provider<List<PictureStoryPrompt>>((ref) {
  final repository = ref.watch(pictureStoryRepositoryProvider);
  final changes = repository.watchCatalog().listen((_) => ref.invalidateSelf());
  ref.onDispose(changes.cancel);
  return repository.listPrompts();
});

final pictureStoryPromptByIdProvider =
    Provider.family<PictureStoryPrompt?, String>((ref, id) {
      ref.watch(pictureStoryCatalogProvider);
      return ref.watch(pictureStoryRepositoryProvider).findPrompt(id);
    });

final pictureStoryPromptVersionProvider =
    Provider.family<PictureStoryPrompt?, ({String id, int version})>((
      ref,
      key,
    ) {
      ref.watch(pictureStoryCatalogProvider);
      return ref
          .watch(pictureStoryRepositoryProvider)
          .findPrompt(key.id, version: key.version);
    });

final pictureStoryPromptProvider = Provider<List<PictureStoryPrompt>>((ref) {
  final profile = ProfileScope.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(profile.cancel);
  final repository = ref.watch(pictureStoryRepositoryProvider);
  final enabled = repository
      .watchEnabled(ProfileScope.currentId)
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(enabled.cancel);
  ref.watch(pictureStoryCatalogProvider);
  return repository.listPrompts(enabledOnly: true);
});

final pictureStoryPromptCountProvider = Provider<int>((ref) {
  return ref.watch(pictureStoryPromptProvider).length;
});

final pictureStoryHistoryProvider = Provider<List<PictureStoryPracticeRecord>>((
  ref,
) {
  final profile = ProfileScope.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(profile.cancel);
  final repository = ref.watch(pictureStoryRepositoryProvider);
  final records = repository.watchRecords().listen((_) => ref.invalidateSelf());
  ref.onDispose(records.cancel);
  return repository.records();
});

/// 同一题目的完成记录；文字重评保存在原记录内，不增加练习次数。
final pictureStoryPromptHistoryProvider =
    Provider.family<List<PictureStoryPracticeRecord>, String>((ref, promptId) {
      return ref
          .watch(pictureStoryHistoryProvider)
          .where((record) => record.promptId == promptId)
          .toList();
    });
