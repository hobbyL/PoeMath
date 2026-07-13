// lib/features/poem/poem_quiz_page.dart
//
// 诗词测试页：填空测试 + 选择题，逐题作答，即时反馈，完成后显示结果。

import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/confetti_overlay.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
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
  late final ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(milliseconds: 500),
    );
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

    if (widget.quizType == QuizType.fillBlank) {
      questions = QuizEngine.generateFillBlank(poem, random: random);
    } else {
      // 收集干扰行
      final allPoems = ref.read(filteredPoemsProvider);
      final extraLines = QuizEngine.collectExtraLines(
        allPoems,
        excludeId: widget.poemId,
        random: random,
      );
      questions = QuizEngine.generateMultipleChoice(
        poem,
        extraLines: extraLines,
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
    final session = _session!;

    // 记录学习
    final progressRepo = ref.read(poemProgressRepoProvider);
    final progress = await progressRepo.recordStudy(widget.poemId);

    // 更新全局统计
    final statsRepo = ref.read(userStatsRepoProvider);
    final learnedCount = progressRepo.learnedCount;
    await statsRepo.updatePoemStats(learned: learnedCount);
    ref.invalidate(learnedCountProvider);
    ref.invalidate(userStatsProvider);

    // 通过时更新掌握等级和复习计划
    if (session.isPassed) {
      if (progress.masteryLevel < 5) {
        progress.masteryLevel = 5; // 测试通过 = 等级 5
        await progressRepo.save(progress);
      }

      // 首次通过 → 创建艾宾浩斯复习计划
      final reviewRepo = ref.read(reviewRepoProvider);
      final existing = reviewRepo.get(widget.poemId);
      if (existing == null) {
        await reviewRepo.createSchedule(widget.poemId);
      }
    }

    if (mounted) setState(() {});
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

    return Scaffold(
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
                      ),
                    ),
                    const SizedBox(height: SpacingTokens.md),

                    // 题干
                    Text(
                      q.type == QuizType.fillBlank
                          ? q.promptLine
                          : '下一句是？',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.8,
                      ),
                    ),
                    const SizedBox(height: SpacingTokens.lg),

                    // 作答区域
                    if (q.type == QuizType.fillBlank)
                      _buildFillBlankInput(context, q, theme)
                    else
                      _buildChoiceOptions(context, q, theme),

                    // 反馈区域
                    if (_answered) ...[
                      const SizedBox(height: SpacingTokens.md),
                      _buildFeedback(context, session, q, theme),
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
                onPressed: session.currentIndex < session.questions.length - 1
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
      children: q.options!.map((option) {
        Color? bgColor;
        Color? borderColor;
        Color? textColor;

        if (_answered) {
          if (option == q.correctAnswer) {
            bgColor = ColorTokens.success.withValues(alpha: 0.12);
            borderColor = ColorTokens.success;
            textColor = ColorTokens.success;
          } else if (option == _session!.userAnswers[_session!.currentIndex]) {
            bgColor = theme.colorScheme.error.withValues(alpha: 0.12);
            borderColor = theme.colorScheme.error;
            textColor = theme.colorScheme.error;
          }
        }

        return Padding(
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SpacingTokens.md),
      decoration: BoxDecoration(
        color: isCorrect
            ? ColorTokens.success.withValues(alpha: 0.1)
            : theme.colorScheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
      ),
      child: Row(
        children: [
          Icon(
            isCorrect ? Icons.check_circle : Icons.cancel,
            color: isCorrect ? ColorTokens.success : theme.colorScheme.error,
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
                        ? ColorTokens.success
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
      ratingText = '满分！完美！🎉';
      ratingIcon = Icons.emoji_events;
      ratingColor = ColorTokens.poemGold;
    } else if (session.isPassed) {
      ratingText = '表现不错，继续加油！👍';
      ratingIcon = Icons.thumb_up;
      ratingColor = ColorTokens.success;
    } else {
      ratingText = '还需努力，多多复习哦 📖';
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
          Icon(ratingIcon, size: 80, color: ratingColor),
          const SizedBox(height: SpacingTokens.md),

          // 评语
          Text(
            ratingText,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: SpacingTokens.xl),

          // 统计卡片
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
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check),
                  label: const Text('完成'),
                ),
              ),
            ],
          ),
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
