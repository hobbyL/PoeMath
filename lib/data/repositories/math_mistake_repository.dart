// lib/data/repositories/math_mistake_repository.dart
//
// 层级：data/repositories
// 职责：口算错题仓储。Profile-scoped。

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_mistake.dart';

class MathMistakeRepository {
  /// 题面归一化 key：同题面 + 同正确答案视为同一条错题。
  /// Unicode 减号统一为 ASCII（与重练弹层归一一致），空白折叠后 md5。
  static String problemKey({
    required String problemText,
    required String correctAnswer,
  }) {
    final normalized = problemText
        .replaceAll('−', '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final digest = md5.convert(utf8.encode('$normalized|$correctAnswer'));
    return 'm_$digest';
  }

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
      ..sort(
        (a, b) =>
            (b.lastWrongAt ?? b.createdAt).compareTo(a.lastWrongAt ?? a.createdAt),
      );
  }

  /// 记录一次答错：同题面命中则累加 wrongCount、刷新最近答错时间并
  /// 覆盖本次作答信息；未命中新建一条（wrongCount = 1）。
  /// 作用域为当前 profile（key 由 ProfileScope 拼接，与 [add] 一致）。
  Future<void> recordWrong({
    required String problemText,
    required String correctAnswer,
    required String userAnswer,
    required String problemType,
    required int grade,
    String? errorType,
    String? solutionStepsJson,
  }) async {
    final id = problemKey(
      problemText: problemText,
      correctAnswer: correctAnswer,
    );
    final existing = getById(id);
    final now = DateTime.now();

    if (existing != null) {
      existing
        ..userAnswer = userAnswer
        ..problemType = problemType
        ..grade = grade
        ..errorType = errorType
        ..solutionStepsJson = solutionStepsJson ?? existing.solutionStepsJson
        ..wrongCount += 1
        ..lastWrongAt = now
        // 又错一次就不再算掌握，重新回到待复练队列。
        ..isResolved = false;
      await existing.save();
      return;
    }

    await add(
      MathMistake(
        id: id,
        profileId: ProfileScope.currentId,
        problemText: problemText,
        correctAnswer: correctAnswer,
        userAnswer: userAnswer,
        problemType: problemType,
        grade: grade,
        errorType: errorType,
        solutionStepsJson: solutionStepsJson,
        lastWrongAt: now,
      ),
    );
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
