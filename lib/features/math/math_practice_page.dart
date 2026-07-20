// lib/features/math/math_practice_page.dart
//
// 口算练习页：题目展示 → 用户输入 → 判定反馈 → 分步讲解。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/celebration_dialog.dart';
import 'package:poemath/core/widgets/confetti_overlay.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/achievement_check_helper.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/widgets/math_text.dart';
import 'package:poemath/features/math/widgets/number_keypad.dart';
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

  /// 每题作答记录
  final List<ProblemRecord> _problemRecords = [];

  /// 练习开始时间
  late DateTime _startTime;

  /// 当前 session ID
  late String _sessionId;

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
    final difficulty = DifficultyLevel.values.firstWhere(
      (d) => d.name == settingsRepo.mathDifficulty,
      orElse: () => DifficultyLevel.medium,
    );

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
      difficulty: ref.read(settingsRepositoryProvider).mathDifficulty,
      problemsJson: jsonEncode(
        _problemRecords.map((r) => r.toJson()).toList(),
      ),
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

    // 记录本题详情
    _problemRecords.add(
      ProblemRecord(
        problemText: problem.problemText,
        answerText: problem.answerText,
        userAnswer: userAnswer,
        isCorrect: judgement.isCorrect,
      ),
    );

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
      difficulty: ref.read(settingsRepositoryProvider).mathDifficulty,
      problemsJson: jsonEncode(
        _problemRecords.map((r) => r.toJson()).toList(),
      ),
    );

    final repo = ref.read(mathSessionRepoProvider);
    await repo.save(session);

    // 做题数和连对数已在 _persistProgress() 中逐题更新，只需添加星星
    final statsRepo = ref.read(userStatsRepoProvider);
    final levelBeforeReward = statsRepo.get().level;
    if (stars > 0) {
      await statsRepo.addStars(stars);
    }
    await ref.read(checkInRepoProvider).updateToday(
      addMathTotal: problems.length,
      addMathCorrect: correctCount,
      addStars: stars,
      addDuration: duration,
    );

    // addStars 会同步重算等级；页面仅负责展示升级反馈。
    final updatedStats = statsRepo.get();
    if (updatedStats.level > levelBeforeReward) {
      if (mounted) {
        showCelebration(
          context,
          type: CelebrationType.levelUp,
          subtitle: updatedStats.level < UserStats.levelNames.length
              ? UserStats.levelNames[updatedStats.level]
              : '诗仙',
        );
      }
    }

    // 成就自动检查
    final newlyUnlocked = await checkAchievements(ref, latestSession: session);

    // 刷新首页统计 providers
    ref.invalidate(userStatsProvider);
    ref.invalidate(todayCheckInProvider);
    ref.invalidate(todayMathCountProvider);
    ref.invalidate(unlockedAchievementsCountProvider);
    ref.invalidate(recentSessionsProvider);
    ref.invalidate(totalProblemsCountProvider);
    ref.invalidate(overallAccuracyProvider);

    if (!mounted) return;

    // 成就解锁庆祝
    if (newlyUnlocked.isNotEmpty) {
      _confettiController.play();
      final names = newlyUnlocked.map((a) => a.title).join('、');
      showCelebration(
        context,
        type: CelebrationType.achievement,
        subtitle: names,
      );
      // 等庆祝弹窗自动关闭后再弹结果
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      if (!mounted) return;
    }

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
    } else if (action == 'retry') {
      _retrySession();
    } else {
      // 'home' 或 dismiss → 返回首页
      context.pop();
    }
  }

  /// 重置答题状态并重新生成同类题目。
  void _retrySession() {
    _answerController.clear();
    _problemRecords.clear();
    _consecutiveCorrect = 0;
    _bestConsecutive = 0;
    _isFinishing = false;
    _startTime = DateTime.now();
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    setState(() {
      _judgement = null;
      _showSteps = false;
    });
    _generateProblems();
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
                  color: theme.semantic.success,
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
            padding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.md,
              vertical: SpacingTokens.sm,
            ),
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
            const SizedBox(height: SpacingTokens.md),

            // 题目显示
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
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
                              : MathText(
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
                                ? theme.semantic.success.withValues(alpha: 0.3)
                                : Colors.transparent,
                          ),
                      const SizedBox(height: SpacingTokens.md),
                      if (_judgement!.correctSteps.isNotEmpty)
                        _buildStepsSection(context),
                    ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // 答案输入区
            const SizedBox(height: SpacingTokens.sm),
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
            ? theme.semantic.success.withValues(alpha: 0.15)
            : theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        border: Border.all(
          width: 2,
          color: judgement.isCorrect
              ? theme.semantic.success
              : theme.colorScheme.tertiary.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                judgement.isCorrect
                    ? Icons.check_circle_rounded
                    : Icons.lightbulb_outline_rounded,
                color: judgement.isCorrect
                    ? theme.semantic.success
                    : theme.colorScheme.tertiary,
                size: 24,
              ),
              const SizedBox(width: SpacingTokens.sm),
              Text(
                judgement.isCorrect ? '回答正确！' : '再想想',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: judgement.isCorrect
                      ? theme.semantic.success
                      : theme.colorScheme.onTertiaryContainer,
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
          ColoredCard(
            color: theme.colorScheme.primary,
            width: double.infinity,
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

    // 余数模式：显示商…余格式提示
    final isRemainder = problem?.resultForm == ResultForm.withRemainder;

    // 普通模式：显示自定义数字键盘
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 答案输入框（只读，通过键盘输入）
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: SpacingTokens.md,
            vertical: SpacingTokens.lg,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _answerController.text.isEmpty
                    ? (isRemainder ? '输入答案（格式：商…余）' : '输入答案')
                    : _answerController.text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: TypographyTokens.fsTitle,
                  fontWeight: FontWeight.bold,
                  color: _answerController.text.isEmpty
                      ? theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.5)
                      : theme.colorScheme.onSurface,
                ),
              ),
              if (isRemainder && _answerController.text.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: SpacingTokens.xs),
                  child: Text(
                    '例如：3…2',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: SpacingTokens.md),
        // 儿童数字键盘
        NumberKeypad(
          onNumberTap: (digit) {
            setState(() {
              _answerController.text += digit;
            });
          },
          onBackspace: () {
            setState(() {
              if (_answerController.text.isNotEmpty) {
                _answerController.text = _answerController.text.substring(
                  0,
                  _answerController.text.length - 1,
                );
              }
            });
          },
          onSubmit: _submitAnswer,
          submitEnabled: _answerController.text.isNotEmpty,
          showEllipsis: isRemainder,
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
