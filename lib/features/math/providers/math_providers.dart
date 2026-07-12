// lib/features/math/providers/math_providers.dart
//
// 口算模块 Riverpod providers。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/data/repositories/math_session_repository.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

// ============ Repositories ============

final mathSessionRepoProvider = Provider<MathSessionRepository>((ref) {
  return MathSessionRepository();
});

final mathMistakeRepoProvider = Provider<MathMistakeRepository>((ref) {
  return MathMistakeRepository();
});

// ============ 练习选择 ============

/// 当前选中年级
final mathGradeProvider = StateProvider<int>((ref) => 1);

/// 当前选中学期
final mathSemesterProvider = StateProvider<String>((ref) => '上');

/// 每组题目数量
final mathBatchSizeProvider = StateProvider<int>((ref) => 10);

// ============ 练习进行中 ============

/// 当前练习的题目列表
final mathProblemsProvider =
    StateProvider<List<MathProblem>>((ref) => const []);

/// 当前题目索引
final mathCurrentIndexProvider = StateProvider<int>((ref) => 0);

/// 本次练习正确数
final mathCorrectCountProvider = StateProvider<int>((ref) => 0);

/// 本次已作答数
final mathAnsweredCountProvider = StateProvider<int>((ref) => 0);

/// 当前题目
final currentProblemProvider = Provider<MathProblem?>((ref) {
  final problems = ref.watch(mathProblemsProvider);
  final index = ref.watch(mathCurrentIndexProvider);
  if (index < 0 || index >= problems.length) return null;
  return problems[index];
});

/// 练习是否结束
final isPracticeFinishedProvider = Provider<bool>((ref) {
  final problems = ref.watch(mathProblemsProvider);
  final answered = ref.watch(mathAnsweredCountProvider);
  return problems.isNotEmpty && answered >= problems.length;
});

// ============ 错题 ============

/// 当前 profile 的所有错题
final mathMistakesProvider = Provider<List<MathMistake>>((ref) {
  final repo = ref.watch(mathMistakeRepoProvider);
  return repo.getAll();
});

/// 未解决的错题
final unresolvedMistakesProvider = Provider<List<MathMistake>>((ref) {
  final repo = ref.watch(mathMistakeRepoProvider);
  return repo.getUnresolved();
});

/// 错题数量
final mistakeCountProvider = Provider<int>((ref) {
  final repo = ref.watch(mathMistakeRepoProvider);
  return repo.totalCount;
});

// ============ 统计 ============

/// 最近练习会话
final recentSessionsProvider = Provider<List<MathSession>>((ref) {
  final repo = ref.watch(mathSessionRepoProvider);
  return repo.getRecent(limit: 5);
});

/// 总做题数
final totalProblemsCountProvider = Provider<int>((ref) {
  final repo = ref.watch(mathSessionRepoProvider);
  return repo.totalProblems;
});

/// 总正确率
final overallAccuracyProvider = Provider<double>((ref) {
  final repo = ref.watch(mathSessionRepoProvider);
  return repo.overallAccuracy;
});

/// 当前年级预设配置
final gradeConfigProvider = Provider<GradeConfig>((ref) {
  final grade = ref.watch(mathGradeProvider);
  final semester = ref.watch(mathSemesterProvider);
  return GradePresets.get(grade, semester);
});
