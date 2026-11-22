import 'package:hive/hive.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_adventure_progress.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/domain/math_adventure_catalog.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

class MathAdventureCompletion {
  const MathAdventureCompletion(this.progress, this.newRegions);
  final MathAdventureProgress progress;
  final Set<String> newRegions;
}

class MathAdventureRepository {
  MathAdventureRepository({Box<MathAdventureProgress>? box})
    : profileId = ProfileScope.currentId,
      _revision = ProfileScope.revision,
      _box = box ?? HiveBoxes.mathAdventureProgress;
  final String profileId;
  final int _revision;
  final Box<MathAdventureProgress> _box;
  final _drafts = PracticeDraftRepository();
  static final _tails = <String, Future<void>>{};

  void assertCurrent() {
    _drafts.assertCurrent();
    if (profileId != ProfileScope.currentId ||
        _revision != ProfileScope.revision) {
      throw StateError('学习档案已切换，请重新进入探险');
    }
  }

  MathAdventureProgress read(int grade, String semester) {
    assertCurrent();
    GradePresets.get(grade, semester);
    return _box.get(MathAdventureProgress.keyFor(profileId, grade, semester)) ??
        MathAdventureProgress(
          profileId: profileId,
          grade: grade,
          semester: semester,
        );
  }

  List<MathAdventureProgress> getAll() {
    assertCurrent();
    return _box.values.where((p) => p.profileId == profileId).toList();
  }

  void assertCanStart(MathAdventureNode node, DifficultyLevel difficulty) {
    node.validate();
    final progress = read(node.grade, node.semester);
    final route = MathAdventureCatalog.route(
      grade: node.grade,
      semester: node.semester,
      difficulty: difficulty,
    );
    if (!route.any((s) => s.id == node.skillId) ||
        !progress.completedSkillIds.contains(node.skillId) &&
            MathAdventureCatalog.current(
                  route,
                  progress.completedSkillIds,
                )?.id !=
                node.skillId) {
      throw StateError('这处小路尚未开放，请从当前关卡出发');
    }
  }

  Future<MathAdventureCompletion> complete({
    required MathAdventureNode node,
    required DifficultyLevel difficulty,
    required int totalProblems,
    required int correctCount,
    required void Function() ensureCurrent,
  }) async {
    node.validate();
    if (totalProblems < 1 ||
        totalProblems > 100 ||
        correctCount != totalProblems) {
      throw StateError('整组题目全部答对，才能解锁下一站');
    }
    return _update(
      node.grade,
      node.semester,
      difficulty,
      completedSkill: node.skillId,
      ensureCurrent: ensureCurrent,
    );
  }

  Future<MathAdventureCompletion> reconcile(
    int grade,
    String semester,
    DifficultyLevel difficulty,
  ) => _update(grade, semester, difficulty);

  Future<MathAdventureCompletion> _update(
    int grade,
    String semester,
    DifficultyLevel difficulty, {
    String? completedSkill,
    void Function()? ensureCurrent,
  }) => _drafts.guard(() async {
    assertCurrent();
    final key = MathAdventureProgress.keyFor(profileId, grade, semester);
    final previous = _tails[key];
    final work = () async {
      if (previous != null) await previous;
      assertCurrent();
      ensureCurrent?.call();
      final regions = MathAdventureCatalog.regions(
        grade: grade,
        semester: semester,
        difficulty: difficulty,
      );
      if (completedSkill != null &&
          !regions.values.expand((s) => s).any((s) => s.id == completedSkill)) {
        throw const FormatException('本次练习知识点与探险路线不符');
      }
      final before = read(grade, semester);
      final skills = {
        ...before.completedSkillIds,
        if (completedSkill != null) completedSkill,
      };
      final collected = {
        ...before.collectedRegionIds,
        for (final entry in regions.entries)
          if (entry.value.isNotEmpty &&
              entry.value.every((s) => skills.contains(s.id)))
            entry.key.id,
      };
      final added = collected.difference(before.collectedRegionIds);
      if (skills.length == before.completedSkillIds.length && added.isEmpty) {
        return MathAdventureCompletion(before, const {});
      }
      final next = MathAdventureProgress(
        profileId: profileId,
        grade: grade,
        semester: semester,
        completedSkillIds: skills,
        collectedRegionIds: collected,
      );
      assertCurrent();
      ensureCurrent?.call();
      await _box.put(key, next);
      assertCurrent();
      ensureCurrent?.call();
      return MathAdventureCompletion(next, Set.unmodifiable(added));
    }();
    final tail = work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _tails[key] = tail;
    try {
      return await work;
    } finally {
      if (identical(_tails[key], tail)) _tails.remove(key);
    }
  });
}
