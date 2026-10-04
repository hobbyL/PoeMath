// lib/features/math/word_problem/word_problem_practice_page.dart
//
// 层级：features/math/word_problem
// 职责：应用题练习页 —— 题库离线消费。判分/讲解本地完成；
//       结算链复用口算（MathSession problemType 'llm_word_problem'
//       计入每日目标；星星/打卡/学习活动/成就同步）。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/celebration_dialog.dart';
import 'package:poemath/core/widgets/confetti_overlay.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/data/models/math_mistake.dart';
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
  bool _isFinishing = false;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
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
    HiveBoxes.mathSessions.put(ProfileScope.key(_sessionId), session);

    final statsKey = ProfileScope.key('stats');
    var stats = HiveBoxes.userStats.get(statsKey);
    stats ??= UserStats(profileId: ProfileScope.currentId);
    stats.mathTotalProblems += 1;
    if (isCorrect) stats.mathTotalCorrect += 1;
    HiveBoxes.userStats.put(statsKey, stats);

    ref.invalidate(userStatsProvider);
    ref.invalidate(todayMathCountProvider);
  }

  static String _difficultyLabel(int difficulty) {
    if (difficulty <= 2) return 'easy';
    if (difficulty == 3) return 'medium';
    return 'hard';
  }

  void _recordMistake(String userAnswer) {
    final problem = _current;
    final repo = ref.read(mathMistakeRepoProvider);

    repo.add(
      MathMistake(
        id: '${_sessionId}_$_currentIndex',
        profileId: ProfileScope.currentId,
        problemText: problem.questionText,
        correctAnswer: problem.answer.toString(),
        userAnswer: userAnswer,
        problemType: 'llm_word_problem',
        grade: problem.grade,
        errorType: null,
        // 应用题讲解是自然语言文本，直接存储。
        solutionStepsJson: problem.explanation.isEmpty ? null : problem.explanation,
      ),
    );
    ref.invalidate(mathMistakeRepoProvider);
  }

  Future<void> _submitAnswer() async {
    if (_isCorrect != null) return;
    final userAnswer = _answerController.text.trim();
    if (userAnswer.isEmpty) return;

    final isCorrect = _judge(userAnswer);
    setState(() {
      _isCorrect = isCorrect;
      _showExplanation = false;
    });

    final sound = ref.read(soundServiceProvider);
    final haptic = ref.read(hapticServiceProvider);
    if (isCorrect) {
      sound.play(SoundEffect.correct);
      await haptic.medium();
      _confettiController.play();
      _correctCount++;
    } else {
      sound.play(SoundEffect.wrong);
      await haptic.heavy();
      _recordMistake(userAnswer);
    }

    _problemRecords.add(
      ProblemRecord(
        problemText: _current.questionText,
        answerText: '${_current.answer}${_current.unit}',
        userAnswer: userAnswer,
        isCorrect: isCorrect,
      ),
    );

    // 记录做题状态（done/attempts/correctCount/lastDoneAt）。
    await ref
        .read(llmProblemRepositoryProvider)
        .recordAttempt(_current.id, correct: isCorrect);

    _persistProgress(isCorrect: isCorrect);
  }

  Future<void> _nextProblem() async {
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
    final problems = widget.problems;
    final correctCount = _correctCount;
    final completedAt = DateTime.now();
    final duration = completedAt.difference(_startTime).inSeconds;
    final first = problems.first;

    final stars = LearningRewardCalculator.calculateStars(
      activityType: LearningActivityType.mathPractice,
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
    await repo.save(session);
    final activityId = 'llm_word_practice:${session.id}';
    await ref.read(learningActivityRepositoryProvider).record(
          id: activityId,
          activityType: LearningActivityType.mathPractice,
          totalItems: problems.length,
          successfulItems: correctCount,
          starsEarned: stars,
          durationSeconds: duration,
          completedAt: completedAt,
        );

    // 做题数已在 _persistProgress() 中逐题更新，只需添加星星。
    final statsRepo = ref.read(userStatsRepoProvider);
    final levelBeforeReward = statsRepo.get().level;
    if (stars > 0) {
      await statsRepo.addStars(stars, activityId: activityId);
    }
    await ref.read(checkInRepoProvider).updateToday(
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

    final newlyUnlocked = await checkAchievements(ref, latestSession: session);

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
      showCelebration(
        context,
        type: CelebrationType.achievement,
        subtitle: names,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      if (!mounted) return;
    }

    await showDialog<String>(
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
    // 应用题练习结束返回题库。
    context.pop();
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
                                )
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
                  _showExplanation
                      ? Icons.expand_less
                      : Icons.expand_more,
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
          onPressed: _nextProblem,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(
            _currentIndex + 1 >= widget.problems.length
                ? '查看成绩'
                : '下一题',
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
