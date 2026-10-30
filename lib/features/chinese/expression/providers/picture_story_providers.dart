import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';

final pictureStoryRepositoryProvider = Provider<PictureStoryRepository>((ref) {
  return PictureStoryRepository();
});

final pictureStoryCatalogProvider = Provider<List<PictureStoryPrompt>>((ref) {
  return PictureStoryCatalog.prompts;
});

final pictureStoryPromptProvider = Provider<List<PictureStoryPrompt>>((ref) {
  final profile = ProfileScope.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(profile.cancel);
  return ref
      .watch(pictureStoryRepositoryProvider)
      .listPrompts(enabledOnly: true);
});

final pictureStoryPromptCountProvider = Provider<int>((ref) {
  return ref.watch(pictureStoryPromptProvider).length;
});

final pictureStoryHistoryProvider =
    Provider<List<PictureStoryPracticeRecord>>((ref) {
  final profile = ProfileScope.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(profile.cancel);
  return ref.watch(pictureStoryRepositoryProvider).records();
});
