// lib/features/math/providers/math_providers.dart
//
// 口算模块 Riverpod providers。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/data/repositories/math_session_repository.dart';
import 'package:poemath/data/repositories/challenge_record_repository.dart';
import 'package:poemath/domain/math_entry_kind.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/features/math/math_practice_request.dart';

class NextMathPracticeRequest extends Notifier<MathPracticeRequest?> {
  @override
  MathPracticeRequest? build() => null;

  void setNext(MathPracticeRequest request) => state = request;

  MathPracticeRequest? consume() {
    final request = state;
    state = null;
    return request;
  }
}

final nextMathPracticeRequestProvider =
    NotifierProvider<NextMathPracticeRequest, MathPracticeRequest?>(
        NextMathPracticeRequest.new,);

// ============ Repositories ============
//
// 纯别名：唯一来源见 `data/providers/repository_providers.dart`，
// 避免同类型双实例导致覆写失效（test 覆写 A、业务读 B）。

final Provider<MathSessionRepository> mathSessionRepoProvider =
    mathSessionRepositoryProvider;

final Provider<MathMistakeRepository> mathMistakeRepoProvider =
    mathMistakeRepositoryProvider;

final Provider<ChallengeRecordRepository> challengeRecordRepoProvider =
    challengeRecordRepositoryProvider;

// ============ 练习选择 ============

/// 当前练习使用的年级 —— **只读派生**，一律跟随学习背景。
///
/// 原为可写 `StateProvider`（口算页年级网格与 AppBar 学期按钮可覆盖），
/// 但那套覆盖只改内存、不写 Hive：用户切到三年级后重启即回到学习背景的
/// 值，也不跨 Tab 传播（诗词页读的是另一组 provider）。同一份"当前册次"
/// 存在三个互不同步的来源，故口算页的选择器已移除，这里改为派生。
///
/// `watch` 而非 `read`：学习背景写入后 `settingsRepositoryProvider` 失效
/// （见 `invalidateLearningBackground`），口算页立即跟随，无需重启。
final mathGradeProvider = Provider<int>(
  (ref) => ref.watch(settingsRepositoryProvider).selectedGrade,
);

/// 当前练习使用的学期 —— **只读派生**，理由同 [mathGradeProvider]。
final mathSemesterProvider = Provider<String>(
  (ref) => ref.watch(settingsRepositoryProvider).selectedSemester,
);

/// 口算页显示的一级入口 —— **只读派生**，跟随学习背景的练习类型开关。
final mathEntryKindsProvider = Provider<Set<MathEntryKind>>(
  (ref) => ref.watch(settingsRepositoryProvider).mathEntryKinds,
);

/// 管理下一次练习使用的一次性题数覆盖。
class MathBatchSizeOverrideNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void setNext(int count) {
    if (count <= 0) {
      throw ArgumentError.value(count, 'count', 'must be positive');
    }
    state = count;
  }

  int consumeOr(int fallback) {
    final batchSize = state ?? fallback;
    state = null;
    return batchSize;
  }
}

/// 下一次进入练习页时使用的临时题数；消费后恢复持久化设置。
final mathBatchSizeOverrideProvider =
    NotifierProvider<MathBatchSizeOverrideNotifier, int?>(
  MathBatchSizeOverrideNotifier.new,
);

/// 难度级别
final mathDifficultyProvider =
    StateProvider<DifficultyLevel>((ref) => DifficultyLevel.medium);

/// 练习模式（null = 综合随机，初始值从 settings 中读取）
final mathPracticeModeProvider = StateProvider<ProblemMode?>((ref) {
  final settings = ref.read(settingsRepositoryProvider);
  final modeName = settings.mathPracticeMode;
  if (modeName == null) return null;
  return ProblemMode.values.where((m) => m.name == modeName).firstOrNull;
});

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

// ============ 错题筛选 ============

/// 错题筛选：年级（null = 全部）
final mistakeGradeFilterProvider = StateProvider<int?>((ref) => null);

/// 错题状态筛选项。与模型派生 getter 一一对应，避免与 `isResolved` /
/// `getUnresolved()`（= 未掌握 + 待巩固）的既有语义撞名。
enum MistakeStatusFilter {
  /// 未掌握：isUnmastered
  unmastered,

  /// 待巩固：isConsolidating
  consolidating,

  /// 已掌握：isResolved
  mastered,
}

/// 错题筛选：状态（null = 全部）
final mistakeStatusFilterProvider =
    StateProvider<MistakeStatusFilter?>((ref) => null);

/// 筛选后的错题列表
final filteredMistakesProvider = Provider<List<MathMistake>>((ref) {
  final mistakes = ref.watch(mathMistakesProvider);
  final gradeFilter = ref.watch(mistakeGradeFilterProvider);
  final statusFilter = ref.watch(mistakeStatusFilterProvider);

  var result = mistakes;

  if (gradeFilter != null) {
    result = result.where((m) => m.grade == gradeFilter).toList();
  }

  result = switch (statusFilter) {
    null => result,
    MistakeStatusFilter.unmastered =>
      result.where((m) => m.isUnmastered).toList(),
    MistakeStatusFilter.consolidating =>
      result.where((m) => m.isConsolidating).toList(),
    MistakeStatusFilter.mastered => result.where((m) => m.isResolved).toList(),
  };

  return result;
});

/// 未解决的错题（未掌握 + 待巩固）
final unresolvedMistakesProvider = Provider<List<MathMistake>>((ref) {
  final repo = ref.watch(mathMistakeRepoProvider);
  return repo.getUnresolved();
});

/// 待重练队列：未掌握 + 今日到期的待巩固（批量重练数据源）
final repracticeQueueProvider = Provider<List<MathMistake>>((ref) {
  final mistakes = ref.watch(mathMistakesProvider);
  return mistakes.where((m) => m.isUnmastered || m.isConsolidationDue).toList();
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
  return ref.watch(userStatsProvider).mathTotalProblems;
});

/// 总正确率
final overallAccuracyProvider = Provider<double>((ref) {
  return ref.watch(userStatsProvider).mathAccuracy;
});

/// 当前年级预设配置
final gradeConfigProvider = Provider<GradeConfig>((ref) {
  final grade = ref.watch(mathGradeProvider);
  final semester = ref.watch(mathSemesterProvider);
  return GradePresets.get(grade, semester);
});
