// lib/features/math/word_problem/word_problem_providers.dart
//
// 层级：features/math/word_problem
// 职责：应用题 AI 出题的 Riverpod Provider —— 题库 repository、
//       LLM 配置读取、题库列表与统计（入库/删除/做题后刷新）。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/llm_problem_repository.dart';

/// 应用题题库 repository。
final llmProblemRepositoryProvider = Provider<LlmProblemRepository>((ref) {
  return LlmProblemRepository();
});

/// LLM 配置（null = 未配置，生成页显示引导态）。
final llmConfigProvider = FutureProvider.autoDispose((ref) async {
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  return settingsRepo.readLlmConfig();
});

/// 题库变更信号：入库/删除/做题后递增以刷新列表与统计。
final llmLibraryVersionProvider = StateProvider<int>((ref) => 0);

/// 当前 profile 的全部应用题（按创建时间倒序）。
final llmProblemListProvider = Provider<List<LlmProblem>>((ref) {
  ref.watch(llmLibraryVersionProvider);
  return ref.watch(llmProblemRepositoryProvider).getAll();
});

/// 题库统计。
final llmLibraryStatsProvider = Provider<LlmProblemStats>((ref) {
  ref.watch(llmLibraryVersionProvider);
  return ref.watch(llmProblemRepositoryProvider).stats();
});
