// lib/features/poem/poem_quiz_page.dart
//
// 诗词测试页：填空测试 + 选择题，逐题作答，即时反馈，完成后显示结果。

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/celebration_dialog.dart';
import 'package:poemath/core/widgets/confetti_overlay.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/achievement_check_helper.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/poem/poem_practice_result.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';
import 'package:poemath/features/poem/quiz/quiz_engine.dart';
import 'package:poemath/features/poem/quiz/quiz_models.dart';

class PoemQuizPage extends ConsumerStatefulWidget {
  const PoemQuizPage({
    super.key,
    required this.poemId,
    required this.quizType,
  });

  final String poemId;
  final QuizType quizType;

  @override
  ConsumerState<PoemQuizPage> createState() => _PoemQuizPageState();
}

class _PoemQuizPageState extends ConsumerState<PoemQuizPage> {
  QuizSession? _session;
  bool _answered = false;
  final _fillController = TextEditingController();
  final _fillFocusNode = FocusNode();
  late final CelebrationController _confettiController;
  bool _allowResultPop = false;
  bool _isFinishing = false;
  int _starsEarned = 0;
  String? _activityId;

  @override
  void initState() {
    super.initState();
    _confettiController = CelebrationController();
    // 延迟初始化，等 ref 可用
    WidgetsBinding.instance.addPostFrameCallback((_) => _initQuiz());
  }

  @override
  void dispose() {
    _fillController.dispose();
    _fillFocusNode.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  void _initQuiz() {
    final poem = ref.read(poemByIdProvider(widget.poemId));
    if (poem == null) return;

    final random = Random();
    List<QuizQuestion> questions;

    switch (widget.quizType) {
      case QuizType.fillBlank:
        questions = QuizEngine.generateFillBlank(poem, random: random);
      case QuizType.multipleChoice:
        // 收集干扰行
        final allPoems = ref.read(filteredPoemsProvider);
        final extraLines = QuizEngine.collectExtraLines(
          allPoems,
          excludeId: widget.poemId,
          random: random,
        );
        // 生成混合选择题：上下句 + 选作者 + 选朝代
        final choiceQuestions = QuizEngine.generateMultipleChoice(
          poem,
          extraLines: extraLines,
          random: random,
          maxQuestions: 3,
        );
        final authorQuestions = QuizEngine.generateChooseAuthor(
          poem,
          allPoems: allPoems,
          maxQuestions: 2,
          random: random,
        );
        final dynastyQuestions = QuizEngine.generateChooseDynasty(
          poem,
          allPoems: allPoems,
          maxQuestions: 1,
          random: random,
        );
        questions = [
          ...choiceQuestions,
          ...authorQuestions,
          ...dynastyQuestions,
        ]..shuffle(random);
        // 限制总题数
        if (questions.length > 8) {
          questions = questions.sublist(0, 8);
        }
      case QuizType.chooseAuthor:
        final allPoems = ref.read(filteredPoemsProvider);
        questions = QuizEngine.generateChooseAuthor(
          poem,
          allPoems: allPoems,
          random: random,
        );
      case QuizType.chooseDynasty:
        final allPoems = ref.read(filteredPoemsProvider);
        questions = QuizEngine.generateChooseDynasty(
          poem,
          allPoems: allPoems,
          random: random,
        );
    }

    if (questions.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该诗词无法生成测试题目')),
        );
        Navigator.pop(context);
      }
      return;
    }

    setState(() {
      _activityId =
          'poem_quiz:${widget.poemId}:${DateTime.now().microsecondsSinceEpoch}';
      _session = QuizSession(
        poemId: widget.poemId,
        type: widget.quizType,
        questions: questions,
      );
    });
  }

  void _submitFillAnswer() {
    final text = _fillController.text.trim();
    if (text.isEmpty || _answered) return;
    _session!.submitAnswer(text);
    setState(() => _answered = true);
    _playAnswerFeedback();
  }

  void _submitChoiceAnswer(String choice) {
    if (_answered) return;
    _session!.submitAnswer(choice);
    setState(() => _answered = true);
    _playAnswerFeedback();
  }

  /// 答题后播放音效和触觉反馈。
  void _playAnswerFeedback() {
    final isCorrect = _session!.isCurrentCorrect();
    final sound = ref.read(soundServiceProvider);
    final haptic = ref.read(hapticServiceProvider);
    if (isCorrect) {
      sound.play(SoundEffect.correct);
      haptic.medium();
      _confettiController.play();
    } else {
      sound.play(SoundEffect.wrong);
      haptic.heavy();
    }
  }

  void _nextQuestion() {
    _session!.advance();
    _fillController.clear();
    setState(() => _answered = false);
    if (!_session!.isFinished) {
      _fillFocusNode.requestFocus();
    }
  }

  Future<void> _finishQuiz() async {
    if (_isFinishing) return;
    _isFinishing = true;
    if (mounted) setState(() {});

    final session = _session!;
    final activityId = _activityId!;
    final stars = LearningRewardCalculator.calculateStars(
      activityType: LearningActivityType.poemQuiz,
      totalItems: session.questions.length,
      successfulItems: session.correctCount,
    );
    _starsEarned = stars;
    try {
      // 记录学习
      final progressRepo = ref.read(poemProgressRepoProvider);
      final progress = await progressRepo.recordStudy(widget.poemId);
      ref.invalidate(poemProgressProvider(widget.poemId));

      // 更新全局统计
      final statsRepo = ref.read(userStatsRepoProvider);
      final learnedCount = progressRepo.learnedCount;
      await statsRepo.updatePoemStats(learned: learnedCount);
      if (stars > 0) {
        await statsRepo.addStars(stars, activityId: activityId);
      }
      await ref.read(checkInRepoProvider).updateToday(
            activityId: activityId,
            addPoems: 1,
            addStars: stars,
            addDuration: session.elapsedSeconds,
          );
      ref.invalidate(learnedCountProvider);
      ref.invalidate(userStatsProvider);
      ref.invalidate(todayPoemCountProvider);
      ref.invalidate(todayCheckInProvider);

      // 通过时更新掌握等级、状态和复习计划
      if (session.isPassed) {
        var needSave = false;

        if (progress.masteryLevel < 5) {
          progress.masteryLevel = 5; // 测试通过 = 等级 5
          needSave = true;
        }

        // 测试通过 → 进入复习阶段
        if (progress.status == LearningStatus.learning) {
          progress.status = LearningStatus.reviewing;
          needSave = true;
        }

        if (needSave) {
          await progressRepo.save(progress);
          ref.invalidate(poemProgressProvider(widget.poemId));
        }

        // 首次通过 → 创建艾宾浩斯复习计划
        final reviewRepo = ref.read(reviewRepoProvider);
        final existing = reviewRepo.get(widget.poemId);
        if (existing == null) {
          await reviewRepo.createSchedule(widget.poemId);
        }
      }

      // 成就自动检查
      final newlyUnlocked = await checkAchievements(ref);
      ref.invalidate(unlockedAchievementsCountProvider);

      if (mounted && newlyUnlocked.isNotEmpty) {
        _confettiController.play();
        final names = newlyUnlocked.map((a) => a.title).join('、');
        showCelebration(
          context,
          type: CelebrationType.achievement,
          subtitle: names,
        );
      }
    } finally {
      _isFinishing = false;
      if (mounted) setState(() {});
    }
  }

  void _exitWithResult() {
    if (_allowResultPop) return;
    final session = _session;
    if (session == null || !session.isFinished) return;

    setState(() => _allowResultPop = true);
    final result = session.isPassed
        ? PoemPracticeResult.quizPassed
        : PoemPracticeResult.quizFailed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    final poem = ref.watch(poemByIdProvider(widget.poemId));
    final theme = Theme.of(context);

    if (poem == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('诗词测试')),
        body: const Center(child: Text('诗词未找到')),
      );
    }

    if (_session == null) {
      return Scaffold(
        appBar: AppBar(title: Text('${widget.quizType.label} · ${poem.title}')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final session = _session!;

    return PopScope<PoemPracticeResult>(
      canPop: !session.isFinished || _allowResultPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && session.isFinished) _exitWithResult();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.quizType.label} · ${poem.title}'),
        ),
        body: Stack(
          children: [
            session.isFinished
                ? _buildResult(context, session)
                : _buildQuestion(context, session, theme),
            ConfettiOverlay(controller: _confettiController),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion(
    BuildContext context,
    QuizSession session,
    ThemeData theme,
  ) {
    final q = session.currentQuestion;
    final progress = (session.currentIndex + 1) / session.questions.length;

    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 进度条
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: progress,
                  borderRadius: BorderRadius.circular(
                    SpacingTokens.radiusSmall,
                  ),
                ),
              ),
              const SizedBox(width: SpacingTokens.sm),
              Text(
                '${session.currentIndex + 1}/${session.questions.length}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.lg),

          // 题目卡片
          Expanded(
            child: SingleChildScrollView(
              child: ColoredCard(
                color: theme.colorScheme.primary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 上下文提示
                    Text(
                      q.contextLine,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.8,
                        fontFamilyFallback: TypographyTokens.serifFallback,
                      ),
                    ),
                    const SizedBox(height: SpacingTokens.md),

                    // 题干
                    Text(
                      q.type == QuizType.fillBlank
                          ? q.promptLine
                          : q.promptLine,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.8,
                        fontFamilyFallback: TypographyTokens.serifFallback,
                      ),
                    ),
                    const SizedBox(height: SpacingTokens.lg),

                    // 作答区域
                    if (q.type == QuizType.fillBlank)
                      _buildFillBlankInput(context, q, theme)
                    else if (q.type.isChoice)
                      _buildChoiceOptions(context, q, theme),

                    // 反馈区域
                    if (_answered) ...[
                      const SizedBox(height: SpacingTokens.md),
                      _buildFeedback(context, session, q, theme)
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
                            color: session.isCurrentCorrect()
                                ? theme.semantic.success.withValues(alpha: 0.3)
                                : Colors.transparent,
                          ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // 底部按钮
          if (_answered) ...[
            const SizedBox(height: SpacingTokens.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isFinishing
                    ? null
                    : session.currentIndex < session.questions.length - 1
                        ? _nextQuestion
                        : () async {
                            session.advance();
                            await _finishQuiz();
                          },
                icon: Icon(
                  session.currentIndex < session.questions.length - 1
                      ? Icons.arrow_forward
                      : Icons.check_circle_outline,
                ),
                label: Text(
                  session.currentIndex < session.questions.length - 1
                      ? '下一题'
                      : '查看结果',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFillBlankInput(
    BuildContext context,
    QuizQuestion q,
    ThemeData theme,
  ) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _fillController,
            focusNode: _fillFocusNode,
            enabled: !_answered,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '请输入答案…',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  SpacingTokens.radiusMedium,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.md,
                vertical: SpacingTokens.sm,
              ),
            ),
            onSubmitted: (_) => _submitFillAnswer(),
          ),
        ),
        if (!_answered) ...[
          const SizedBox(width: SpacingTokens.sm),
          FilledButton(
            onPressed: _submitFillAnswer,
            child: const Text('提交'),
          ),
        ],
      ],
    );
  }

  Widget _buildChoiceOptions(
    BuildContext context,
    QuizQuestion q,
    ThemeData theme,
  ) {
    return Column(
      children: q.options!.asMap().entries.map((entry) {
        final i = entry.key;
        final option = entry.value;
        Color? bgColor;
        Color? borderColor;
        Color? textColor;
        final isCorrectOption = option == q.correctAnswer;
        final isUserWrong = _answered &&
            !isCorrectOption &&
            option == _session!.userAnswers[_session!.currentIndex];

        if (_answered) {
          if (isCorrectOption) {
            bgColor = theme.semantic.success.withValues(alpha: 0.12);
            borderColor = theme.semantic.success;
            textColor = theme.semantic.success;
          } else if (isUserWrong) {
            bgColor = theme.colorScheme.error.withValues(alpha: 0.12);
            borderColor = theme.colorScheme.error;
            textColor = theme.colorScheme.error;
          }
        }

        Widget optionWidget = Padding(
          padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _answered ? null : () => _submitChoiceAnswer(option),
              style: OutlinedButton.styleFrom(
                backgroundColor: bgColor,
                side: borderColor != null
                    ? BorderSide(color: borderColor, width: 2)
                    : null,
                foregroundColor: textColor,
                padding: const EdgeInsets.all(SpacingTokens.md),
                alignment: Alignment.centerLeft,
              ),
              child: Text(
                option,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: textColor,
                  height: 1.6,
                ),
              ),
            ),
          ),
        );

        // 交错入场
        optionWidget = optionWidget
            .animate()
            .fadeIn(delay: (100 * i).ms, duration: 300.ms)
            .slideX(
              begin: 0.15,
              end: 0,
              delay: (100 * i).ms,
              duration: 300.ms,
              curve: Curves.easeOutCubic,
            );

        // 答对选项：额外弹跳 + 光泽
        if (_answered && isCorrectOption) {
          optionWidget = optionWidget
              .animate(delay: 100.ms)
              .scale(
                begin: const Offset(1, 1),
                end: const Offset(1.03, 1.03),
                duration: 200.ms,
                curve: Curves.easeOut,
              )
              .then()
              .scale(
                begin: const Offset(1.03, 1.03),
                end: const Offset(1, 1),
                duration: 200.ms,
              )
              .shimmer(
                delay: 100.ms,
                duration: 600.ms,
                color: theme.semantic.success.withValues(alpha: 0.4),
              );
        }

        // 答错选项：抖动
        if (isUserWrong) {
          optionWidget = optionWidget
              .animate(delay: 100.ms)
              .shakeX(duration: 400.ms, hz: 4, amount: 4);
        }

        return optionWidget;
      }).toList(),
    );
  }

  Widget _buildFeedback(
    BuildContext context,
    QuizSession session,
    QuizQuestion q,
    ThemeData theme,
  ) {
    final isCorrect = session.isCurrentCorrect();
    return ColoredCard(
      color: isCorrect ? theme.semantic.success : theme.colorScheme.error,
      backgroundOpacity: 0.1,
      width: double.infinity,
      child: Row(
        children: [
          Icon(
            isCorrect ? Icons.check_circle : Icons.cancel,
            color: isCorrect ? theme.semantic.success : theme.colorScheme.error,
          ),
          const SizedBox(width: SpacingTokens.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCorrect ? '回答正确！' : '回答错误',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: isCorrect
                        ? theme.semantic.success
                        : theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!isCorrect) ...[
                  const SizedBox(height: SpacingTokens.xs),
                  Text(
                    '正确答案：${q.correctAnswer}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context, QuizSession session) {
    final theme = Theme.of(context);
    final poem = ref.watch(poemByIdProvider(widget.poemId));

    String ratingText;
    IconData ratingIcon;
    Color ratingColor;

    if (session.accuracy >= 1.0) {
      ratingText = '满分！完美！';
      ratingIcon = Icons.emoji_events;
      ratingColor = theme.semantic.caution;
    } else if (session.isPassed) {
      ratingText = '表现不错，继续加油！';
      ratingIcon = Icons.thumb_up;
      ratingColor = theme.semantic.success;
    } else {
      ratingText = '还需努力，多多复习哦';
      ratingIcon = Icons.auto_stories;
      ratingColor = theme.colorScheme.secondary;
    }

    final minutes = session.elapsedSeconds ~/ 60;
    final seconds = session.elapsedSeconds % 60;
    final timeText = minutes > 0 ? '$minutes 分 $seconds 秒' : '$seconds 秒';

    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: Column(
        children: [
          const Spacer(),

          // 评级图标
          Icon(ratingIcon, size: 80, color: ratingColor)
              .animate()
              .scale(
                begin: const Offset(0, 0),
                end: const Offset(1, 1),
                duration: 500.ms,
                curve: Curves.elasticOut,
              )
              .shimmer(
                delay: 400.ms,
                duration: 800.ms,
                color: ratingColor.withValues(alpha: 0.3),
              ),
          const SizedBox(height: SpacingTokens.md),

          // 评语
          Text(
            ratingText,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
          const SizedBox(height: SpacingTokens.xl),

          // 统计卡片（滑入）
          ColoredCard(
            color: theme.colorScheme.primary,
            child: Column(
              children: [
                Text(
                  poem?.title ?? '',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatItem(
                      context,
                      '${session.correctCount}/${session.questions.length}',
                      '正确',
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.2),
                    ),
                    _buildStatItem(
                      context,
                      '${(session.accuracy * 100).toStringAsFixed(0)}%',
                      '正确率',
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.2),
                    ),
                    _buildStatItem(context, timeText, '用时'),
                  ],
                ),
                const SizedBox(height: SpacingTokens.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.star_rounded,
                      size: 18,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: SpacingTokens.xs),
                    Text(
                      _starsEarned > 0 ? '获得 $_starsEarned 颗星星' : '本次未获得星星',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (session.isPassed) ...[
                  const SizedBox(height: SpacingTokens.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: SpacingTokens.xs),
                      Text(
                        '已加入艾宾浩斯复习计划',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ).animate().fadeIn(delay: 600.ms, duration: 400.ms).slideY(
                begin: 0.15,
                end: 0,
                delay: 600.ms,
                duration: 400.ms,
                curve: Curves.easeOutCubic,
              ),

          const Spacer(),

          // 操作按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    // 重新测试
                    setState(() {
                      _session = null;
                      _answered = false;
                      _allowResultPop = false;
                      _fillController.clear();
                    });
                    _initQuiz();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('再测一次'),
                ),
              ),
              const SizedBox(width: SpacingTokens.md),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _exitWithResult,
                  icon: const Icon(Icons.check),
                  label: const Text('完成'),
                ),
              ),
            ],
          ).animate().fadeIn(delay: 800.ms, duration: 400.ms),
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String value, String label) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: SpacingTokens.xs),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
