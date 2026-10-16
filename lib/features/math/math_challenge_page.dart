// lib/features/math/math_challenge_page.dart
//
// 层级：features/math
// 职责：口算限时挑战 — 支持两种模式：
//       固定时间（60 秒纯倒计时）和续命模式（答对加时）。
//       挑战结束后自动保存记录。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
  const MathChallengePage({super.key});

  @override
  ConsumerState<MathChallengePage> createState() => _MathChallengePageState();
}

class _MathChallengePageState extends ConsumerState<MathChallengePage>
    with TickerProviderStateMixin {
  static const _initialSeconds = 60;
  static const _bonusSeconds = 3; // 答对加 3 秒（仅续命模式）
  static const _comboThreshold = 5; // 连续 5 题触发 combo 奖励

  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  /// 挑战模式：'fixed'（固定时间）或 'extending'（续命模式）
  String _challengeMode = 'extending';

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
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _nextProblemTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _startChallenge() {
    setState(() {
      _challengeId = 'math_challenge:${DateTime.now().microsecondsSinceEpoch}';
      _started = true;
      _remainingSeconds = _initialSeconds;
      _startedAt = DateTime.now();
    });
    _generateProblem();
    _startTimer();
    _focusNode.requestFocus();
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
    final grade = ref.read(mathGradeProvider);
    final semester = ref.read(mathSemesterProvider);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final difficulty = DifficultyLevel.values.firstWhere(
      (d) => d.name == settingsRepo.mathDifficulty,
      orElse: () => DifficultyLevel.medium,
    );

    final problem = MathEngine.generate(
      grade: grade,
      semester: semester,
      mode: ProblemMode.findResult,
      difficulty: difficulty,
    );
    setState(() {
      _currentProblem = problem;
      _lastCorrect = null;
      _answerPending = false;
    });
  }

  void _submitAnswer() {
    if (_finished || _answerPending || _currentProblem == null) return;
    final userAnswer = _controller.text.trim();
    if (userAnswer.isEmpty) return;
    _answerPending = true;

    final problem = _currentProblem!;
    final judgement = MathEngine.judge(problem, userAnswer);
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
      unawaited(_recordMistake(problem, userAnswer, judgement));
    }

    _controller.clear();

    // 短暂显示反馈后出下一题
    _nextProblemTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted && !_finished) {
        _generateProblem();
        _focusNode.requestFocus();
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
  ) async {
    final grade = ref.read(mathGradeProvider);
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
    final grade = ref.read(mathGradeProvider);
    final semester = ref.read(mathSemesterProvider);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final difficulty = settingsRepo.mathDifficulty;
    final completedAt = _completedAt ??= DateTime.now();

    final record = ChallengeRecord(
      id: _challengeId,
      profileId: ProfileScope.currentId,
      mode: _challengeMode,
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
      grade: ref.read(mathGradeProvider),
      problemType: 'challenge',
      totalProblems: _totalAnswered,
      correctCount: _correctCount,
      durationSeconds: elapsed,
      starsEarned: stars,
      finishedAt: DateTime.now(),
      semester: ref.read(mathSemesterProvider),
      difficulty: ref.read(settingsRepositoryProvider).mathDifficulty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grade = ref.watch(mathGradeProvider);
    final semester = ref.watch(mathSemesterProvider);

    return PopScope(
      canPop: !_isSaving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '限时挑战 · ${GradePresets.get(grade, semester).label}',
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.history_rounded),
              tooltip: '挑战记录',
              onPressed: _isSaving
                  ? null
                  : () => context.push(AppRoutes.challengeHistory),
            ),
          ],
        ),
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

  Widget _buildStart(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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

            // 模式选择卡片
            Row(
              children: [
                Expanded(
                  child: _buildModeCard(
                    theme,
                    icon: Icons.hourglass_top_rounded,
                    title: '固定时间',
                    description: '$_initialSeconds秒倒计时\n比拼速度与准确率',
                    mode: 'fixed',
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: _buildModeCard(
                    theme,
                    icon: Icons.add_alarm_rounded,
                    title: '续命模式',
                    description: '答对+$_bonusSeconds秒\n挑战你的极限',
                    mode: 'extending',
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
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
                    '${_challengeMode == 'extending' ? '• 答对 +$_bonusSeconds秒，答错不扣时间' : '• 固定$_initialSeconds秒，答对不加时间'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SpacingTokens.lg),

            FilledButton.icon(
              onPressed: _startChallenge,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('开始挑战'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(200, 56),
                textStyle: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
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

    return GestureDetector(
      onTap: () => setState(() => _challengeMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(SpacingTokens.md),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 40,
              color: isSelected ? color : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: SpacingTokens.sm),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: isSelected ? color : null,
              ),
            ),
            const SizedBox(height: SpacingTokens.xs),
            Text(
              description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
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

    return Column(
      children: [
        // 顶部状态栏：时间 + 分数 + combo
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 时间
            Row(
              children: [
                Icon(Icons.timer, color: timeColor, size: 24),
                const SizedBox(width: SpacingTokens.xs),
                Text(
                  '${_remainingSeconds}s',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: timeColor,
                  ),
                ),
              ],
            ),
            // 分数
            Text(
              '$_score 分',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            // Combo
            if (_currentCombo >= 2)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: SpacingTokens.sm,
                  vertical: SpacingTokens.xs,
                ),
                decoration: BoxDecoration(
                  color: theme.semantic.caution.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(SpacingTokens.radiusPill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 16,
                      color: theme.semantic.caution,
                    ),
                    const SizedBox(width: SpacingTokens.xs),
                    Text(
                      'x$_currentCombo',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.semantic.caution,
                      ),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: SpacingTokens.xs),

        // 时间进度条
        ClipRRect(
          borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
          child: LinearProgressIndicator(
            value: timeRatio.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(timeColor),
          ),
        ),

        const Spacer(),

        // 题目
        if (_currentProblem != null)
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
                // 反馈指示器
                if (_lastCorrect != null)
                  Icon(
                    _lastCorrect! ? Icons.check_circle : Icons.cancel,
                    size: 32,
                    color: _lastCorrect!
                        ? theme.semantic.success
                        : theme.colorScheme.error,
                  ).animate().fadeIn(duration: 200.ms).scale(
                        begin: const Offset(0.5, 0.5),
                        end: const Offset(1, 1),
                        duration: 200.ms,
                      ),
                const SizedBox(height: SpacingTokens.md),
                Text(
                  _currentProblem!.problemText,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

        const Spacer(),

        // 输入框
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                // 挑战页年级覆盖 1-6 全 resultForm，含小数/分数/负数题；
                // TextInputType.number 在 Android 上无小数点与负号，
                // 必须显式开启 decimal + signed。
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
              onPressed: _submitAnswer,
              style: FilledButton.styleFrom(
                minimumSize: const Size(64, 56),
              ),
              child: const Icon(Icons.send_rounded),
            ),
          ],
        ),
        const SizedBox(height: SpacingTokens.md),

        // 底部统计
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '已答 $_totalAnswered 题 · 正确 $_correctCount 题',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_challengeMode == 'extending') ...[
              const SizedBox(width: SpacingTokens.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: SpacingTokens.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.circular(SpacingTokens.radiusSmall),
                ),
                child: Text(
                  '续命',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: SpacingTokens.md),
      ],
    );
  }

  Widget _buildResult(ThemeData theme) {
    final accuracy =
        _totalAnswered > 0 ? (_correctCount / _totalAnswered * 100).round() : 0;

    return Center(
      child: AnimatedPageBody(
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
              _challengeMode == 'fixed' ? '固定时间' : '续命模式',
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
