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
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/challenge_record.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/math_engine/math_engine.dart';
import 'package:poemath/math_engine/models/answer_judgement.dart';
import 'package:poemath/math_engine/models/difficulty_level.dart';
import 'package:poemath/math_engine/models/math_problem.dart';
import 'package:poemath/math_engine/presets/grade_presets.dart';

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

  /// 当前题目
  MathProblem? _currentProblem;

  /// 统计
  int _totalAnswered = 0;
  int _correctCount = 0;
  int _currentCombo = 0;
  int _bestCombo = 0;
  int _score = 0;

  /// 记录实际用时
  DateTime? _startedAt;

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
    _controller.dispose();
    _focusNode.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _startChallenge() {
    setState(() {
      _started = true;
      _remainingSeconds = _initialSeconds;
      _startedAt = DateTime.now();
    });
    _generateProblem();
    _startTimer();
    _focusNode.requestFocus();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds <= 0) {
          _remainingSeconds = 0;
          _finished = true;
          timer.cancel();
          _saveRecord();
        }
      });
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
    });
  }

  void _submitAnswer() {
    if (_finished || _currentProblem == null) return;
    final userAnswer = _controller.text.trim();
    if (userAnswer.isEmpty) return;

    final judgement = MathEngine.judge(_currentProblem!, userAnswer);
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
        _recordMistake(_currentProblem!, userAnswer, judgement);
        sound.play(SoundEffect.wrong);
        // 震动反馈
        HapticFeedback.mediumImpact();
        _shakeController.forward(from: 0);
      }
    });

    _controller.clear();

    // 短暂显示反馈后出下一题
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted && !_finished) {
        _generateProblem();
        _focusNode.requestFocus();
      }
    });
  }

  /// 记录错题到 Hive
  void _recordMistake(
    MathProblem problem,
    String userAnswer,
    AnswerJudgement judgement,
  ) {
    final grade = ref.read(mathGradeProvider);
    final repo = ref.read(mathMistakeRepoProvider);

    final mistake = MathMistake(
      id: 'challenge_${DateTime.now().millisecondsSinceEpoch}_$_totalAnswered',
      profileId: ProfileScope.currentId,
      problemText: problem.problemText,
      correctAnswer: problem.answerText,
      userAnswer: userAnswer,
      problemType: 'challenge',
      grade: grade,
      errorType: judgement.diagnosis?.category,
      solutionStepsJson: _stepsToJson(judgement.correctSteps),
    );

    repo.add(mistake);
    ref.invalidate(mathMistakeRepoProvider);
  }

  String? _stepsToJson(List<SolutionStep> steps) {
    if (steps.isEmpty) return null;
    return steps
        .map((s) => '${s.description}|||${s.expression}|||${s.resultHint}')
        .join('\n');
  }

  /// 保存挑战记录到 Hive
  void _saveRecord() {
    final grade = ref.read(mathGradeProvider);
    final semester = ref.read(mathSemesterProvider);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final difficulty = settingsRepo.mathDifficulty;

    final elapsed = _startedAt != null
        ? DateTime.now().difference(_startedAt!).inSeconds
        : _initialSeconds;

    final record = ChallengeRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
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
    );

    final repo = ref.read(challengeRecordRepoProvider);
    repo.save(record);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grade = ref.watch(mathGradeProvider);
    final semester = ref.watch(mathSemesterProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '限时挑战 · ${GradePresets.get(grade, semester).label}',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: '挑战记录',
            onPressed: () => context.push(AppRoutes.challengeHistory),
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
            Icon(icon, size: 40, color: isSelected ? color : theme.colorScheme.onSurfaceVariant),
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
    // 固定模式: 正常 ratio; 续命模式: 防止超过 1.0
    final baseSeconds = _challengeMode == 'extending'
        ? _remainingSeconds.clamp(_initialSeconds, _remainingSeconds)
        : _initialSeconds;
    final timeRatio = _remainingSeconds / baseSeconds;
    final timeColor = timeRatio > 0.3
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

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
                  borderRadius:
                      BorderRadius.circular(SpacingTokens.radiusPill),
                ),
                child: Text(
                  '🔥 x$_currentCombo',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.semantic.caution,
                  ),
                ),
              )
            else
              const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: SpacingTokens.xs),

        // 时间进度条
        ClipRRect(
          borderRadius:
              BorderRadius.circular(SpacingTokens.radiusSmall),
          child: LinearProgressIndicator(
            value: timeRatio.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor:
                theme.colorScheme.surfaceContainerHighest,
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
                keyboardType: TextInputType.number,
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
              borderRadius:
                  BorderRadius.circular(SpacingTokens.radiusPill),
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

          // 操作按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
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
                  onPressed: _restartChallenge,
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
    setState(() {
      _started = false;
      _finished = false;
      _totalAnswered = 0;
      _correctCount = 0;
      _currentCombo = 0;
      _bestCombo = 0;
      _score = 0;
      _remainingSeconds = _initialSeconds;
      _currentProblem = null;
      _lastCorrect = null;
      _startedAt = null;
    });
    _timer?.cancel();
    _controller.clear();
  }
}
