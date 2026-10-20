// lib/features/math/math_practice_page.dart
//
// 口算练习页：题目展示 → 用户输入 → 判定反馈 → 分步讲解。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/celebration_dialog.dart';
import 'package:poemath/core/widgets/confetti_overlay.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/achievement_check_helper.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/widgets/math_ai_explain_sheet.dart';
import 'package:poemath/features/math/widgets/math_text.dart';
import 'package:poemath/features/math/widgets/number_keypad.dart';
import 'package:poemath/features/math/widgets/session_result_dialog.dart';
import 'package:poemath/features/math/widgets/vertical_calc_widget.dart';
import 'package:poemath/features/math/widgets/vertical_process_input.dart';
import 'package:poemath/math_engine/models/vertical_attempt.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/features/math/math_practice_request.dart';
import 'package:poemath/features/math/practice_clock.dart';
import 'package:poemath/features/math/practice_resume_prompt.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';

class MathPracticePage extends ConsumerStatefulWidget {
  const MathPracticePage({super.key, this.resume = false});
  final bool resume;

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
  DateTime? _completedAt;
  bool _submitting = false;

  /// 当前连续答对数（答错时清零）
  int _consecutiveCorrect = 0;

  /// 本次练习最佳连续答对数
  int _bestConsecutive = 0;

  /// 当前页面固定使用的题数，避免“再练一组”丢失临时覆盖。
  int? _sessionBatchSize;
  MathPracticeRequest? _request;
  String? _generationError;
  final _drafts = PracticeDraftRepository();
  late final PracticeClock _clock;
  List<MathProblem> _sessionProblems = [];
  int _draftIndex = 0;
  bool _ready = false;
  bool _draftDisabled = false;
  Timer? _draftTimer;
  VerticalAttempt _verticalAttempt = const VerticalAttempt();
  String _verticalField = 'ones';

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _sessionId = DateTime.now().microsecondsSinceEpoch.toString();
    _confettiController = CelebrationController();
    _clock = PracticeClock()..onPause = _saveOnPause;
    _answerController.addListener(_queueDraftSave);

    // 延迟到 build 之后初始化题目
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_initialize());
    });
  }

  Future<void> _initialize() async {
    try {
      final draft = _drafts.get('math');
      // 本次入口想练什么（口算/竖式卡片各自 setNext 的意图）。
      // 在弹恢复框**之前**同步捕获：`consume()` 会清空 provider，
      // 弹窗 await 后再读就拿不到了。peek() 只读不消费。
      final intent = ref.read(nextMathPracticeRequestProvider.notifier).peek();
      if (draft != null) {
        // 意图分流：从口算/竖式卡片进入时，用户已经选定了方案。
        // 若待恢复的草稿是**另一种**方案（如从竖式入口遇到普通草稿），
        // 不弹恢复框、直接丢弃旧草稿开始新练习 —— 恢复它等于劫持入口
        // 意图（用户点"竖式计算"却被带回普通口算），而静默丢弃 setNext
        // 的请求还会让"开始新练习"也偏离所选方案。
        // 首页 `?resume=1` 与无预设请求的进入（intent == null）不受影响，
        // 仍走原弹窗/直接恢复语义。
        final draftIsVertical =
            (draft['request'] as Map<String, dynamic>?)?['mode'] ==
                ProblemMode.vertical.name;
        final intentIsVertical = intent?.mode == ProblemMode.vertical;
        final sameScheme =
            intent == null || draftIsVertical == intentIsVertical;

        final resume = !sameScheme
            ? false // 意图不同：丢草稿走新练习（下方 remove）。
            : widget.resume
                ? true
                : await choosePracticeResume(context, '口算');
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
          ref.read(nextMathPracticeRequestProvider.notifier).consume();
          await _restoreDraft(draft);
          return;
        }
        await _drafts.remove('math');
      }
      if (mounted) _generateProblems();
    } catch (error, stack) {
      AppLogger.e(
        '续练初始化失败',
        tag: 'MathPractice',
        error: error,
        stackTrace: stack,
      );
      if (!mounted) return;
      if (_ready) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('练习已恢复，进度或结算暂未保存，请重试')),
        );
      } else {
        setState(() => _generationError = '上次练习暂时无法恢复，请返回首页放弃草稿后重试');
      }
    }
  }

  Future<void> _restoreDraft(Map<String, dynamic> draft) async {
    final problems = (draft['problems'] as List<dynamic>)
        .map(
          (p) => MathProblem.fromJson(p as Map<String, dynamic>),
        )
        .toList();
    final records = (draft['records'] as List<dynamic>)
        .map(
          (r) => ProblemRecord.fromJson(r as Map<String, dynamic>),
        )
        .toList();
    final index = draft['index'] as int;
    if (problems.isEmpty ||
        index < 0 ||
        index >= problems.length ||
        records.length < index ||
        records.length > index + 1) {
      throw const FormatException('草稿答题位置无效');
    }
    _request =
        MathPracticeRequest.fromJson(draft['request'] as Map<String, dynamic>);
    _sessionBatchSize = _request!.count;
    _sessionProblems = problems;
    _draftIndex = index;
    _problemRecords.addAll(records);
    _sessionId = draft['sessionId'] as String;
    _startTime = DateTime.parse(draft['startedAt'] as String);
    _completedAt = DateTime.tryParse(draft['completedAt'] as String? ?? '');
    _consecutiveCorrect = draft['consecutiveCorrect'] as int? ?? 0;
    _bestConsecutive = draft['bestConsecutive'] as int? ?? 0;
    _clock.start(elapsedMilliseconds: draft['elapsedMilliseconds'] as int);
    if (_completedAt != null) _clock.finish();
    _answerController.text = draft['input'] as String? ?? '';
    if (draft['verticalAttempt'] case final Map<String, dynamic> attempt) {
      _verticalAttempt = VerticalAttempt.fromJson(attempt);
    }
    _verticalField = draft['verticalField'] as String? ?? 'ones';
    ref.read(mathProblemsProvider.notifier).state = problems;
    ref.read(mathCurrentIndexProvider.notifier).state = index;
    ref.read(mathAnsweredCountProvider.notifier).state = records.length;
    ref.read(mathCorrectCountProvider.notifier).state =
        records.where((r) => r.isCorrect).length;
    if (records.length > index) {
      final record = records[index];
      _judgement =
          VerticalAttempt.supports(problems[index]) && record.attempt != null
              ? VerticalAttempt.fromJson(record.attempt!).judge(problems[index])
              : MathEngine.judge(problems[index], record.userAnswer);
    }
    _submitting = true;
    if (mounted) setState(() => _ready = true);
    try {
      if (records.isNotEmpty) await _persistProgress();
      if (_completedAt != null && mounted) await _finishSession();
    } finally {
      _submitting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveDraft() async {
    if (!_ready ||
        _draftDisabled ||
        _sessionProblems.isEmpty ||
        _request == null) {
      return;
    }
    await _drafts.save('math', {
      'sessionId': _sessionId,
      'startedAt': _startTime.toIso8601String(),
      'completedAt': _completedAt?.toIso8601String(),
      'elapsedMilliseconds': _clock.elapsedMilliseconds,
      'request': _request!.toJson(),
      'index': _draftIndex,
      'input': _answerController.text,
      'verticalAttempt': _verticalAttempt.toJson(),
      'verticalField': _verticalField,
      'problems': _sessionProblems.map((p) => p.toJson()).toList(),
      'records': _problemRecords.map((r) => r.toJson()).toList(),
      'consecutiveCorrect': _consecutiveCorrect,
      'bestConsecutive': _bestConsecutive,
    });
  }

  void _queueDraftSave() {
    if (_draftDisabled) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 200), () {
      unawaited(
        _saveDraft().catchError((Object error, StackTrace stack) {
          AppLogger.e(
            '续练草稿保存失败',
            tag: 'MathPractice',
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
          '暂停时保存草稿失败',
          tag: 'MathPractice',
          error: error,
          stackTrace: stack,
        );
      }),
    );
  }

  void _generateProblems() {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final batchSize = _sessionBatchSize ??= ref
        .read(mathBatchSizeOverrideProvider.notifier)
        .consumeOr(settingsRepo.mathBatchSize);
    final defaultDifficulty = DifficultyLevel.values.firstWhere(
      (d) => d.name == settingsRepo.mathDifficulty,
      orElse: () => DifficultyLevel.medium,
    );
    final request = _request ??=
        ref.read(nextMathPracticeRequestProvider.notifier).consume() ??
            MathPracticeRequest(
              grade: ref.read(mathGradeProvider),
              semester: ref.read(mathSemesterProvider),
              count: batchSize,
              mode: ref.read(mathPracticeModeProvider),
              difficulty: defaultDifficulty,
            );
    final grade = request.grade;
    final semester = request.semester;
    final difficulty = request.difficulty;
    var practiceMode = request.mode;

    if (practiceMode != null &&
        !MathEngine.supportedModes(
          grade: grade,
          semester: semester,
          difficulty: difficulty,
        ).contains(practiceMode)) {
      if (request.skillId != null) {
        setState(() => _generationError = '当前年级或难度不支持此专项模式，请返回选择其他练习');
        ref.read(mathProblemsProvider.notifier).state = [];
        return;
      }
      practiceMode = null;
      ref.read(mathPracticeModeProvider.notifier).state = null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所选模式不适用于当前年级或难度，已切换为综合练习')),
      );
    }

    List<MathProblem> problems;
    try {
      problems = MathEngine.generateBatch(
        grade: grade,
        semester: semester,
        count: request.count,
        mode: practiceMode,
        difficulty: difficulty,
        skillId: request.skillId,
        verticalProcessOnly: request.verticalProcessOnly,
      );
    } catch (_) {
      ref.read(mathProblemsProvider.notifier).state = [];
      setState(() => _generationError = '当前册次或模式无法生成这一专项，请返回调整选择');
      return;
    }
    _generationError = null;
    _sessionProblems = problems;
    _draftIndex = 0;
    _verticalAttempt = const VerticalAttempt();
    _verticalField = 'ones';
    _draftDisabled = false;
    _ready = true;
    _clock.start();
    _queueDraftSave();

    ref.read(mathProblemsProvider.notifier).state = problems;
    ref.read(mathCurrentIndexProvider.notifier).state = 0;
    ref.read(mathCorrectCountProvider.notifier).state = 0;
    ref.read(mathAnsweredCountProvider.notifier).state = 0;
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _clock.dispose();
    unawaited(
      _saveDraft().catchError((Object error, StackTrace stack) {
        AppLogger.e(
          '退出时保存草稿失败',
          tag: 'MathPractice',
          error: error,
          stackTrace: stack,
        );
      }),
    );
    _answerController.dispose();
    _focusNode.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  /// 按固定题组和题序写入检查点，恢复后允许幂等重放。
  Future<void> _persistProgress() async {
    final answered = ref.read(mathAnsweredCountProvider);
    final correctCount = ref.read(mathCorrectCountProvider);
    final duration = _clock.elapsedSeconds;
    final sessions = ref.read(mathSessionRepositoryProvider);
    final stats = ref.read(userStatsRepositoryProvider);
    final mistakes = ref.read(mathMistakeRepoProvider);

    // 更新运行中的 session（同一 ID 覆盖写入）
    final session = MathSession(
      id: _sessionId,
      profileId: ProfileScope.currentId,
      grade: _request!.grade,
      problemType: 'mixed',
      totalProblems: answered,
      correctCount: correctCount,
      durationSeconds: duration,
      starsEarned: 0,
      startedAt: _startTime,
      finishedAt: DateTime.now(),
      isComplete: false,
      semester: _request!.semester,
      difficulty: _request!.difficulty.name,
      problemsJson: jsonEncode(
        _problemRecords.map((r) => r.toJson()).toList(),
      ),
    );
    if (_completedAt == null) await _drafts.guard(() => sessions.save(session));

    // 增量更新用户统计（每题 +1），与其余练习页共用同一仓储写入路径。
    for (var i = 0; i < _problemRecords.length; i++) {
      await _drafts.guard(
        () => stats.recordMathAttempt(
          isCorrect: _problemRecords[i].isCorrect,
          bestStreak: _bestConsecutive,
          activityId: 'math_attempt:$_sessionId:$i',
        ),
      );
      final record = _problemRecords[i];
      if (!record.isCorrect) {
        final problem = _sessionProblems[i];
        final judgement =
            VerticalAttempt.supports(problem) && record.attempt != null
                ? VerticalAttempt.fromJson(record.attempt!).judge(problem)
                : MathEngine.judge(problem, record.userAnswer);
        await _drafts.guard(
          () => mistakes.recordWrong(
            problemText: problem.problemText,
            correctAnswer: problem.answerText,
            userAnswer: record.userAnswer,
            problemType: _problemTypeLabel(problem),
            grade: problem.grade,
            errorType: judgement.diagnosis?.category,
            solutionStepsJson: _stepsToJson(judgement.correctSteps),
            skillId: problem.skillId,
            semester: problem.semester,
            problemJson: jsonEncode(problem.toJson()),
            attemptJson:
                record.attempt == null ? null : jsonEncode(record.attempt),
            activityId: 'math_mistake_attempt:$_sessionId:$i',
          ),
        );
      }
    }

    // 刷新 providers
    if (mounted) {
      ref.invalidate(userStatsProvider);
      ref.invalidate(todayMathCountProvider);
      ref.invalidate(mathMistakeRepoProvider);
    }
  }

  void _submitAnswer() {
    final problem = ref.read(currentProblemProvider);
    if (problem == null || _judgement != null) return;

    if (VerticalAttempt.supports(problem)) {
      if (_verticalAttempt.complete(problem)) {
        _processAnswer(problem, _verticalAttempt.answer(problem));
      }
      return;
    }
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
    if (_submitting) return;
    final process = VerticalAttempt.supports(problem) ? _verticalAttempt : null;
    final judgement =
        process?.judge(problem) ?? MathEngine.judge(problem, userAnswer);
    setState(() {
      _submitting = true;
      _judgement = judgement;
      _showSteps = false;
    });

    // 音效和触觉反馈
    final sound = ref.read(soundServiceProvider);
    final haptic = ref.read(hapticServiceProvider);
    ref.read(mathAnsweredCountProvider.notifier).update((s) => s + 1);
    if (judgement.isCorrect) {
      ref.read(mathCorrectCountProvider.notifier).update((s) => s + 1);
      _consecutiveCorrect++;
      if (_consecutiveCorrect > _bestConsecutive) {
        _bestConsecutive = _consecutiveCorrect;
      }
    } else {
      _consecutiveCorrect = 0;
    }

    // 记录本题详情
    _problemRecords.add(
      ProblemRecord(
        problemText: problem.problemText,
        answerText: problem.answerText,
        userAnswer: userAnswer,
        isCorrect: judgement.isCorrect,
        skillId: problem.skillId,
        problem: problem.toJson(),
        attempt: process?.toJson(),
      ),
    );

    try {
      await _saveDraft();
      await _persistProgress();
      sound.play(judgement.isCorrect ? SoundEffect.correct : SoundEffect.wrong);
      if (judgement.isCorrect) {
        await haptic.medium();
        if (mounted) _confettiController.play();
      } else {
        await haptic.heavy();
      }
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '答题反馈失败',
        tag: 'MathPractice',
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
    if (_submitting || _judgement == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      await _saveDraft();
      await _persistProgress();
      if (!mounted) return;
      if (_draftIndex + 1 >= _sessionProblems.length) {
        if (!_isFinishing) {
          _isFinishing = true;
          await _finishSession();
        }
        return;
      }
      ref.read(mathCurrentIndexProvider.notifier).update((s) => s + 1);
      _draftIndex++;
      _answerController.clear();
      _verticalAttempt = const VerticalAttempt();
      _verticalField = 'ones';
      setState(() {
        _judgement = null;
        _showSteps = false;
      });
      _focusNode.requestFocus();
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
    // 结算主体包 `try/finally`：任一 await 抛错（Hive IO、成就检查等）都必须
    // 复位 `_isFinishing`，否则 `_nextProblem` 的防重入守卫会永久拦住后续结算，
    // 用户只能退出页面才能恢复。与 `poem_quiz_page._finishQuiz` 同法。
    try {
      await _settleSession();
    } finally {
      _isFinishing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _settleSession() async {
    final grade = _request!.grade;
    final problems = ref.read(mathProblemsProvider);
    final correctCount = ref.read(mathCorrectCountProvider);
    final completedAt = _completedAt ??= DateTime.now();
    _clock.finish();
    final duration = _clock.elapsedSeconds;
    final draftWrite = _saveDraft();

    final stars = LearningRewardCalculator.calculateStars(
      activityType: LearningActivityType.mathPractice,
      totalItems: problems.length,
      successfulItems: correctCount,
    );

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
      startedAt: _startTime,
      finishedAt: completedAt,
      semester: _request!.semester,
      difficulty: _request!.difficulty.name,
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
    final activityId = 'math_practice:${session.id}';
    await _drafts.guard(
      () => activityRepo.record(
        id: activityId,
        activityType: LearningActivityType.mathPractice,
        totalItems: problems.length,
        successfulItems: correctCount,
        starsEarned: stars,
        durationSeconds: duration,
        completedAt: completedAt,
      ),
    );

    // 做题数和连对数已在 _persistProgress() 中逐题更新，只需添加星星
    final levelBeforeReward = statsRepo.get().level;
    if (stars > 0) {
      await _drafts.guard(
        () => statsRepo.addStars(
          stars,
          activityId: activityId,
        ),
      );
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
      await _drafts.remove('math', sessionId: _sessionId);
    } catch (_) {
      _draftDisabled = false;
      rethrow;
    }

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
    if (!mounted) return;
    final newlyUnlocked = await checkAchievements(ref, latestSession: session);
    if (!mounted) return;

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
      // 允许点击空白收起：返回值 null 走 else 分支（返回上一页）。
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
      // 'home' 或 dismiss → 返回上一页。
      // 深链直达 /math/practice 时栈内没有上一页，pop 会断言失败（用户卡在
      // 结算后的空白页），此时直接回首页。
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.home);
      }
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
    _sessionId = DateTime.now().microsecondsSinceEpoch.toString();
    _completedAt = null;
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

    if (!_ready || problems.isEmpty || problem == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('口算练习')),
        body: Center(
          child: _generationError == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(SpacingTokens.lg),
                  child: Text(_generationError!),
                ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${currentIndex + 1} / ${problems.length}'),
        actions: [
          _buildAiExplainAction(context),
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
      bottomNavigationBar: _buildAnswerControls(context),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.md,
              vertical: SpacingTokens.sm,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final question = Column(
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
                );
                final progress = LinearProgressIndicator(
                  value: (currentIndex + 1) / problems.length,
                  backgroundColor:
                      theme.colorScheme.primary.withValues(alpha: 0.1),
                  color: theme.colorScheme.primary,
                  borderRadius:
                      BorderRadius.circular(SpacingTokens.radiusSmall),
                );
                return Column(
                  children: [
                    progress,
                    const SizedBox(height: SpacingTokens.md),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, area) => SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(minHeight: area.maxHeight),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                question,
                                if (_judgement == null &&
                                    problem.mode != ProblemMode.compare)
                                  _buildAnswerInput(context),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
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

    return ColoredCard(
      color: judgement.isCorrect
          ? theme.semantic.success
          : theme.colorScheme.tertiary,
      width: double.infinity,
      padding: const EdgeInsets.all(SpacingTokens.md),
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
                            // 圆形底恒为 `primary`（见上方 decoration），
                            // 四主题的 onPrimary 均显式固定为白，等价替换。
                            color: theme.colorScheme.onPrimary,
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
                            if (judgement.correctSteps[i].resultHint.isNotEmpty)
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

  /// AppBar 的 AI 解析入口：宽屏图标+文字，窄屏仅图标（参考口算页顶部导航）。
  /// 只做讲解展示，不参与判分/错题/统计；未判分时不显示。
  Widget _buildAiExplainAction(BuildContext context) {
    final problem = ref.read(currentProblemProvider);
    final judgement = _judgement;
    if (problem == null || judgement == null) return const SizedBox.shrink();
    final isWide = MediaQuery.sizeOf(context).width >= 420;
    void open() => showMathAiExplainSheet(
          context,
          problemText: problem.problemText,
          correctAnswer: problem.answerText,
          userAnswer: judgement.isCorrect ? null : _userAnswerOfCurrent(),
          diagnosisCategory: judgement.diagnosis?.category,
        );
    return isWide
        ? TextButton.icon(
            onPressed: open,
            icon: const Icon(Icons.auto_awesome_outlined, size: 18),
            label: const Text('AI 帮我讲'),
          )
        : IconButton(
            onPressed: open,
            // 与宽屏按钮同尺寸（18）：默认 24 的实心图标在仅图标态下偏大。
            icon: const Icon(Icons.auto_awesome_outlined, size: 18),
            tooltip: 'AI 帮我讲',
          );
  }

  /// 回查当前题的作答（只读，不改动记录链路）。
  ///
  /// 按**题目索引**定位，不用题干文本匹配：`_problemRecords` 与
  /// `mathProblemsProvider` 同序（每题作答时 `add` 一条），索引即权威关联。
  /// 文本匹配在题干重复时会命中错误的旧记录（如连出两道同形题，
  /// 第二次作答前显示的是第一次的答案）。
  String? _userAnswerOfCurrent() {
    final index = ref.read(mathCurrentIndexProvider);
    if (index < 0 || index >= _problemRecords.length) return null;
    return _problemRecords[index].userAnswer;
  }

  Widget _buildAnswerControls(BuildContext context) {
    if (_judgement != null) {
      // 已作答，显示"下一题"按钮
      return SafeArea(
        top: false,
        minimum: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.md,
          vertical: SpacingTokens.sm,
        ),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _submitting || _isFinishing ? null : _nextProblem,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(
              ref.read(mathCurrentIndexProvider) + 1 >=
                      ref.read(mathProblemsProvider).length
                  ? '查看成绩'
                  : '下一题',
            ),
          ),
        ).animate().fadeIn(duration: 250.ms).slideY(
              begin: 0.2,
              end: 0,
              duration: 250.ms,
              curve: Curves.easeOutCubic,
            ),
      );
    }

    // 比大小模式：显示 > < = 三个按钮
    final problem = ref.watch(currentProblemProvider);
    if (problem?.mode == ProblemMode.compare) {
      return SafeArea(
        top: false,
        minimum: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.md,
          vertical: SpacingTokens.sm,
        ),
        child: _buildCompareButtons(context),
      );
    }

    final process = problem != null && VerticalAttempt.supports(problem);
    return NumberKeypad(
      onNumberTap: (digit) {
        setState(() {
          if (process) {
            if (RegExp(r'^\d$').hasMatch(digit)) {
              _verticalAttempt =
                  _verticalAttempt.withField(_verticalField, digit);
              _queueDraftSave();
            }
            return;
          }
          if (NumberKeypad.canAppend(_answerController.text, digit)) {
            _answerController.text += digit;
          }
        });
      },
      onBackspace: () {
        setState(() {
          if (process) {
            _verticalAttempt = _verticalAttempt.withField(_verticalField, '');
            _queueDraftSave();
            return;
          }
          if (_answerController.text.isNotEmpty) {
            _answerController.text = _answerController.text.substring(
              0,
              _answerController.text.length - 1,
            );
          }
        });
      },
      onSubmit: _submitAnswer,
      submitEnabled: !_submitting &&
          (process
              ? _verticalAttempt.complete(problem)
              : _answerController.text.isNotEmpty),
      showDecimal: problem?.resultForm == ResultForm.decimal,
      showEllipsis: problem?.resultForm == ResultForm.withRemainder,
      showSlash: problem?.resultForm == ResultForm.fraction,
      showNegative: problem?.result.isNegative ?? false,
    );
  }

  /// 作答内容位于可滚动题目区，数字键盘独立固定在页面底部。
  Widget _buildAnswerInput(BuildContext context) {
    final problem = ref.watch(currentProblemProvider);
    // 余数模式：显示商…余格式提示
    final isRemainder = problem?.resultForm == ResultForm.withRemainder;

    // 数字键盘独立固定在底部，此处仅展示当前输入。
    final theme = Theme.of(context);
    final process = problem != null && VerticalAttempt.supports(problem);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (process)
          VerticalProcessInput(
            problem: problem,
            attempt: _verticalAttempt,
            selectedField: _verticalField,
            onSelect: (field) => setState(() => _verticalField = field),
          )
        else
          ColoredCard(
            color: theme.colorScheme.primary,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.md,
              vertical: SpacingTokens.lg,
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
        if (problem?.mode == ProblemMode.vertical && !process)
          Padding(
            padding: const EdgeInsets.only(top: SpacingTokens.xs),
            child: Text(
              '本题为结果练习；两位数加减法支持逐列过程练习。',
              style: theme.textTheme.bodySmall,
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
