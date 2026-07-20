// lib/data/repositories/math_mistake_repository.dart
//
// 层级：data/repositories
// 职责：口算错题仓储。Profile-scoped。

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_mistake.dart';

class MathMistakeRepository {
  /// 记录一个错题
  Future<void> add(MathMistake mistake) async {
    final key = ProfileScope.key(mistake.id);
    await HiveBoxes.mathMistakes.put(key, mistake);
  }

  /// 按 ID 获取
  MathMistake? getById(String id) {
    return HiveBoxes.mathMistakes.get(ProfileScope.key(id));
  }

  /// 获取当前 profile 的所有错题
  List<MathMistake> getAll() {
    return HiveBoxes.mathMistakes.values
        .where((m) => m.profileId == ProfileScope.currentId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// 按题型筛选
  List<MathMistake> byType(String problemType) {
    return getAll().where((m) => m.problemType == problemType).toList();
  }

  /// 按年级筛选
  List<MathMistake> byGrade(int grade) {
    return getAll().where((m) => m.grade == grade).toList();
  }

  /// 获取未解决的错题
  List<MathMistake> getUnresolved() {
    return getAll().where((m) => !m.isResolved).toList();
  }

  /// 手动标记错题已解决，不计入重练次数
  Future<void> resolve(String id) async {
    final mistake = getById(id);
    if (mistake == null) return;
    mistake.isResolved = true;
    await mistake.save();
  }

  /// 记录一次已提交的重练结果；答对时同时标记为已解决
  Future<void> recordRetryResult(
    String id, {
    required bool isCorrect,
  }) async {
    final mistake = getById(id);
    if (mistake == null) return;
    mistake.retryCount++;
    if (isCorrect) mistake.isResolved = true;
    await mistake.save();
  }

  /// 错题总数
  int get totalCount => getAll().length;

  /// 未解决数
  int get unresolvedCount => getUnresolved().length;

  /// 删除某个错题
  Future<void> delete(String id) async {
    await HiveBoxes.mathMistakes.delete(ProfileScope.key(id));
  }
}
