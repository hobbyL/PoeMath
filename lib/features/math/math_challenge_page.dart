// lib/features/math/math_challenge_page.dart
//
// 层级：features/math
// 职责：口算限时挑战 — 支持两种模式：
//       固定时间（60 秒纯倒计时）和续命模式（答对加时）。
//       挑战结束后自动保存记录。

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/celebration_dialog.dart';
import 'package:poemath/data/models/challenge_record.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/achievement_check_helper.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/math_practice_request.dart';
import 'package:poemath/features/math/widgets/math_text.dart';
import 'package:poemath/features/math/widgets/number_keypad.dart';
import 'package:poemath/features/math/widgets/practice_scheme_selector.dart';
import 'package:poemath/features/math/widgets/vertical_calc_widget.dart';
import 'package:poemath/features/math/widgets/vertical_process_input.dart';
import 'package:poemath/math_engine/models/vertical_attempt.dart';
import 'package:poemath/math_engine/math_engine.dart';
import 'package:poemath/math_engine/models/answer_judgement.dart';
import 'package:poemath/math_engine/models/difficulty_level.dart';
import 'package:poemath/math_engine/models/math_problem.dart';
import 'package:poemath/math_engine/presets/grade_presets.dart';

/// 计算时间进度条比例（0.0 ~ 1.0）。
///
/// 固定模式以初始秒数为分母；续命模式答对会加时，剩余秒数可能超过初始值，
/// 取两者较大者作分母，保证结果不超过 1.0。
double challengeTimeRatio({
  required int remainingSeconds,
  required int initialSeconds,
  required bool extending,
}) {
  final baseSeconds = extending && remainingSeconds > initialSeconds
      ? remainingSeconds
      : initialSeconds;
  return remainingSeconds / baseSeconds;
}

class MathChallengePage extends ConsumerStatefulWidget {
  const MathChallengePage({super.key, this.random});

  /// 可注入固定随机源，复现挑战题组。
  final Random? random;

  @override
  ConsumerState<MathChallengePage> createState() => _MathChallengePageState();
}

class _MathChallengePageState extends ConsumerState<MathChallengePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _initialSeconds = 60;
  static const _bonusSeconds = 3; // 答对加 3 秒（仅续命模式）
  static const _comboThreshold = 5; // 连续 5 题触发 combo 奖励

  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  /// 挑战模式：'fixed'（固定时间）或 'extending'（续命模式）
  String _challengeMode = 'extending';
  bool _verticalScheme = false;
  MathPracticeRequest? _challengeRequest;
  VerticalAttempt _verticalAttempt = const VerticalAttempt();
  String _verticalField = 'ones';

  /// 剩余时间（秒）
  int _remainingSeconds = _initialSeconds;
  Timer? _timer;

  /// 是否已开始
  bool _started = false;

  /// 是否已结束
  bool _finished = false;
  bool _answerPending = false;
  Timer? _nextProblemTimer;
  DateTime? _completedAt;
  int? _completedElapsed;

  /// 当前题目
  MathProblem? _currentProblem;

  /// 统计
  int _totalAnswered = 0;
  int _correctCount = 0;
  int _currentCombo = 0;
  int _bestCombo = 0;
  int _score = 0;
  int _starsEarned = 0;

  /// 挑战结束后等待所有统计和奖励完成持久化。
  bool _isSaving = false;
  String? _saveError;

  /// 记录实际用时
  DateTime? _startedAt;

  late String _challengeId;

  /// 答对/错 反馈动画
  bool? _lastCorrect;

  late AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _nextProblemTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_started &&
        !_finished &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden)) {
      _timer?.cancel();
      unawaited(_finishChallenge());
    }
  }

  Future<void> _confirmEndChallenge() async {
    if (_isSaving || !_started || _finished) return;
    final end = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('结束这次挑战？'),
        content: const Text('限时挑战不能续练。结束后会结算已回答的题目。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续挑战'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('结束并结算'),
          ),
        ],
      ),
    );
    if (end == true && mounted) {
      _timer?.cancel();
      await _finishChallenge();
    }
  }

  void _startChallenge() {
    if (_started) return;
    final settings = ref.read(settingsRepositoryProvider);
    final grade = ref.read(mathGradeProvider);
    final semester = ref.read(mathSemesterProvider);
    final difficulty = DifficultyLevel.values.byName(settings.mathDifficulty);
    final vertical = _verticalScheme &&
        MathEngine.supportedModes(
          grade: grade,
          semester: semester,
          difficulty: difficulty,
        ).contains(ProblemMode.vertical);
    _challengeRequest = MathPracticeRequest(
      grade: grade,
      semester: semester,
      count: 1,
      difficulty: difficulty,
      mode: vertical ? ProblemMode.vertical : ProblemMode.findResult,
    );
    try {
      _generateProblem();
    } catch (error, stack) {
      _challengeRequest = null;
      AppLogger.e(
        '挑战出题失败',
        tag: 'MathChallenge',
        error: error,
        stackTrace: stack,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前方案暂时无法出题，请调整选择后重试')),
      );
      return;
    }
    setState(() {
      _verticalScheme = vertical;
      _challengeId = 'math_challenge:${DateTime.now().microsecondsSinceEpoch}';
      _started = true;
      _remainingSeconds = _initialSeconds;
      _startedAt = DateTime.now();
    });
    _startTimer();
    if (!_verticalScheme) _focusNode.requestFocus();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final shouldFinish = _remainingSeconds <= 1;
      setState(() {
        _remainingSeconds = shouldFinish ? 0 : _remainingSeconds - 1;
      });

      if (shouldFinish) {
        timer.cancel();
        await _finishChallenge();
      }
    });
  }

  void _generateProblem() {
    final request = _challengeRequest!;
    final problem = MathEngine.generate(
      grade: request.grade,
      semester: request.semester,
      mode: request.mode,
      difficulty: request.difficulty,
      random: widget.random,
    );
    _controller.clear();
    setState(() {
      _currentProblem = problem;
      _lastCorrect = null;
      _answerPending = false;
      _verticalAttempt = const VerticalAttempt();
      _verticalField = 'ones';
    });
  }

  void _submitAnswer() {
    if (_finished || _answerPending || _currentProblem == null) return;
    final problem = _currentProblem!;
    final process = VerticalAttempt.supports(problem) ? _verticalAttempt : null;
    if (process != null && !process.complete(problem)) return;
    final userAnswer = process?.answer(problem) ?? _controller.text.trim();
    if (userAnswer.isEmpty) return;
    _answerPending = true;

    final judgement =
        process?.judge(problem) ?? MathEngine.judge(problem, userAnswer);
    final isCorrect = judgement.isCorrect;

    final sound = ref.read(soundServiceProvider);

    setState(() {
      _totalAnswered++;
      _lastCorrect = isCorrect;

      if (isCorrect) {
        _correctCount++;
        _currentCombo++;
        if (_currentCombo > _bestCombo) _bestCombo = _currentCombo;

        // 基础分 10 + combo 加成
        var points = 10;
        if (_currentCombo >= _comboThreshold) {
          points = 20; // combo 双倍
        }
        _score += points;

        // 仅续命模式答对加时
        if (_challengeMode == 'extending') {
          _remainingSeconds += _bonusSeconds;
        }

        sound.play(SoundEffect.correct);
      } else {
        _currentCombo = 0;
        sound.play(SoundEffect.wrong);
        // 震动反馈
        HapticFeedback.mediumImpact();
        _shakeController.forward(from: 0);
      }
    });

    if (!isCorrect) {
      // setState 是同步闭包不能 await，故在闭包外发起；400ms 后
      // `_generateProblem()` 会替换 `_currentProblem`，所以把当前题目
      // 作为参数传入。内部已兜底异常，不会产生未捕获的异步错误。
      unawaited(_recordMistake(problem, userAnswer, judgement, process));
    }

    _controller.clear();

    // 短暂显示反馈后出下一题
    _nextProblemTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted && !_finished) {
        try {
          _generateProblem();
          if (!_verticalScheme) _focusNode.requestFocus();
        } catch (error, stack) {
          AppLogger.e(
            '挑战换题失败',
            tag: 'MathChallenge',
            error: error,
            stackTrace: stack,
          );
          _timer?.cancel();
          unawaited(_finishChallenge());
        }
      }
    });
  }

  /// 记录错题到 Hive。
  ///
  /// 必须 await 后再 `invalidate`：写入未完成就失效 provider 会让错题本
  /// 读到旧快照；写入失败时记日志并跳过 invalidate（无新数据可读）。
  Future<void> _recordMistake(
    MathProblem problem,
    String userAnswer,
    AnswerJudgement judgement,
    VerticalAttempt? process,
  ) async {
    final grade = problem.grade;
    final repo = ref.read(mathMistakeRepoProvider);

    try {
      await repo.recordWrong(
        problemText: problem.problemText,
        correctAnswer: problem.answerText,
        userAnswer: userAnswer,
        problemType: 'challenge',
        grade: grade,
        errorType: judgement.diagnosis?.category,
        solutionStepsJson: _stepsToJson(judgement.correctSteps),
        skillId: problem.skillId,
        semester: problem.semester,
        problemJson: jsonEncode(problem.toJson()),
        attemptJson: process == null ? null : jsonEncode(process.toJson()),
      );
    } on Object catch (error, stackTrace) {
      // Hive IO 失败抛的是 `HiveError extends Error`，`on Exception` 捕不到；
      // 此处位于 UI 边界，兜底后仅记日志，不打断挑战流程。
      AppLogger.e(
        '挑战错题落库失败',
        tag: 'MathChallenge',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }
    if (!mounted) return;
    ref.invalidate(mathMistakeRepoProvider);
  }

  String? _stepsToJson(List<SolutionStep> steps) {
    if (steps.isEmpty) return null;
    return steps
        .map((s) => '${s.description}|||${s.expression}|||${s.resultHint}')
        .join('\n');
  }

  Future<void> _finishChallenge() async {
    if (_finished || _isSaving) return;
    _nextProblemTimer?.cancel();

    final elapsed = _completedElapsed ??= _startedAt != null
        ? DateTime.now().difference(_startedAt!).inSeconds
        : _initialSeconds;
    final stars = LearningRewardCalculator.calculateStars(
      activityType: LearningActivityType.mathChallenge,
      totalItems: _totalAnswered,
      successfulItems: _correctCount,
    );
    final statsRepo = ref.read(userStatsRepoProvider);
    final levelBeforeReward = statsRepo.get().level;
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _finished = true;
      _isSaving = true;
      _starsEarned = stars;
      _saveError = null;
    });

    try {
      await _saveRecord(elapsed: elapsed, stars: stars);
      if (!mounted) return;
      // 挑战页只落 ChallengeRecord，但「单次全对 / 困难全对」类成就的判定
      // 口径来自 MathSession（见 AchievementChecker._sessionPerfect）。这里把
      // 本次挑战映射成一份内存态 MathSession 传入，不写入 Hive —— 挑战数据
      // 的持久化仍以 ChallengeRecord 为唯一来源，避免出现双份记录。
      final newlyUnlocked = await checkAchievements(
        ref,
        latestSession: _asAchievementSession(elapsed: elapsed, stars: stars),
      );

      if (!mounted) return;

      ref.invalidate(userStatsProvider);
      ref.invalidate(todayCheckInProvider);
      ref.invalidate(todayMathCountProvider);
      ref.invalidate(unlockedAchievementsCountProvider);
      ref.invalidate(challengeRecordRepoProvider);
      ref.invalidate(totalProblemsCountProvider);
      ref.invalidate(overallAccuracyProvider);

      setState(() => _isSaving = false);

      final updatedStats = statsRepo.get();
      if (updatedStats.level > levelBeforeReward) {
        await showCelebration(
          context,
          type: CelebrationType.levelUp,
          subtitle: updatedStats.levelName,
        );
        if (!mounted) return;
      }
      if (newlyUnlocked.isNotEmpty) {
        await showCelebration(
          context,
          type: CelebrationType.achievement,
          subtitle:
              newlyUnlocked.map((achievement) => achievement.title).join('、'),
        );
      }
    } catch (error, stackTrace) {
      AppLogger.e(
        '挑战结算保存失败',
        tag: 'MathChallenge',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = '挑战记录保存失败';
      });
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('挑战记录保存失败')));
    }
  }

  /// 保存挑战记录及其关联统计。
  Future<void> _saveRecord({
    required int elapsed,
    required int stars,
  }) async {
    final request = _challengeRequest!;
    final grade = request.grade;
    final semester = request.semester;
    final difficulty = request.difficulty.name;
    final completedAt = _completedAt ??= DateTime.now();

    final record = ChallengeRecord(
      id: _challengeId,
      profileId: ProfileScope.currentId,
      mode: _challengeMode,
      calculationMode: _verticalScheme ? 'vertical' : 'normal',
      score: _score,
      totalAnswered: _totalAnswered,
      correctCount: _correctCount,
      bestCombo: _bestCombo,
      grade: grade,
      semester: semester,
      difficulty: difficulty,
      durationSeconds: elapsed,
      starsEarned: stars,
      createdAt: completedAt,
    );

    final repo = ref.read(challengeRecordRepoProvider);
    final statsRepo = ref.read(userStatsRepoProvider);
    final checkInRepo = ref.read(checkInRepoProvider);
    final activityRepo = ref.read(learningActivityRepositoryProvider);
    await repo.save(record);
    await activityRepo.record(
      id: record.id,
      activityType: LearningActivityType.mathChallenge,
      totalItems: _totalAnswered,
      successfulItems: _correctCount,
      starsEarned: stars,
      durationSeconds: elapsed,
      completedAt: completedAt,
    );
    await statsRepo.settleMathChallenge(
      activityId: record.id,
      problems: _totalAnswered,
      correct: _correctCount,
      bestStreak: _bestCombo,
      stars: stars,
    );
    await checkInRepo.updateToday(
      activityId: record.id,
      addMathTotal: _totalAnswered,
      addMathCorrect: _correctCount,
      addStars: stars,
      addDuration: elapsed,
    );
  }

  /// 把本次挑战映射为成就判定用的 [MathSession]。
  ///
  /// 仅用于 `checkAchievements(latestSession:)` 的上下文，**不写入 Hive**。
  /// 字段对齐挑战页的统计口径，使「单次全对」（`totalProblems >= n` 且
  /// 正确率 100%）与「困难全对」等成就对挑战模式同样生效。
  MathSession _asAchievementSession({
    required int elapsed,
    required int stars,
  }) {
    return MathSession(
      id: _challengeId,
      profileId: ProfileScope.currentId,
      grade: _challengeRequest!.grade,
      problemType: _verticalScheme ? 'vertical' : 'challenge',
      totalProblems: _totalAnswered,
      correctCount: _correctCount,
      durationSeconds: elapsed,
      starsEarned: stars,
      finishedAt: DateTime.now(),
      semester: _challengeRequest!.semester,
      difficulty: _challengeRequest!.difficulty.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedGrade = ref.watch(mathGradeProvider);
    final selectedSemester = ref.watch(mathSemesterProvider);
    final grade = _challengeRequest?.grade ?? selectedGrade;
    final semester = _challengeRequest?.semester ?? selectedSemester;

    return PopScope(
      canPop: !_isSaving && (!_started || _finished),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmEndChallenge());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${_started && _verticalScheme ? '竖式挑战' : '限时挑战'} · ${GradePresets.get(grade, semester).label}',
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.history_rounded),
              tooltip: '挑战记录',
              onPressed: _isSaving || (_started && !_finished)
                  ? null
                  : () => context.push(AppRoutes.challengeHistory),
            ),
          ],
        ),
        bottomNavigationBar: _started && !_finished && _verticalScheme
            ? _buildVerticalKeypad()
            : null,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: _finished
                ? _buildResult(theme)
                : _started
                    ? _buildChallenge(theme)
                    : _buildStart(theme),
          ),
        ),
      ),
    );
  }

  /// 挑战准备页：内容区可滚动，「开始挑战」吸附在底部。
  ///
  /// 不用「整页 Center + SingleChildScrollView」：那样内容超出屏幕时
  /// 按钮会被推到滚动区底部，窄屏大字号下用户得先滚到底才能开始。
  /// 改为 Column[Expanded(滚动内容), 固定按钮] —— 内容多则滚动，按钮
  /// 始终可见。
  Widget _buildStart(ThemeData theme) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Icon(
                  Icons.timer_rounded,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: SpacingTokens.md),
                Text(
                  '限时挑战',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: SpacingTokens.xs),
                Text(
                  '选择挑战模式',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: SpacingTokens.lg),

                ColoredCard(
                  color: theme.colorScheme.primary,
                  child: PracticeSchemeSelector(
                    grade: ref.watch(mathGradeProvider),
                    semester: ref.watch(mathSemesterProvider),
                    difficulty: DifficultyLevel.values.byName(
                      ref.watch(settingsRepositoryProvider).mathDifficulty,
                    ),
                    vertical: _verticalScheme,
                    onChanged: (value) =>
                        setState(() => _verticalScheme = value),
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),

                // 计时方式
                _buildModeCard(
                  theme,
                  icon: Icons.hourglass_top_rounded,
                  title: '固定时间',
                  description: '$_initialSeconds 秒倒计时，比拼速度与准确率',
                  mode: 'fixed',
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(height: SpacingTokens.sm),
                _buildModeCard(
                  theme,
                  icon: Icons.add_alarm_rounded,
                  title: '续命模式',
                  description: '答对 +$_bonusSeconds 秒，挑战你的极限',
                  mode: 'extending',
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: SpacingTokens.md),

                // 规则说明
                ColoredCard(
                  color: theme.colorScheme.tertiary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: theme.colorScheme.tertiary,
                          ),
                          const SizedBox(width: SpacingTokens.xs),
                          Text(
                            '规则说明',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.tertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: SpacingTokens.xs),
                      Text(
                        '• 答对 +10 分，连续$_comboThreshold题正确双倍得分\n'
                        '${_challengeMode == 'extending' ? '• 答对 +$_bonusSeconds秒，答错不扣时间' : '• 固定$_initialSeconds秒，答对不加时间'}\n'
                        '• 切到后台会结束并结算；离页需先结束挑战\n'
                        '• 挑战不支持续练，强制关闭应用可能丢失本次未结算成绩',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),
              ],
            ),
          ),
        ),
        // 吸附底部：不随内容滚动。
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _startChallenge,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('开始挑战'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(200, 56),
              textStyle: theme.textTheme.titleMedium,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModeCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String description,
    required String mode,
    required Color color,
  }) {
    final isSelected = _challengeMode == mode;
    // 不用 `AppTile`：它在 `trailing` 非空时会把整行的 onTap 置空
    // （设计假设是"trailing 接管交互"，适用于 Switch 那类，但这里的圈
    // 是纯展示），表现为只有圈能点、整行点不动。用 ColoredCard 自建，
    // 整行可点、圈随状态变化。
    return ColoredCard(
      color: isSelected ? color : theme.colorScheme.onSurfaceVariant,
      onTap: () => setState(() => _challengeMode = mode),
      constraints: const BoxConstraints(
        minHeight: SpacingTokens.minTapTarget + SpacingTokens.md,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.md,
        vertical: SpacingTokens.sm + 2,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (isSelected ? color : theme.colorScheme.onSurfaceVariant)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
            ),
            child: Icon(
              icon,
              color:
                  isSelected ? color : theme.colorScheme.onSurfaceVariant,
              size: 22,
            ),
          ),
          const SizedBox(width: SpacingTokens.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // 互斥单选：圈形是标准语汇，未选中态也给出"可选项"的暗示
          // （`AppTile` 默认的 chevron 只说"可进入"）。选中转主题色。
          Icon(
            isSelected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: isSelected ? color : theme.colorScheme.outline,
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalKeypad() {
    final problem = _currentProblem!;
    final process = VerticalAttempt.supports(problem);
    return NumberKeypad(
      onNumberTap: (digit) {
        if (_answerPending) return;
        setState(() {
          if (process) {
            _verticalAttempt =
                _verticalAttempt.withField(_verticalField, digit);
          } else if (NumberKeypad.canAppend(_controller.text, digit)) {
            _controller.text += digit;
          }
        });
      },
      onBackspace: () {
        if (_answerPending) return;
        setState(() {
          if (process) {
            _verticalAttempt = _verticalAttempt.withField(_verticalField, '');
          } else if (_controller.text.isNotEmpty) {
            _controller.text =
                _controller.text.substring(0, _controller.text.length - 1);
          }
        });
      },
      onSubmit: _submitAnswer,
      submitEnabled: !_answerPending &&
          (process
              ? _verticalAttempt.complete(problem)
              : _controller.text.isNotEmpty),
      showDecimal: !process && problem.resultForm == ResultForm.decimal,
      showNegative: !process && problem.result.isNegative,
    );
  }

  Widget _buildChallenge(ThemeData theme) {
    final timeRatio = challengeTimeRatio(
      remainingSeconds: _remainingSeconds,
      initialSeconds: _initialSeconds,
      extending: _challengeMode == 'extending',
    );
    final timeColor =
        timeRatio > 0.3 ? theme.colorScheme.primary : theme.colorScheme.error;
    final problem = _currentProblem!;
    final process = VerticalAttempt.supports(problem);

    return Column(
      children: [
        Wrap(
          spacing: SpacingTokens.lg,
          runSpacing: SpacingTokens.xs,
          alignment: WrapAlignment.center,
          children: [
            Text(
              '${_remainingSeconds}s',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: timeColor,
              ),
            ),
            Text(
              '$_score 分',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            if (_currentCombo >= 2)
              Text(
                '连对 $_currentCombo 题',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.semantic.caution,
                ),
              ),
          ],
        ),
        const SizedBox(height: SpacingTokens.xs),
        LinearProgressIndicator(
          value: timeRatio.clamp(0.0, 1.0),
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation(timeColor),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: SpacingTokens.lg),
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: _shakeController,
                  builder: (context, child) {
                    final dx = _shakeController.isAnimating
                        ? 10 *
                            (1 - _shakeController.value) *
                            (_shakeController.value * 4 * 3.14159)
                                .remainder(3.14159)
                                .abs()
                        : 0.0;
                    return Transform.translate(
                      offset: Offset(dx, 0),
                      child: child,
                    );
                  },
                  child: Column(
                    children: [
                      if (_lastCorrect != null)
                        Icon(
                          _lastCorrect! ? Icons.check_circle : Icons.cancel,
                          size: 32,
                          color: _lastCorrect!
                              ? theme.semantic.success
                              : theme.colorScheme.error,
                        ),
                      const SizedBox(height: SpacingTokens.md),
                      if (_verticalScheme)
                        Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: VerticalCalcWidget(problem: problem),
                          ),
                        )
                      else
                        MathText(
                          problem.problemText,
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: SpacingTokens.lg),
                if (_verticalScheme)
                  if (process)
                    IgnorePointer(
                      ignoring: _answerPending,
                      child: VerticalProcessInput(
                        problem: problem,
                        attempt: _verticalAttempt,
                        selectedField: _verticalField,
                        onSelect: (field) =>
                            setState(() => _verticalField = field),
                      ),
                    )
                  else ...[
                    ColoredCard(
                      color: theme.colorScheme.primary,
                      width: double.infinity,
                      child: Text(
                        _controller.text.isEmpty ? '输入答案' : _controller.text,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: SpacingTokens.sm),
                    const Text('本题填写结果；两位数整数加减法支持逐列过程练习。'),
                  ]
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: '输入答案',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                SpacingTokens.radiusMedium,
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _submitAnswer(),
                        ),
                      ),
                      const SizedBox(width: SpacingTokens.sm),
                      FilledButton(
                        onPressed: _answerPending ? null : _submitAnswer,
                        child: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                const SizedBox(height: SpacingTokens.md),
                Text(
                  '已答 $_totalAnswered 题 · 正确 $_correctCount 题',
                  style: theme.textTheme.bodySmall,
                ),
                if (_challengeMode == 'extending') const Text('续命'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult(ThemeData theme) {
    final accuracy =
        _totalAnswered > 0 ? (_correctCount / _totalAnswered * 100).round() : 0;

    return Center(
      child: AnimatedPageBody(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        children: [
          const SizedBox(height: SpacingTokens.xl),
          Icon(
            Icons.emoji_events_rounded,
            size: 80,
            color: theme.semantic.caution,
          ),
          const SizedBox(height: SpacingTokens.md),
          Text(
            '挑战结束！',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: SpacingTokens.xs),
          // 模式标签
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.sm,
              vertical: SpacingTokens.xs,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(SpacingTokens.radiusPill),
            ),
            child: Text(
              "${_verticalScheme ? '竖式' : '普通'} · ${_challengeMode == 'fixed' ? '固定时间' : '续命模式'}",
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),

          // 分数大字
          Text(
            '$_score',
            style: theme.textTheme.displayLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          Text(
            '总分',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < 3; index++)
                Icon(
                  index < _starsEarned
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 32,
                  color: index < _starsEarned
                      ? theme.semantic.caution
                      : theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
          Text(
            '获得 $_starsEarned 颗星',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),

          // 详细统计
          ColoredCard(
            color: theme.colorScheme.primary,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildResultStat(
                      theme,
                      '$_totalAnswered',
                      '总答题',
                      theme.colorScheme.primary,
                    ),
                    _buildResultStat(
                      theme,
                      '$_correctCount',
                      '答对',
                      theme.semantic.success,
                    ),
                    _buildResultStat(
                      theme,
                      '$accuracy%',
                      '正确率',
                      theme.colorScheme.secondary,
                    ),
                    _buildResultStat(
                      theme,
                      '$_bestCombo',
                      '最佳连击',
                      theme.semantic.caution,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),

          if (_isSaving) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: SpacingTokens.sm),
            Text(
              '正在保存挑战结果',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SpacingTokens.lg),
          ] else if (_saveError != null) ...[
            Text(
              _saveError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: SpacingTokens.sm),
          ],

          // 操作按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _isSaving ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('返回'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ),
              const SizedBox(width: SpacingTokens.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _restartChallenge,
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('再来一次'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.lg),
        ],
      ),
    );
  }

  Widget _buildResultStat(
    ThemeData theme,
    String value,
    String label,
    Color color,
  ) {
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: SpacingTokens.xs),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  void _restartChallenge() {
    _nextProblemTimer?.cancel();
    _answerPending = false;
    _completedAt = null;
    _completedElapsed = null;
    setState(() {
      _started = false;
      _finished = false;
      _challengeRequest = null;
      _totalAnswered = 0;
      _correctCount = 0;
      _currentCombo = 0;
      _bestCombo = 0;
      _score = 0;
      _starsEarned = 0;
      _isSaving = false;
      _saveError = null;
      _remainingSeconds = _initialSeconds;
      _currentProblem = null;
      _lastCorrect = null;
      _startedAt = null;
    });
    _timer?.cancel();
    _controller.clear();
  }
}
