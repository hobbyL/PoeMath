// lib/features/math/math_practice_page.dart
//
// 口算练习页：题目展示 → 用户输入 → 判定反馈 → 分步讲解。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/celebration_dialog.dart';
import 'package:poemath/core/widgets/confetti_overlay.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/achievement_checker.dart';
import 'package:poemath/domain/level_calculator.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/widgets/session_result_dialog.dart';
import 'package:poemath/features/math/widgets/vertical_calc_widget.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

class MathPracticePage extends ConsumerStatefulWidget {
  const MathPracticePage({super.key});

  @override
  ConsumerState<MathPracticePage> createState() => _MathPracticePageState();
}

class _MathPracticePageState extends ConsumerState<MathPracticePage> {
  final _answerController = TextEditingController();
  final _focusNode = FocusNode();
  late final CelebrationController _confettiController;

  /// 当前判定结果（null = 尚未作答）
  AnswerJudgement? _judgement;

  /// 是否展示分步解答
  bool _showSteps = false;

  /// 练习开始时间
  late final DateTime _startTime;

  /// 当前 session ID
  late final String _sessionId;

  /// 当前连续答对数（答错时清零）
  int _consecutiveCorrect = 0;

  /// 本次练习最佳连续答对数
  int _bestConsecutive = 0;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _confettiController = CelebrationController();

    // 延迟到 build 之后初始化题目
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generateProblems();
    });
  }

  void _generateProblems() {
    final grade = ref.read(mathGradeProvider);
    final semester = ref.read(mathSemesterProvider);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final batchSize = settingsRepo.mathBatchSize;
    final practiceMode = ref.read(mathPracticeModeProvider);
    final difficulty = ref.read(mathDifficultyProvider);

    final problems = MathEngine.generateBatch(
      grade: grade,
      semester: semester,
      count: batchSize,
      mode: practiceMode,
      difficulty: difficulty,
    );

    ref.read(mathProblemsProvider.notifier).state = problems;
    ref.read(mathCurrentIndexProvider.notifier).state = 0;
    ref.read(mathCorrectCountProvider.notifier).state = 0;
    ref.read(mathAnsweredCountProvider.notifier).state = 0;
  }

  @override
  void dispose() {
    // 数据已在 _persistProgress() 中逐题保存，无需额外处理
    _answerController.dispose();
    _focusNode.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  /// 每答一题后同步更新 Hive，确保数据立即持久化。
  ///
  /// Hive put() 的内存写入是同步的，后续 provider 读取立刻可见。
  void _persistProgress({required bool isCorrect}) {
    final answered = ref.read(mathAnsweredCountProvider);
    final correctCount = ref.read(mathCorrectCountProvider);
    final duration = DateTime.now().difference(_startTime).inSeconds;

    // 更新运行中的 session（同一 ID 覆盖写入）
    final session = MathSession(
      id: _sessionId,
      profileId: ProfileScope.currentId,
      grade: ref.read(mathGradeProvider),
      problemType: 'mixed',
      totalProblems: answered,
      correctCount: correctCount,
      durationSeconds: duration,
      starsEarned: 0,
      finishedAt: DateTime.now(),
      semester: ref.read(mathSemesterProvider),
      difficulty: ref.read(mathDifficultyProvider).name,
    );
    HiveBoxes.mathSessions.put(ProfileScope.key(_sessionId), session);

    // 增量更新用户统计（每题 +1）
    final statsKey = ProfileScope.key('stats');
    var stats = HiveBoxes.userStats.get(statsKey);
    stats ??= UserStats(profileId: ProfileScope.currentId);
    stats.mathTotalProblems += 1;
    if (isCorrect) stats.mathTotalCorrect += 1;
    if (_bestConsecutive > stats.mathBestStreak) {
      stats.mathBestStreak = _bestConsecutive;
    }
    HiveBoxes.userStats.put(statsKey, stats);

    // 刷新 providers
    ref.invalidate(userStatsProvider);
    ref.invalidate(todayMathCountProvider);
  }

  void _submitAnswer() {
    final problem = ref.read(currentProblemProvider);
    if (problem == null || _judgement != null) return;

    final userAnswer = _answerController.text.trim();
    if (userAnswer.isEmpty) return;

    _processAnswer(problem, userAnswer);
  }

  /// 处理比大小模式的作答。
  void _submitCompareAnswer(String symbol) {
    final problem = ref.read(currentProblemProvider);
    if (problem == null || _judgement != null) return;

    _processAnswer(problem, symbol);
  }

  Future<void> _processAnswer(MathProblem problem, String userAnswer) async {
    final judgement = MathEngine.judge(problem, userAnswer);
    setState(() {
      _judgement = judgement;
      _showSteps = false;
    });

    // 音效和触觉反馈
    final sound = ref.read(soundServiceProvider);
    final haptic = ref.read(hapticServiceProvider);
    if (judgement.isCorrect) {
      sound.play(SoundEffect.correct);
      await haptic.medium();
      _confettiController.play();
    } else {
      sound.play(SoundEffect.wrong);
      await haptic.heavy();
    }

    ref.read(mathAnsweredCountProvider.notifier).update((s) => s + 1);
    if (judgement.isCorrect) {
      ref.read(mathCorrectCountProvider.notifier).update((s) => s + 1);
      _consecutiveCorrect++;
      if (_consecutiveCorrect > _bestConsecutive) {
        _bestConsecutive = _consecutiveCorrect;
      }
    } else {
      _consecutiveCorrect = 0;
      _recordMistake(problem, userAnswer, judgement);
    }

    // 每答一题就同步保存到 Hive
    _persistProgress(isCorrect: judgement.isCorrect);
  }

  void _recordMistake(
    MathProblem problem,
    String userAnswer,
    AnswerJudgement judgement,
  ) {
    final grade = ref.read(mathGradeProvider);
    final repo = ref.read(mathMistakeRepoProvider);

    final mistake = MathMistake(
      id: '${_sessionId}_${ref.read(mathCurrentIndexProvider)}',
      profileId: ProfileScope.currentId,
      problemText: problem.problemText,
      correctAnswer: problem.answerText,
      userAnswer: userAnswer,
      problemType: _problemTypeLabel(problem),
      grade: grade,
      errorType: judgement.diagnosis?.category,
      solutionStepsJson: _stepsToJson(judgement.correctSteps),
    );

    repo.add(mistake);
    ref.invalidate(mathMistakeRepoProvider);
  }

  String _problemTypeLabel(MathProblem problem) {
    if (problem.resultForm == ResultForm.fraction) return 'fraction';
    if (problem.resultForm == ResultForm.decimal) return 'decimal';
    if (problem.resultForm == ResultForm.withRemainder) return 'remainder';
    if (problem.operators.length > 1) return 'mixed';
    final op = problem.operators.first;
    switch (op) {
      case Operator.add:
        return 'addition';
      case Operator.subtract:
        return 'subtraction';
      case Operator.multiply:
        return 'multiplication';
      case Operator.divide:
        return 'division';
    }
  }

  String? _stepsToJson(List<SolutionStep> steps) {
    if (steps.isEmpty) return null;
    // 简单的序列化：description|||expression|||resultHint
    return steps
        .map((s) => '${s.description}|||${s.expression}|||${s.resultHint}')
        .join('\n');
  }

  /// 是否正在结算中，防止多次调用。
  bool _isFinishing = false;

  Future<void> _nextProblem() async {
    final problems = ref.read(mathProblemsProvider);
    final currentIndex = ref.read(mathCurrentIndexProvider);

    if (currentIndex + 1 >= problems.length) {
      if (!_isFinishing) {
        _isFinishing = true;
        await _finishSession();
      }
      return;
    }

    ref.read(mathCurrentIndexProvider.notifier).update((s) => s + 1);
    _answerController.clear();
    setState(() {
      _judgement = null;
      _showSteps = false;
    });
    _focusNode.requestFocus();
  }

  Future<void> _finishSession() async {
    final grade = ref.read(mathGradeProvider);
    final problems = ref.read(mathProblemsProvider);
    final correctCount = ref.read(mathCorrectCountProvider);
    final duration = DateTime.now().difference(_startTime).inSeconds;

    // 计算星星：全对 → 3星, 90%+ → 2星, 70%+ → 1星
    final accuracy = problems.isNotEmpty ? correctCount / problems.length : 0.0;
    final stars = accuracy >= 1.0
        ? 3
        : accuracy >= 0.9
            ? 2
            : accuracy >= 0.7
                ? 1
                : 0;

    // 保存 session
    final session = MathSession(
      id: _sessionId,
      profileId: ProfileScope.currentId,
      grade: grade,
      problemType: 'mixed',
      totalProblems: problems.length,
      correctCount: correctCount,
      durationSeconds: duration,
      starsEarned: stars,
      finishedAt: DateTime.now(),
      semester: ref.read(mathSemesterProvider),
      difficulty: ref.read(mathDifficultyProvider).name,
    );

    final repo = ref.read(mathSessionRepoProvider);
    await repo.save(session);

    // 做题数和连对数已在 _persistProgress() 中逐题更新，只需添加星星
    final statsRepo = ref.read(userStatsRepoProvider);
    if (stars > 0) {
      await statsRepo.addStars(stars);
    }

    // 等级自动计算
    final updatedStats = statsRepo.get();
    final newLevel = LevelCalculator.calculate(updatedStats.totalStars);
    if (newLevel != updatedStats.level) {
      await statsRepo.updateLevel(newLevel);
      if (mounted) {
        showCelebration(
          context,
          type: CelebrationType.levelUp,
          subtitle: newLevel < UserStats.levelNames.length
              ? UserStats.levelNames[newLevel]
              : '诗仙',
        );
      }
    }

    // 成就自动检查
    final achievementRepo = ref.read(achievementRepoProvider);
    final checker = AchievementChecker(achievementRepo);
    await checker.check(statsRepo.get());

    // 刷新首页统计 providers
    ref.invalidate(userStatsProvider);
    ref.invalidate(todayMathCountProvider);
    ref.invalidate(unlockedAchievementsCountProvider);
    ref.invalidate(recentSessionsProvider);
    ref.invalidate(totalProblemsCountProvider);
    ref.invalidate(overallAccuracyProvider);

    if (!mounted) return;

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SessionResultDialog(
        totalProblems: problems.length,
        correctCount: correctCount,
        durationSeconds: duration,
        starsEarned: stars,
      ),
    );

    if (!mounted) return;

    if (action == 'review') {
      context.pushReplacement(AppRoutes.mathMistake);
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final problems = ref.watch(mathProblemsProvider);
    final currentIndex = ref.watch(mathCurrentIndexProvider);
    final correctCount = ref.watch(mathCorrectCountProvider);
    final problem = ref.watch(currentProblemProvider);
    final theme = Theme.of(context);

    if (problems.isEmpty || problem == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('口算练习')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${currentIndex + 1} / ${problems.length}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: SpacingTokens.md),
            child: Center(
              child: Text(
                '✓ $correctCount',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: ColorTokens.success,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(SpacingTokens.lg),
            child: Column(
              children: [
            // 进度条
            LinearProgressIndicator(
              value: (currentIndex + 1) / problems.length,
              backgroundColor:
                  theme.colorScheme.primary.withValues(alpha: 0.1),
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: SpacingTokens.xl),

            // 题目显示
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 题目文本（竖式模式特殊展示）
                    KeyedSubtree(
                      key: ValueKey('q_$currentIndex'),
                      child: (problem.mode == ProblemMode.vertical
                              ? VerticalCalcWidget(
                                  problem: problem,
                                  showAnswer: _judgement != null,
                                ) as Widget
                              : Text(
                                  problem.problemText,
                                  style: TypographyTokens.mathProblemStyle(
                                    color: theme.colorScheme.onSurface,
                                  ),
                                  textAlign: TextAlign.center,
                                ))
                          .animate()
                          .fadeIn(duration: 350.ms)
                          .slideX(
                            begin: 0.12,
                            end: 0,
                            duration: 350.ms,
                            curve: Curves.easeOutCubic,
                          ),
                    ),
                    const SizedBox(height: SpacingTokens.xl),

                    // 判定反馈
                    if (_judgement != null) ...[
                      _buildJudgementFeedback(context)
                          .animate()
                          .fadeIn(duration: 300.ms)
                          .scale(
                            begin: const Offset(0.9, 0.9),
                            end: const Offset(1, 1),
                            duration: 300.ms,
                            curve: Curves.easeOutBack,
                          )
                          .then()
                          .shimmer(
                            delay: 200.ms,
                            duration: 600.ms,
                            color: _judgement!.isCorrect
                                ? ColorTokens.success.withValues(alpha: 0.3)
                                : Colors.transparent,
                          ),
                      const SizedBox(height: SpacingTokens.md),
                      if (_judgement!.correctSteps.isNotEmpty)
                        _buildStepsSection(context),
                    ],
                  ],
                ),
              ),
            ),

            // 答案输入区
            const SizedBox(height: SpacingTokens.md),
            _buildAnswerInput(context),
          ],
        ),
      ),
      ConfettiOverlay(controller: _confettiController),
        ],
      ),
    );
  }

  Widget _buildJudgementFeedback(BuildContext context) {
    final judgement = _judgement!;
    final problem = ref.read(currentProblemProvider)!;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SpacingTokens.md),
      decoration: BoxDecoration(
        color: judgement.isCorrect
            ? ColorTokens.success.withValues(alpha: 0.15)
            : ColorTokens.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        border: Border.all(
          color: judgement.isCorrect
              ? ColorTokens.success
              : ColorTokens.error,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                judgement.isCorrect
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                color: judgement.isCorrect
                    ? ColorTokens.success
                    : ColorTokens.error,
              ),
              const SizedBox(width: SpacingTokens.sm),
              Text(
                judgement.isCorrect ? '回答正确！' : '答错了',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: judgement.isCorrect
                      ? ColorTokens.success
                      : ColorTokens.error,
                ),
              ),
            ],
          ),
          if (!judgement.isCorrect) ...[
            const SizedBox(height: SpacingTokens.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '正确答案：${problem.answerText}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (judgement.diagnosis != null) ...[
              const SizedBox(height: SpacingTokens.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  judgement.diagnosis!.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildStepsSection(BuildContext context) {
    final judgement = _judgement!;
    final theme = Theme.of(context);

    return Column(
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _showSteps = !_showSteps),
          icon: Icon(_showSteps ? Icons.expand_less : Icons.expand_more),
          label: Text(_showSteps ? '收起解题步骤' : '查看解题步骤'),
        ),
        if (_showSteps)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(SpacingTokens.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius:
                  BorderRadius.circular(SpacingTokens.radiusMedium),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < judgement.correctSteps.length; i++) ...[
                  if (i > 0) const SizedBox(height: SpacingTokens.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${i + 1}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: SpacingTokens.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              judgement.correctSteps[i].description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            if (judgement
                                .correctSteps[i].resultHint.isNotEmpty)
                              Text(
                                judgement.correctSteps[i].resultHint,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAnswerInput(BuildContext context) {
    if (_judgement != null) {
      // 已作答，显示"下一题"按钮
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _nextProblem,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(
            ref.read(mathCurrentIndexProvider) + 1 >=
                    ref.read(mathProblemsProvider).length
                ? '查看成绩'
                : '下一题',
          ),
        ),
      )
          .animate()
          .fadeIn(duration: 250.ms)
          .slideY(
            begin: 0.2,
            end: 0,
            duration: 250.ms,
            curve: Curves.easeOutCubic,
          );
    }

    // 比大小模式：显示 > < = 三个按钮
    final problem = ref.watch(currentProblemProvider);
    if (problem?.mode == ProblemMode.compare) {
      return _buildCompareButtons(context);
    }

    // 普通模式：显示输入框
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _answerController,
            focusNode: _focusNode,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: TypographyTokens.fsTitle,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              hintText: '输入答案',
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(SpacingTokens.radiusMedium),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.md,
                vertical: SpacingTokens.md,
              ),
            ),
            onSubmitted: (_) => _submitAnswer(),
          ),
        ),
        const SizedBox(width: SpacingTokens.md),
        SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: _submitAnswer,
            child: const Text('确定'),
          ),
        ),
      ],
    );
  }

  /// 比大小模式的三个按钮：> < =
  Widget _buildCompareButtons(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final symbol in const ['<', '=', '>']) ...[
          if (symbol != '<') const SizedBox(width: SpacingTokens.md),
          Expanded(
            child: SizedBox(
              height: 64,
              child: OutlinedButton(
                onPressed: () => _submitCompareAnswer(symbol),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(SpacingTokens.radiusMedium),
                  ),
                ),
                child: Text(
                  symbol,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
