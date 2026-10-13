// lib/features/math/mistake_consolidation_labels.dart
//
// 层级：features/math
// 职责：错题巩固状态的中文文案单一来源（状态 pill、筛选 chip、重练反馈）。
//       列表页与详情页共用，避免页面之间互相 import。
//       颜色归 UI 侧（依赖 theme），这里只管文案。

import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/features/math/providers/math_providers.dart';

/// 错题卡片状态标签：已掌握 / 待巩固第 N 关 / 未掌握。
String mistakeStatusLabel(MathMistake mistake) {
  if (mistake.isResolved) return '已掌握';
  if (mistake.isConsolidating) {
    return '待巩固 第 ${mistake.consolidationRound} 关';
  }
  return '未掌握';
}

/// 状态筛选 chip 文案。
String mistakeStatusFilterLabel(MistakeStatusFilter filter) {
  return switch (filter) {
    MistakeStatusFilter.unmastered => '未掌握',
    MistakeStatusFilter.consolidating => '待巩固',
    MistakeStatusFilter.mastered => '已掌握',
  };
}

/// 单题重练结果反馈文案。
/// [mistake] 需为状态机执行后的最新记录（轮次已推进）。
String repracticeOutcomeMessage(
  RepracticeOutcome outcome,
  MathMistake mistake,
) {
  const intervals = MathMistakeRepository.consolidationIntervals;
  return switch (outcome) {
    RepracticeOutcome.enteredConsolidation =>
      '答对了！${intervals.first} 天后抽查一次',
    RepracticeOutcome.advanced =>
      '巩固第 ${mistake.consolidationRound - 1} 关通过，'
          '${intervals[mistake.consolidationRound - 1]} 天后再抽查',
    RepracticeOutcome.mastered => '三关全过，已彻底掌握',
    RepracticeOutcome.reset => '抽查答错，回到未掌握，重新练起来',
  };
}
