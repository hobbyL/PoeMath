// lib/data/repositories/math_mistake_repository.dart
//
// 层级：data/repositories
// 职责：口算错题仓储。Profile-scoped。

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/repositories/activity_settlement_ledger.dart';

/// 一次重练提交的结果，决定 UI 反馈文案。
enum RepracticeOutcome {
  /// 首次答对，进入巩固队列
  enteredConsolidation,

  /// 通过一关抽查，顺延下一关
  advanced,

  /// 三关全过，彻底掌握
  mastered,

  /// 答错，打回未掌握
  reset,
}

class MathMistakeRepository {
  /// 巩固抽查间隔（天）：答对后依次 1 → 3 → 7 天各抽查一次，三关全过即掌握。
  static const List<int> consolidationIntervals = [1, 3, 7];

  /// 题面归一化 key：同题面 + 同正确答案视为同一条错题。
  /// Unicode 减号统一为 ASCII（与重练弹层归一一致），空白折叠后 md5。
  static String problemKey({
    required String problemText,
    required String correctAnswer,
  }) {
    final normalized =
        problemText.replaceAll('−', '-').replaceAll(RegExp(r'\s+'), ' ').trim();
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
        (a, b) => (b.lastWrongAt ?? b.createdAt)
            .compareTo(a.lastWrongAt ?? a.createdAt),
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
    String? skillId,
    String? semester,
    String? problemJson,
    String? attemptJson,
    String? activityId,
  }) async {
    if (activityId != null) {
      await ActivitySettlementLedger.runOnce(
        channel: ActivitySettlementLedger.userStatsChannel,
        activityId: activityId,
        action: () => recordWrong(
            problemText: problemText,
            correctAnswer: correctAnswer,
            userAnswer: userAnswer,
            problemType: problemType,
            grade: grade,
            errorType: errorType,
            solutionStepsJson: solutionStepsJson,
            skillId: skillId,
            semester: semester,
            problemJson: problemJson,
            attemptJson: attemptJson,),
      );
      return;
    }
    final id = problemKey(
      problemText: problemText,
      correctAnswer: correctAnswer,
    );
    final existing = getById(id)?.copy();
    final now = DateTime.now();

    if (existing != null) {
      existing
        ..userAnswer = userAnswer
        ..problemType = problemType
        ..grade = grade
        ..errorType = errorType
        ..solutionStepsJson = solutionStepsJson ?? existing.solutionStepsJson
        ..skillId = skillId
        ..semester = semester
        ..problemJson = problemJson
        ..attemptJson = attemptJson
        ..wrongCount += 1
        ..lastWrongAt = now
        // 又错一次就不再算掌握，重新回到待复练队列。
        ..isResolved = false
        ..consolidationRound = 0
        ..nextConsolidationDate = null;
      await add(existing);
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
        skillId: skillId,
        semester: semester,
        problemJson: problemJson,
        attemptJson: attemptJson,
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

  /// 获取未解决的错题（未掌握 + 待巩固两组之和）
  List<MathMistake> getUnresolved() {
    return getAll().where((m) => !m.isResolved).toList();
  }

  /// 今日到期的待巩固错题（抽查队列）
  List<MathMistake> getDueConsolidation() {
    return getAll().where((m) => m.isConsolidationDue).toList();
  }

  /// 手动标记错题已解决，不计入重练次数。
  /// 家长逃生口：跳过巩固直接出列，巩固轮次一并清零。
  Future<void> resolve(String id) async {
    final mistake = getById(id);
    if (mistake == null) return;
    mistake
      ..isResolved = true
      ..consolidationRound = 0
      ..nextConsolidationDate = null;
    await mistake.save();
  }

  /// 记录一次已提交的重练结果，推进巩固状态机：
  ///
  /// - 答对且 round == 0：进入巩固队列（round 1，1 天后抽查）
  /// - 答对且 round 1/2：通过本关，按 [consolidationIntervals] 顺延下一关
  /// - 答对且 round == 3：三关全过，出列标记已掌握
  /// - 答错（任何阶段）：打回未掌握，轮次清零
  ///
  /// 返回本次结果用于 UI 文案；记录不存在返回 null。
  Future<RepracticeOutcome?> recordRepracticeResult(
    String id, {
    required bool isCorrect,
  }) async {
    final mistake = getById(id);
    if (mistake == null) return null;

    mistake.retryCount++;

    if (!isCorrect) {
      mistake
        ..isResolved = false
        ..consolidationRound = 0
        ..nextConsolidationDate = null;
      await mistake.save();
      return RepracticeOutcome.reset;
    }

    final RepracticeOutcome outcome;
    if (mistake.consolidationRound >= consolidationIntervals.length) {
      // 末关已通过，这次答对即彻底掌握。
      mistake
        ..isResolved = true
        ..nextConsolidationDate = null;
      outcome = RepracticeOutcome.mastered;
    } else {
      final nextRound = mistake.consolidationRound + 1;
      final now = DateTime.now();
      mistake
        ..consolidationRound = nextRound
        ..nextConsolidationDate = DateTime(now.year, now.month, now.day)
            .add(Duration(days: consolidationIntervals[nextRound - 1]));
      outcome = nextRound == 1
          ? RepracticeOutcome.enteredConsolidation
          : RepracticeOutcome.advanced;
    }

    await mistake.save();
    return outcome;
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
