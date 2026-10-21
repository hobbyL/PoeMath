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
import 'package:poemath/features/math/practice_clock.dart';
import 'package:poemath/features/math/practice_resume_prompt.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/features/math/widgets/number_keypad.dart';
import 'package:poemath/features/math/widgets/session_result_dialog.dart';
import 'package:poemath/features/math/word_problem/word_problem_providers.dart';

class WordProblemPracticePage extends ConsumerStatefulWidget {
  const WordProblemPracticePage({
    super.key,
    required this.problems,
    this.resume = false,
  });

  final List<LlmProblem> problems;
  final bool resume;

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
  final _drafts = PracticeDraftRepository();
  late final PracticeClock _clock;
  late List<LlmProblem> _problems;
  bool _ready = false;
  bool _draftDisabled = false;
  String? _resumeError;
  Timer? _draftTimer;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _sessionId = DateTime.now().microsecondsSinceEpoch.toString();
    _confettiController = CelebrationController();
    _problems = widget.problems;
    _clock = PracticeClock()..onPause = _saveOnPause;
    _answerController.addListener(_queueDraftSave);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initialize());
    });
  }

  Future<void> _initialize() async {
    try {
      final draft = _drafts.get('word');
      if (draft != null) {
        final resume =
            widget.resume ? true : await choosePracticeResume(context, '应用题');
        if (!mounted) return;
        if (resume == null) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(AppRoutes.home);
          }
          return;
        }
        if (resume) {
          _problems = (draft['problems'] as List<dynamic>)
              .map(
                (p) => LlmProblem.fromSnapshot(p as Map<String, dynamic>),
              )
              .toList();
          _problemRecords.addAll(
            (draft['records'] as List<dynamic>).map(
              (r) => ProblemRecord.fromJson(r as Map<String, dynamic>),
            ),
          );
          _currentIndex = draft['index'] as int;
          if (_problems.isEmpty ||
              _currentIndex < 0 ||
              _currentIndex >= _problems.length ||
              _problemRecords.length < _currentIndex ||
              _problemRecords.length > _currentIndex + 1) {
            throw const FormatException('草稿答题位置无效');
          }
          _sessionId = draft['sessionId'] as String;
          _startTime = DateTime.parse(draft['startedAt'] as String);
          _completedAt =
              DateTime.tryParse(draft['completedAt'] as String? ?? '');
          _correctCount = _problemRecords.where((r) => r.isCorrect).length;
          _isCorrect = _problemRecords.length > _currentIndex
              ? _problemRecords[_currentIndex].isCorrect
              : null;
          _answerController.text = draft['input'] as String? ?? '';
          _clock.start(
            elapsedMilliseconds: draft['elapsedMilliseconds'] as int,
          );
          if (_completedAt != null) _clock.finish();
          _submitting = true;
          setState(() => _ready = true);
          try {
            if (_problemRecords.isNotEmpty) await _persistProgress();
            if (_completedAt != null && mounted) await _finishSession();
          } finally {
            _submitting = false;
            if (mounted) setState(() {});
          }
          return;
        }
        await _drafts.remove('word');
      }
      if (!mounted) return;
      if (_problems.isEmpty) throw const FormatException('没有可恢复的应用题');
      _clock.start();
      setState(() => _ready = true);
      await _saveDraft();
    } catch (error, stack) {
      AppLogger.e(
        '应用题续练失败',
        tag: 'WordProblemPractice',
        error: error,
        stackTrace: stack,
      );
      if (!mounted) return;
      if (_ready) {
        // 快照解析完成后的落盘失败可在当前题重试，不能挡住结算按钮。
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('练习已恢复，进度或结算暂未保存，请重试')),
        );
      } else {
        setState(() => _resumeError = '上次应用题暂时无法恢复，请返回首页放弃草稿后重试');
      }
    }
  }

  Future<void> _saveDraft() async {
    if (!_ready || _draftDisabled || _problems.isEmpty) return;
    await _drafts.save('word', {
      'sessionId': _sessionId,
      'startedAt': _startTime.toIso8601String(),
      'completedAt': _completedAt?.toIso8601String(),
      'elapsedMilliseconds': _clock.elapsedMilliseconds,
      'index': _currentIndex,
      'input': _answerController.text,
      'problems': _problems.map((p) => p.toSnapshot()).toList(),
      'records': _problemRecords.map((r) => r.toJson()).toList(),
    });
  }

  void _queueDraftSave() {
    if (_draftDisabled) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 200), () {
      unawaited(
        _saveDraft().catchError((Object error, StackTrace stack) {
          AppLogger.e(
            '应用题草稿保存失败',
            tag: 'WordProblemPractice',
            error: error,
            stackTrace: stack,
          );
        }),
      );
    });
  }

  void _saveOnPause() {
    _draftTimer?.cancel();
    unawaited(
      _saveDraft().catchError((Object error, StackTrace stack) {
        AppLogger.e(
          '暂停时保存应用题草稿失败',
          tag: 'WordProblemPractice',
          error: error,
          stackTrace: stack,
        );
      }),
    );
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _clock.dispose();
    unawaited(
      _saveDraft().catchError((Object error, StackTrace stack) {
        AppLogger.e(
          '退出时保存草稿失败',
          tag: 'WordProblemPractice',
          error: error,
          stackTrace: stack,
        );
      }),
    );
    _answerController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  LlmProblem get _current => _problems[_currentIndex];

  /// 判分：输入解析为 num 后与答案精确相等（"16" / "16.0" 均通过）。
  bool _judge(String userAnswer) {
    final parsed = num.tryParse(userAnswer.trim());
    return parsed != null && parsed == _current.answer;
  }

  /// 按固定题组和题序写入检查点，恢复后允许幂等重放。
  Future<void> _persistProgress() async {
    final answered = _problemRecords.length;
    final duration = _clock.elapsedSeconds;
    final first = _problems.first;
    final sessions = ref.read(mathSessionRepositoryProvider);
    final stats = ref.read(userStatsRepositoryProvider);
    final problems = ref.read(llmProblemRepositoryProvider);
    final mistakes = ref.read(mathMistakeRepoProvider);

    final session = MathSession(
      id: _sessionId,
      profileId: ProfileScope.currentId,
      grade: first.grade,
      problemType: 'llm_word_problem',
      totalProblems: answered,
      correctCount: _correctCount,
      durationSeconds: duration,
      starsEarned: 0,
      startedAt: _startTime,
      finishedAt: DateTime.now(),
      isComplete: false,
      semester: first.semester,
      difficulty: _difficultyLabel(first.difficulty),
      problemsJson: jsonEncode(
        _problemRecords.map((r) => r.toJson()).toList(),
      ),
    );
    if (_completedAt == null) await _drafts.guard(() => sessions.save(session));

    // 增量更新用户统计（每题 +1），与口算练习页共用同一仓储写入路径。
    for (var i = 0; i < _problemRecords.length; i++) {
      await _drafts.guard(
        () => stats.recordMathAttempt(
          isCorrect: _problemRecords[i].isCorrect,
          bestStreak: 0,
          activityId: 'word_attempt:$_sessionId:$i',
        ),
      );
      await _drafts.guard(
        () => problems.recordAttempt(
          _problems[i].id,
          correct: _problemRecords[i].isCorrect,
          activityId: 'word_library_attempt:$_sessionId:$i',
        ),
      );
      final record = _problemRecords[i];
      if (!record.isCorrect) {
        final problem = _problems[i];
        await _drafts.guard(
          () => mistakes.recordWrong(
            problemText: problem.questionText,
            correctAnswer: problem.answer.toString(),
            userAnswer: record.userAnswer,
            problemType: 'llm_word_problem',
            grade: problem.grade,
            semester: problem.semester,
            solutionStepsJson:
                problem.explanation.isEmpty ? null : problem.explanation,
            activityId: 'word_mistake_attempt:$_sessionId:$i',
          ),
        );
      }
    }

    if (mounted) {
      ref.invalidate(userStatsProvider);
      ref.invalidate(todayMathCountProvider);
      ref.invalidate(mathMistakeRepoProvider);
    }
  }

  static String _difficultyLabel(int difficulty) {
    if (difficulty <= 2) return 'easy';
    if (difficulty == 3) return 'medium';
    return 'hard';
  }

  Future<void> _submitAnswer() async {
    if (_isCorrect != null || _submitting) return;
    final userAnswer = _answerController.text.trim();
    if (userAnswer.isEmpty) return;
    final problem = _current;
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
    try {
      await _saveDraft();
      await _persistProgress();
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('本题进度暂未保存，下一步会重试，请勿强制关闭应用')),
        );
      }
    } finally {
      _submitting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _nextProblem() async {
    if (_submitting || _isCorrect == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      await _saveDraft();
      await _persistProgress();
      if (!mounted) return;
      if (_currentIndex + 1 >= _problems.length) {
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
      await _saveDraft();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('答题进度或结算保存失败，请重试')),
        );
      }
    } finally {
      _submitting = false;
      if (mounted) setState(() {});
    }
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
    final problems = _problems;
    final correctCount = _correctCount;
    final completedAt = _completedAt ??= DateTime.now();
    _clock.finish();
    final duration = _clock.elapsedSeconds;
    final draftWrite = _saveDraft();
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
      startedAt: _startTime,
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
    await draftWrite;
    await _drafts.guard(() => repo.save(session));
    final activityId = 'llm_word_practice:${session.id}';
    await _drafts.guard(
      () => activityRepo.record(
        id: activityId,
        activityType: LearningActivityType.wordProblem,
        totalItems: problems.length,
        successfulItems: correctCount,
        starsEarned: stars,
        durationSeconds: duration,
        completedAt: completedAt,
      ),
    );

    // 做题数已在 _persistProgress() 中逐题更新，只需添加星星。
    final levelBeforeReward = statsRepo.get().level;
    if (stars > 0) {
      await _drafts
          .guard(() => statsRepo.addStars(stars, activityId: activityId));
    }
    await _drafts.guard(
      () => checkInRepo.updateForDate(
        completedAt,
        activityId: activityId,
        addMathTotal: problems.length,
        addMathCorrect: correctCount,
        addStars: stars,
        addDuration: duration,
      ),
    );
    _draftDisabled = true;
    try {
      await _drafts.remove('word', sessionId: _sessionId);
    } catch (_) {
      _draftDisabled = false;
      rethrow;
    }

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
      await _retrySession();
    } else {
      _returnToLibrary();
    }
  }

  void _returnToLibrary() {
    // 栈内没有上一页时（深链直达 / 进程恢复）直接去题库。
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.wordProblemLibrary);
    }
  }

  /// 从当前档案题库换一组：保持练习背景，优先未做题，排除刚完成的题。
  Future<void> _retrySession() async {
    final contexts =
        _problems.map((p) => (p.grade, p.semester, p.topic)).toSet();
    final completedIds = _problems.map((p) => p.id).toSet();
    final completedTexts = _problems.map((p) => p.questionText.trim()).toSet();
    final candidates = ref
        .read(llmProblemRepositoryProvider)
        .getAll()
        .where(
          (p) =>
              contexts.contains((p.grade, p.semester, p.topic)) &&
              !completedIds.contains(p.id) &&
              !completedTexts.contains(p.questionText.trim()),
        )
        .toList();
    final nextProblems = [
      ...candidates.where((p) => !p.done),
      ...candidates.where((p) => p.done),
    ].take(_problems.length).toList();
    if (nextProblems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('同类题目已练完，可以在题库选择其他题目或生成新题')),
      );
      _returnToLibrary();
      return;
    }

    _draftTimer?.cancel();
    _answerController.clear();
    _problemRecords.clear();
    _startTime = DateTime.now();
    _sessionId = DateTime.now().microsecondsSinceEpoch.toString();
    _completedAt = null;
    _clock.start();
    setState(() {
      _problems = nextProblems;
      _currentIndex = 0;
      _correctCount = 0;
      _isCorrect = null;
      _showExplanation = false;
    });
    _draftDisabled = false;
    await _saveDraft();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _resumeError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('应用题练习')),
        body: Center(
          child: _resumeError == null
              ? const CircularProgressIndicator()
              : Text(_resumeError!),
        ),
      );
    }
    final theme = Theme.of(context);
    final problem = _current;
    final total = _problems.length;

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
            _currentIndex + 1 >= _problems.length ? '查看成绩' : '下一题',
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
          submitEnabled: _answerController.text.isNotEmpty &&
              !_submitting &&
              !_isFinishing,
        ),
      ],
    );
  }
}
