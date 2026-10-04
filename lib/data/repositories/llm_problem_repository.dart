// lib/data/repositories/llm_problem_repository.dart
//
// 层级：data/repositories
// 职责：LLM 应用题仓储。Profile-scoped。

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/llm_problem.dart';

/// LLM 应用题题库统计快照。
class LlmProblemStats {
  const LlmProblemStats({
    required this.total,
    required this.done,
    required this.attempts,
    required this.correctCount,
  });

  /// 题库总题数。
  final int total;

  /// 已做题数。
  final int done;

  /// 总做题次数。
  final int attempts;

  /// 总答对次数。
  final int correctCount;

  /// 正确率（0-1；无记录时为 0）。
  double get accuracy => attempts > 0 ? correctCount / attempts : 0.0;
}

class LlmProblemRepository {
  /// 批量入库（家长确认后调用）。
  Future<void> addAll(List<LlmProblem> problems) async {
    for (final problem in problems) {
      await HiveBoxes.llmProblems.put(
        ProfileScope.key(problem.id),
        problem,
      );
    }
  }

  /// 按 ID 获取。
  LlmProblem? getById(String id) {
    return HiveBoxes.llmProblems.get(ProfileScope.key(id));
  }

  /// 当前 profile 的全部题目（按创建时间倒序）。
  List<LlmProblem> getAll() {
    return HiveBoxes.llmProblems.values
        .where((p) => p.profileId == ProfileScope.currentId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// 按批次获取。
  List<LlmProblem> byBatch(String batchId) {
    return getAll().where((p) => p.batchId == batchId).toList();
  }

  /// 按条件过滤（null 表示不过滤该项）。
  List<LlmProblem> filter({
    String? topic,
    int? grade,
    String? semester,
    bool? done,
  }) {
    var result = getAll();
    if (topic != null) {
      result = result.where((p) => p.topic == topic).toList();
    }
    if (grade != null) {
      result = result.where((p) => p.grade == grade).toList();
    }
    if (semester != null) {
      result = result.where((p) => p.semester == semester).toList();
    }
    if (done != null) {
      result = result.where((p) => p.done == done).toList();
    }
    return result;
  }

  /// 记录一次作答。
  Future<void> recordAttempt(String id, {required bool correct}) async {
    final problem = getById(id);
    if (problem == null) return;
    problem.attempts++;
    if (correct) problem.correctCount++;
    problem.done = true;
    problem.lastDoneAt = DateTime.now();
    await problem.save();
  }

  /// 删除单题。
  Future<void> delete(String id) async {
    await HiveBoxes.llmProblems.delete(ProfileScope.key(id));
  }

  /// 删除整个批次。
  Future<void> deleteBatch(String batchId) async {
    for (final problem in byBatch(batchId)) {
      await delete(problem.id);
    }
  }

  /// 清空当前 profile 的全部题目。
  Future<void> clearAll() async {
    for (final problem in getAll()) {
      await delete(problem.id);
    }
  }

  /// 当前 profile 的题库统计。
  LlmProblemStats stats() {
    final all = getAll();
    return LlmProblemStats(
      total: all.length,
      done: all.where((p) => p.done).length,
      attempts: all.fold<int>(0, (sum, p) => sum + p.attempts),
      correctCount: all.fold<int>(0, (sum, p) => sum + p.correctCount),
    );
  }
}
