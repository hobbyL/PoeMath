import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_adventure_progress.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/math_adventure_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

final mathAdventureProfileProvider = Provider<({String id, int revision})>((
  ref,
) {
  final subscription = ProfileScope.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(() => unawaited(subscription.cancel()));
  return (id: ProfileScope.currentId, revision: ProfileScope.revision);
});

final mathAdventureRepositoryProvider = Provider<MathAdventureRepository>((
  ref,
) {
  ref.watch(mathAdventureProfileProvider);
  return MathAdventureRepository();
});

/// 每个练习页面取得自己的 lease，不能共享有可变所有权的仓储实例。
final mathAdventureDraftRepositoryProvider =
    Provider<PracticeDraftRepository Function()>(
      (ref) => PracticeDraftRepository.new,
    );

final mathAdventureSettingsProvider =
    Provider<
      ({int grade, String semester, DifficultyLevel difficulty, int count})
    >((ref) {
      final subscription = HiveBoxes.settings.watch().listen(
        (_) => ref.invalidateSelf(),
      );
      ref.onDispose(() => unawaited(subscription.cancel()));
      final settings = ref.watch(settingsRepositoryProvider);
      return (
        grade: settings.selectedGrade,
        semester: settings.selectedSemester,
        difficulty: DifficultyLevel.values.byName(settings.mathDifficulty),
        count: settings.mathBatchSize,
      );
    });

final mathAdventureProgressProvider =
    Provider<AsyncValue<List<MathAdventureProgress>>>((ref) {
      final repository = ref.watch(mathAdventureRepositoryProvider);
      final subscription = HiveBoxes.mathAdventureProgress.watch().listen(
        (_) => ref.invalidateSelf(),
      );
      ref.onDispose(() => unawaited(subscription.cancel()));
      try {
        return AsyncData(repository.getAll());
      } catch (error, stack) {
        return AsyncError(error, stack);
      }
    });

/// 对账独立于 build；相同集合不产生写入，不会触发监听循环。
final mathAdventureReconcileProvider = FutureProvider.autoDispose<void>((
  ref,
) async {
  final settings = ref.watch(mathAdventureSettingsProvider);
  final repository = ref.watch(mathAdventureRepositoryProvider);
  // 先离开触发 provider 的 build 帧，再执行可能写入纪念物的对账。
  bool disposed = false;
  ref.onDispose(() => disposed = true);
  await Future<void>.value();
  if (disposed) return;
  await repository.reconcile(
    settings.grade,
    settings.semester,
    settings.difficulty,
  );
});
