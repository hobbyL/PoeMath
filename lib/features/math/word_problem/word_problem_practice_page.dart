// lib/features/math/word_problem/word_problem_practice_page.dart
//
// 层级：features/math/word_problem
// 职责：应用题练习页 —— 题库离线消费。判分/讲解本地完成；
//       结算链复用口算（MathSession problemType 'llm_word_problem'
//       计入每日目标；星星/打卡/学习活动/成就同步）。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/celebration_dialog.dart';
import 'package:poemath/core/widgets/confetti_overlay.dart';
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/achievement_check_helper.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/widgets/number_keypad.dart';
import 'package:poemath/features/math/widgets/session_result_dialog.dart';
import 'package:poemath/features/math/word_problem/word_problem_providers.dart';

class WordProblemPracticePage extends ConsumerStatefulWidget {
  const WordProblemPracticePage({super.key, required this.problems});

  final List<LlmProblem> problems;

  @override
  ConsumerState<WordProblemPracticePage> createState() =>
      _WordProblemPracticePageState();
}

class _WordProblemPracticePageState
    extends ConsumerState<WordProblemPracticePage> {
  final _answerController = TextEditingController();
  late final CelebrationController _confettiController;

  /// 当前题判定（null = 尚未作答）。
  bool? _isCorrect;

  /// 是否展开讲解。
  bool _showExplanation = false;

  /// 每题作答记录。
  final List<ProblemRecord> _problemRecords = [];

  int _currentIndex = 0;
  int _correctCount = 0;

  late DateTime _startTime;
  late String _sessionId;
  DateTime? _completedAt;
  bool _submitting = false;
  bool _isFinishing = false;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _sessionId = DateTime.now().microsecondsSinceEpoch.toString();
    _confettiController = CelebrationController();
  }

  @override
  void dispose() {
    _answerController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  LlmProblem get _current => widget.problems[_currentIndex];

  /// 判分：输入解析为 num 后与答案精确相等（"16" / "16.0" 均通过）。
  bool _judge(String userAnswer) {
    final parsed = num.tryParse(userAnswer.trim());
    return parsed != null && parsed == _current.answer;
  }

  /// 每答一题后同步写 Hive（MathSession 同 ID 覆盖 + userStats 增量）。
  ///
  /// 「同步」指内存可见性而非落盘：Hive `put()` 同步更新内存中的 box，
  /// 之后的读取（含刚 `invalidate` 的 provider）立即拿到新值。磁盘 flush
  /// 异步进行，这里刻意不 `await`，避免拖慢答题；代价是进程被强杀时可能
  /// 丢掉最后一次 flush 之前的数据。真正需要「写完再读」的路径（如
  /// 错题记录）另见 `_recordMistake`，那里是 `await` 后才 invalidate。
  void _persistProgress({required bool isCorrect}) {
    final answered = _currentIndex + 1;
    final duration = DateTime.now().difference(_startTime).inSeconds;
    final first = widget.problems.first;

    final session = MathSession(
      id: _sessionId,
      profileId: ProfileScope.currentId,
      grade: first.grade,
      problemType: 'llm_word_problem',
      totalProblems: answered,
      correctCount: _correctCount,
      durationSeconds: duration,
      starsEarned: 0,
      finishedAt: DateTime.now(),
      semester: first.semester,
      difficulty: _difficultyLabel(first.difficulty),
      problemsJson: jsonEncode(
        _problemRecords.map((r) => r.toJson()).toList(),
      ),
    );
    unawaited(
      ref
          .read(mathSessionRepositoryProvider)
          .save(session)
          .catchError((Object error, StackTrace stack) {
        AppLogger.e(
          '练习快照保存失败',
          tag: 'MathPractice',
          error: error,
          stackTrace: stack,
        );
      }),
    );

    // 增量更新用户统计（每题 +1），与口算练习页共用同一仓储写入路径。
    unawaited(
      ref
          .read(userStatsRepositoryProvider)
          .recordMathAttempt(
            isCorrect: isCorrect,
            bestStreak: 0,
          )
          .catchError((Object error, StackTrace stackTrace) {
        AppLogger.e(
          '应用题答题进度落库失败',
          tag: 'WordProblemPractice',
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );

    ref.invalidate(userStatsProvider);
    ref.invalidate(todayMathCountProvider);
  }

  static String _difficultyLabel(int difficulty) {
    if (difficulty <= 2) return 'easy';
    if (difficulty == 3) return 'medium';
    return 'hard';
  }

  /// 记录错题到 Hive。
  ///
  /// 必须 await 后再 `invalidate`：写入未完成就失效 provider 会让错题本
  /// 读到旧快照；写入失败时记日志并跳过 invalidate（无新数据可读）。
  Future<void> _recordMistake(String userAnswer) async {
    final problem = _current;
    final repo = ref.read(mathMistakeRepoProvider);

    try {
      await repo.recordWrong(
        problemText: problem.questionText,
        correctAnswer: problem.answer.toString(),
        userAnswer: userAnswer,
        problemType: 'llm_word_problem',
        grade: problem.grade,
        // 应用题讲解是自然语言文本，直接存储。
        solutionStepsJson:
            problem.explanation.isEmpty ? null : problem.explanation,
      );
    } on Object catch (error, stackTrace) {
      // Hive IO 失败抛的是 `HiveError extends Error`，`on Exception` 捕不到；
      // 此处位于 UI 边界，兜底后仅记日志，不打断答题流程。
      AppLogger.e(
        '应用题错题落库失败',
        tag: 'WordProblemPractice',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }
    if (!mounted) return;
    ref.invalidate(mathMistakeRepoProvider);
  }

  Future<void> _submitAnswer() async {
    if (_isCorrect != null || _submitting) return;
    final userAnswer = _answerController.text.trim();
    if (userAnswer.isEmpty) return;
    final problem = _current;
    final problemRepo = ref.read(llmProblemRepositoryProvider);
    final isCorrect = _judge(userAnswer);
    setState(() {
      _submitting = true;
      _isCorrect = isCorrect;
      _showExplanation = false;
    });

    final sound = ref.read(soundServiceProvider);
    final haptic = ref.read(hapticServiceProvider);
    // 先提交内存状态和逐题持久化，再等待不影响答案归属的反馈。
    if (isCorrect) _correctCount++;
    _problemRecords.add(
      ProblemRecord(
        problemText: problem.questionText,
        answerText: '${problem.answer}${problem.unit}',
        userAnswer: userAnswer,
        isCorrect: isCorrect,
      ),
    );
    _persistProgress(isCorrect: isCorrect);
    final mistakeWrite =
        isCorrect ? Future<void>.value() : _recordMistake(userAnswer);
    try {
      await problemRepo.recordAttempt(problem.id, correct: isCorrect);
      await mistakeWrite;
      if (isCorrect) {
        sound.play(SoundEffect.correct);
        await haptic.medium();
        if (mounted) _confettiController.play();
      } else {
        sound.play(SoundEffect.wrong);
        await haptic.heavy();
      }
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '应用题答题记录失败',
        tag: 'WordProblemPractice',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _submitting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _nextProblem() async {
    if (_submitting || !mounted) return;
    if (_currentIndex + 1 >= widget.problems.length) {
      if (!_isFinishing) {
        _isFinishing = true;
        await _finishSession();
      }
      return;
    }
    setState(() {
      _currentIndex++;
      _isCorrect = null;
      _showExplanation = false;
    });
    _answerController.clear();
  }

  Future<void> _finishSession() async {
    // 结算主体包 `try/finally`：任一 await 抛错都必须复位 `_isFinishing`，
    // 否则 `_nextProblem` 的防重入守卫会永久拦住后续结算。
    try {
      await _settleSession();
    } finally {
      _isFinishing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _settleSession() async {
    final problems = widget.problems;
    final correctCount = _correctCount;
    final completedAt = _completedAt ??= DateTime.now();
    final duration = completedAt.difference(_startTime).inSeconds;
    final first = problems.first;

    final stars = LearningRewardCalculator.calculateStars(
      activityType: LearningActivityType.wordProblem,
      totalItems: problems.length,
      successfulItems: correctCount,
    );

    final session = MathSession(
      id: _sessionId,
      profileId: ProfileScope.currentId,
      grade: first.grade,
      problemType: 'llm_word_problem',
      totalProblems: problems.length,
      correctCount: correctCount,
      durationSeconds: duration,
      starsEarned: stars,
      finishedAt: completedAt,
      semester: first.semester,
      difficulty: _difficultyLabel(first.difficulty),
      problemsJson: jsonEncode(
        _problemRecords.map((r) => r.toJson()).toList(),
      ),
    );

    final repo = ref.read(mathSessionRepoProvider);
    final activityRepo = ref.read(learningActivityRepositoryProvider);
    final statsRepo = ref.read(userStatsRepoProvider);
    final checkInRepo = ref.read(checkInRepoProvider);
    await repo.save(session);
    final activityId = 'llm_word_practice:${session.id}';
    await activityRepo.record(
      id: activityId,
      activityType: LearningActivityType.wordProblem,
      totalItems: problems.length,
      successfulItems: correctCount,
      starsEarned: stars,
      durationSeconds: duration,
      completedAt: completedAt,
    );

    // 做题数已在 _persistProgress() 中逐题更新，只需添加星星。
    final levelBeforeReward = statsRepo.get().level;
    if (stars > 0) {
      await statsRepo.addStars(stars, activityId: activityId);
    }
    await checkInRepo.updateToday(
      activityId: activityId,
      addMathTotal: problems.length,
      addMathCorrect: correctCount,
      addStars: stars,
      addDuration: duration,
    );

    final updatedStats = statsRepo.get();
    if (updatedStats.level > levelBeforeReward && mounted) {
      showCelebration(
        context,
        type: CelebrationType.levelUp,
        subtitle: updatedStats.level < UserStats.levelNames.length
            ? UserStats.levelNames[updatedStats.level]
            : '诗仙',
      );
    }

    if (!mounted) return;
    final newlyUnlocked = await checkAchievements(ref, latestSession: session);
    if (!mounted) return;

    ref.invalidate(userStatsProvider);
    ref.invalidate(todayCheckInProvider);
    ref.invalidate(todayMathCountProvider);
    ref.invalidate(unlockedAchievementsCountProvider);
    ref.invalidate(recentSessionsProvider);
    ref.invalidate(totalProblemsCountProvider);
    ref.invalidate(overallAccuracyProvider);

    if (!mounted) return;

    if (newlyUnlocked.isNotEmpty) {
      _confettiController.play();
      final names = newlyUnlocked.map((a) => a.title).join('、');
      // await 到庆祝弹窗关闭为止，再弹结果对话框（避免两窗重叠）。
      await showCelebration(
        context,
        type: CelebrationType.achievement,
        subtitle: names,
      );
      if (!mounted) return;
    }

    final action = await showDialog<String>(
      context: context,
      // 允许点击空白收起：返回值 null 与右上角关闭图标同为「返回题库」。
      barrierDismissible: true,
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
      // null（关闭图标 / 点击空白）→ 返回题库。
      // 栈内没有上一页时（深链直达 / 进程恢复）pop 会断言失败，改为直接去题库。
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.wordProblemLibrary);
      }
    }
  }

  /// 重置答题状态并重新开始同一套题。
  void _retrySession() {
    _answerController.clear();
    _problemRecords.clear();
    _isFinishing = false;
    _startTime = DateTime.now();
    _sessionId = DateTime.now().microsecondsSinceEpoch.toString();
    _completedAt = null;
    setState(() {
      _currentIndex = 0;
      _correctCount = 0;
      _isCorrect = null;
      _showExplanation = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = _current;
    final total = widget.problems.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('${_currentIndex + 1} / $total'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: SpacingTokens.md),
            child: Center(
              child: Text(
                '✓ $_correctCount',
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
                LinearProgressIndicator(
                  value: (_currentIndex + 1) / total,
                  backgroundColor:
                      theme.colorScheme.primary.withValues(alpha: 0.1),
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: SpacingTokens.md),
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
                              // 应用题题面（长文本自适应）
                              KeyedSubtree(
                                key: ValueKey('q_$_currentIndex'),
                                child: Text(
                                  problem.questionText,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    height: 1.6,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ).animate().fadeIn(duration: 350.ms).slideX(
                                      begin: 0.12,
                                      end: 0,
                                      duration: 350.ms,
                                      curve: Curves.easeOutCubic,
                                    ),
                              ),
                              const SizedBox(height: SpacingTokens.xl),

                              if (_isCorrect != null) ...[
                                _buildJudgementFeedback(context)
                                    .animate()
                                    .fadeIn(duration: 300.ms)
                                    .scale(
                                      begin: const Offset(0.9, 0.9),
                                      end: const Offset(1, 1),
                                      duration: 300.ms,
                                      curve: Curves.easeOutBack,
                                    ),
                                const SizedBox(height: SpacingTokens.md),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
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
    final theme = Theme.of(context);
    final problem = _current;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SpacingTokens.md),
      decoration: BoxDecoration(
        color: _isCorrect!
            ? theme.semantic.success.withValues(alpha: 0.15)
            : theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        border: Border.all(
          width: 2,
          color: _isCorrect!
              ? theme.semantic.success
              : theme.colorScheme.tertiary.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                _isCorrect!
                    ? Icons.check_circle_rounded
                    : Icons.lightbulb_outline_rounded,
                color: _isCorrect!
                    ? theme.semantic.success
                    : theme.colorScheme.tertiary,
                size: 24,
              ),
              const SizedBox(width: SpacingTokens.sm),
              Text(
                _isCorrect! ? '回答正确！' : '再想想',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _isCorrect!
                      ? theme.semantic.success
                      : theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ],
          ),
          if (!_isCorrect!) ...[
            const SizedBox(height: SpacingTokens.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '正确答案：${problem.answer}${problem.unit}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (problem.explanation.trim().isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.xs),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _showExplanation = !_showExplanation),
                icon: Icon(
                  _showExplanation ? Icons.expand_less : Icons.expand_more,
                ),
                label: Text(
                  _showExplanation ? '收起讲解' : '查看讲解',
                ),
              ),
              if (_showExplanation)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    problem.explanation,
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

  Widget _buildAnswerInput(BuildContext context) {
    final theme = Theme.of(context);

    if (_isCorrect != null) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _submitting || _isFinishing ? null : _nextProblem,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(
            _currentIndex + 1 >= widget.problems.length ? '查看成绩' : '下一题',
          ),
        ),
      ).animate().fadeIn(duration: 250.ms).slideY(
            begin: 0.2,
            end: 0,
            duration: 250.ms,
            curve: Curves.easeOutCubic,
          );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 答案输入框（只读 + 右侧单位标注）
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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    _answerController.text.isEmpty
                        ? '输入答案'
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
                  if (_current.unit.isNotEmpty) ...[
                    const SizedBox(width: SpacingTokens.xs),
                    Text(
                      _current.unit,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: SpacingTokens.md),
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
        ),
      ],
    );
  }
}
