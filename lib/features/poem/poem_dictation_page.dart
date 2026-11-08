// lib/features/poem/poem_dictation_page.dart
//
// 诗词听写页：TTS 逐句朗读 → 孩子逐句补写 → 逐句判定 → 结果页。
// 双输入模式：候选字点选（默认）⇄ 打字（系统输入法），右上角切换。
//
// 判定口径：逐句去标点后逐字全对计 1 句通过；
// 总得分 = 通过句数 / 总句数，≥0.8 → quizPassed（与 quiz 及格线同构）。
//
// 返回契约：pop 前把得分写入 lastPracticeScoreProvider 侧信道
// （复用 ④ 的机制），复习链路自适应推进零额外改动。
//
// TTS 竞态纪律：复用 poem_detail_page 的会话令牌护栏
// （_activeSessionId + currentSessionId 比对）+ _isPreparing 遮罩，
// dispose 停播。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/poem/poem_practice_result.dart';
import 'package:poemath/features/poem/poem_practice_score.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/domain/poem_practice_details.dart';
import 'package:poemath/domain/writing_stroke_data.dart';
import 'package:poemath/features/poem/poem_answer_difference.dart';
import 'package:poemath/features/poem/widgets/poem_practice_unavailable.dart';
import 'package:poemath/features/poem/widgets/poem_handwriting_pad.dart';
import 'package:poemath/features/poem/widgets/poem_sentence_writing_sheet.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/textbook/writing/stroke_data_provider.dart';
import 'package:poemath/features/poem/poem_practice_draft.dart';
import 'package:poemath/core/routing/app_routes.dart';

/// 中文标点集合（不作为听写目标），口径与背诵页一致。
const _punctuation = {
  '，',
  '。',
  '！',
  '？',
  '、',
  '；',
  '：',
  '“',
  '”',
  '‘',
  '’',
  '（',
  '）',
  '《',
  '》',
  '【',
  '】',
  '…',
  '—',
  '　',
  ',',
  '.',
  '!',
  '?',
  ':',
  ';',
  '"',
  "'",
  '(',
  ')',
  ' ',
};

bool _isPunctuation(String ch) => _punctuation.contains(ch);

/// 候选字不够时的兜底字池（与背诵页同款）。
const _fallbackPool = [
  '山',
  '水',
  '风',
  '月',
  '花',
  '云',
  '雨',
  '春',
  '秋',
  '雪',
  '天',
  '地',
  '日',
  '夜',
  '人',
  '心',
  '梦',
  '鸟',
  '树',
  '石',
];

/// 及格线：与 QuizSession.isPassed 同口径。
const double _kPassLine = 0.8;

class PoemDictationPage extends ConsumerStatefulWidget {
  const PoemDictationPage({
    super.key,
    required this.poemId,
    this.targetLineIndices,
  });

  final List<int>? targetLineIndices;

  final String poemId;

  @override
  ConsumerState<PoemDictationPage> createState() => _PoemDictationPageState();
}

class _PoemDictationPageState extends ConsumerState<PoemDictationPage> {
  late final _learningWrites = ref.read(
    poemPracticeDraftRepositoryFactoryProvider,
  )();
  // ── 诗句数据 ──
  List<String> _lines = [];
  final List<bool> _lineResults = [];
  List<int> _sourceIndices = [];
  final List<PoemLineResult> _snapshots = [];
  String? _detailsJson;
  bool get _targeted => widget.targetLineIndices != null;

  // ── 关卡状态 ──
  int _currentLineIndex = 0;
  bool _isComplete = false;
  bool _allowResultPop = false;
  late String _activityId = _newActivityId();
  DateTime? _completedAt;
  bool _settling = false;
  bool _settled = false;
  bool _progressRecorded = false;
  String? _settlementError;

  String _newActivityId() =>
      'poem_dictation:${widget.poemId}:${DateTime.now().microsecondsSinceEpoch}';

  // ── 输入模式 ──
  bool _useTyping = false;

  // ── 手写默写 ──
  /// 当前待手写字 → 笔顺数据（null = 无数据降级自由书写）。
  CharacterStrokeData? _handwriteStrokeData;
  bool _handwriteLoading = false;
  int _handwriteLoadId = 0;

  // ── 点选模式 ──
  List<_CandidateTile> _candidates = [];
  List<String> _filled = [];
  bool _judging = false; // 本句已判定，等待推进的反馈期

  // ── TTS ──
  late final TtsService _tts;
  bool _isPreparing = false;
  bool _initialized = false;
  bool _isSpeaking = false;
  int _activeSessionId = -1;

  bool _isCurrentSession(int sessionId) => sessionId == _activeSessionId;
  PoemPracticeDraft? _draft;
  bool _draftOpening = true;
  int? _settledDuration;
  PoemHandwrittenChar? _pendingInk;

  void _update(VoidCallback action) {
    setState(action);
    _draft?.changed();
  }

  Map<String, dynamic> _captureDraft() => {
    'activityId': _activityId,
    'line': _currentLineIndex,
    'results': _lineResults,
    'filled': _filled,
    'judging': _judging,
    'candidates': [
      for (final c in _candidates) {'char': c.char, 'used': c.used},
    ],
    'handwrite': _useTyping,
    'handwritten': _handwritten.map((c) => c.toJson()).toList(),
    'pendingInk': _pendingInk?.toJson(),
    'snapshots': _snapshots.map((s) => s.toJson()).toList(),
    'completedAt': _completedAt?.toIso8601String(),
    'duration': _settledDuration,
    'details': _detailsJson,
  };

  void _restoreDraft(Map<String, dynamic> data) {
    final line = data['line'] as int;
    final results = (data['results'] as List).cast<bool>();
    final filled = (data['filled'] as List).cast<String>();
    final judging = data['judging'] as bool;
    final candidates = (data['candidates'] as List).map((value) {
      final c = value as Map<String, dynamic>;
      return _CandidateTile(c['char'] as String)..used = c['used'] as bool;
    }).toList();
    final handwritten = (data['handwritten'] as List)
        .map((c) => PoemHandwrittenChar.fromJson(c as Map<String, dynamic>))
        .toList();
    final pending = data['pendingInk'] == null
        ? null
        : PoemHandwrittenChar.fromJson(
            data['pendingInk'] as Map<String, dynamic>,
          );
    final snapshots = (data['snapshots'] as List)
        .map((s) => PoemLineResult.fromJson(s as Map<String, dynamic>))
        .toList();
    final completedAt = data['completedAt'] == null
        ? null
        : DateTime.parse(data['completedAt'] as String);
    final duration = data['duration'] as int?;
    final details = data['details'] as String?;
    final id = data['activityId'] as String;
    final typing = data['handwrite'] as bool;
    if (line < 0 ||
        line >= _lines.length ||
        results.length > _lines.length ||
        snapshots.length != results.length ||
        filled.length > _targetCharsOf(_lines[line]).length ||
        handwritten.length > _targetCharsOf(_lines[line]).length ||
        snapshots.any((s) => !_sourceIndices.contains(s.lineIndex))) {
      throw const FormatException('听写草稿进度不完整');
    }
    _currentLineIndex = line;
    _lineResults
      ..clear()
      ..addAll(results);
    _filled = filled;
    _judging = judging;
    _candidates = candidates;
    _useTyping = typing;
    _handwritten
      ..clear()
      ..addAll(handwritten);
    _pendingInk = pending;
    _snapshots
      ..clear()
      ..addAll(snapshots);
    _completedAt = completedAt;
    _settledDuration = duration;
    _detailsJson = details;
    _activityId = id;
  }

  Future<void> _openPractice() async {
    if (!mounted) return;
    _initPoem(prepareOnly: true);
    final poem = ref.read(poemByIdProvider(widget.poemId));
    if (poem == null || _lines.isEmpty) return;
    final variant = widget.targetLineIndices == null
        ? 'all'
        : _sourceIndices.join(',');
    final route = Uri(
      path: AppRoutes.poemDictationOf(widget.poemId),
      queryParameters: widget.targetLineIndices == null
          ? null
          : {'lines': variant},
    ).toString();
    final draft = _draft = PoemPracticeDraft(
      identity: PoemDraftIdentity(
        kind: 'poemDictation',
        poem: poem,
        variant: variant,
        label: _targeted ? '错句听写' : '听写练习',
        route: route,
      ),
      capture: _captureDraft,
      repository: _learningWrites,
    );
    final opened = await draft.open(context, _restoreDraft);
    if (!mounted) return;
    if (!opened) {
      Navigator.of(context).pop();
      return;
    }
    _update(() => _draftOpening = false);
    if (!draft.restored) {
      _setupLine(0);
      return;
    }
    if (_completedAt != null) {
      unawaited(_onAllLinesComplete());
      return;
    }
    if (_judging) {
      _setupLine(_currentLineIndex + 1);
      return;
    }
    if (_useTyping) {
      final target = _targetCharsOf(_lines[_currentLineIndex]);
      if (_handwritten.length < target.length) {
        unawaited(_loadHandwriteStrokeData(target[_handwritten.length]));
      }
    }
    // 恢复时不自动播放，孩子可点击朗读重新听当前句。
  }

  @override
  void initState() {
    super.initState();
    _tts = ref.read(ttsServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPractice());
  }

  @override
  void dispose() {
    _draft?.dispose();
    // 退出停播纪律：与 assistant / detail 页一致。
    unawaited(_tts.stop().onError((_, __) {}));
    super.dispose();
  }

  void _initPoem({bool prepareOnly = false}) {
    if (!mounted) return;
    // 侧信道纪律：进入时清空，防止上一次练习的陈旧分数被误消费。
    ref.read(lastPracticeScoreProvider.notifier).state = null;
    final poem = ref.read(poemByIdProvider(widget.poemId));
    if (poem == null) {
      _update(() => _initialized = true);
      return;
    }

    final allLines = poemPracticeLines(poem.content);
    _sourceIndices = [
      for (var i = 0; i < allLines.length; i++)
        if (widget.targetLineIndices == null ||
            widget.targetLineIndices!.contains(i))
          i,
    ];
    final lines = _sourceIndices.map((i) => allLines[i]).toList();

    _update(() {
      _initialized = true;
      _lines = lines;
      _lineResults.clear();
      if (lines.isNotEmpty && !prepareOnly) _setupLine(0);
    });
  }

  /// 当前句的非标点目标字（判定与点选填充都以它为基准）。
  List<String> _targetCharsOf(String line) {
    return line.characters.where((ch) => !_isPunctuation(ch)).toList();
  }

  void _setupLine(int index) {
    if (index >= _lines.length) {
      _onAllLinesComplete();
      return;
    }

    final target = _targetCharsOf(_lines[index]);
    if (target.isEmpty) {
      // 纯标点行不作为听写目标，直接跳过。
      _setupLine(index + 1);
      return;
    }

    _update(() {
      _currentLineIndex = index;
      _filled = [];
      _judging = false;
      _handwritten.clear();
      _pendingInk = null;
      _handwriteStrokeData = null;
      _candidates = _generateCandidates(target);
    });
    if (_useTyping) {
      // 手写默写：预载首字笔顺（逐字换新时再取下一个）。
      unawaited(_loadHandwriteStrokeData(target.first));
    }
    // 进入新句自动朗读（听一句，写一句）。
    unawaited(_speakLine(index));
  }

  /// 加载手写目标字的笔顺数据；无数据（未收录）时保持 null 走降级路径。
  Future<void> _loadHandwriteStrokeData(String character) async {
    final loadId = ++_handwriteLoadId;
    _update(() => _handwriteLoading = true);
    try {
      final asset = await ref.read(writingStrokeDataProvider.future);
      if (!mounted || loadId != _handwriteLoadId) return;
      _update(() {
        _handwriteStrokeData = asset[character];
        _handwriteLoading = false;
      });
    } on Object {
      if (!mounted || loadId != _handwriteLoadId) return;
      _update(() {
        // 资产加载失败：本句降级自由书写（与无数据同路径）。
        _handwriteStrokeData = null;
        _handwriteLoading = false;
      });
    }
  }

  /// 手写板确认一个字：填入作答序列；满句即走既有判定。
  void _onHandwriteCharConfirmed(PoemHandwrittenChar result) {
    if (_judging) return;
    HapticFeedback.lightImpact();
    _pendingInk = null;
    _handwritten.add(result);
    final target = _targetCharsOf(_lines[_currentLineIndex]);
    if (_handwritten.length >= target.length) {
      // 整句写满：按笔迹序拼出作答走既有判定（对/错由判定给出）。
      _judgeCurrentLine([for (final c in _handwritten) c.character]);
      return;
    }
    // 预载下一个待手写字的笔顺。
    unawaited(_loadHandwriteStrokeData(target[_handwritten.length]));
    _update(() {});
  }

  /// 当前句已确认的笔迹（句级格位行展示）。
  final List<PoemHandwrittenChar> _handwritten = [];

  /// 候选字池：本句全部字（含重复）+ 干扰字，凑满 12 个（句长更长则全用）。
  List<_CandidateTile> _generateCandidates(List<String> target) {
    final tiles = target.map((ch) => _CandidateTile(ch)).toList();

    final lineSet = target.toSet();
    final distractPool = <String>[
      ..._allPoemChars.where((ch) => !lineSet.contains(ch)),
      ..._fallbackPool.where((ch) => !lineSet.contains(ch)),
    ]..shuffle();

    final want = tiles.length >= 12 ? 0 : 12 - tiles.length;
    tiles.addAll(distractPool.take(want).map((ch) => _CandidateTile(ch)));

    tiles.shuffle();
    return tiles;
  }

  List<String> get _allPoemChars {
    final pool = <String>{};
    for (final line in _lines) {
      for (final ch in line.characters) {
        if (!_isPunctuation(ch)) pool.add(ch);
      }
    }
    return pool.toList();
  }

  // ─────────────────────────────────────────────────────────────
  // TTS：会话令牌护栏（口径同 poem_detail_page）
  // ─────────────────────────────────────────────────────────────

  Future<void> _speakLine(int index) async {
    final scaffold = ScaffoldMessenger.of(context);
    _update(() {
      _isPreparing = true;
      _isSpeaking = true;
    });
    // Future.sync：发起时同步抛错归一为 Future 失败，
    // 保证「捕获会话 id」一定先于异常被观察到（遮罩不卡死）。
    final speaking = Future.sync(() {
      return _tts.speakLines(
        [_lines[index]],
        onReady: (sessionId) {
          if (mounted && _isCurrentSession(sessionId)) {
            _update(() => _isPreparing = false);
          }
        },
      );
    });
    final sessionId = _tts.currentSessionId;
    _activeSessionId = sessionId;
    try {
      await speaking;
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '听写朗读失败',
        tag: 'PoemDictation',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted && _isCurrentSession(sessionId)) {
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          SnackBar(
            content: Text(
              error is TtsException
                  ? '朗读失败：${error.message}'
                  : '朗读失败，请检查系统语音服务后重试',
            ),
          ),
        );
      }
    } finally {
      // 兜底清理：过期会话（已被 stop/新会话接管）不复位新会话状态。
      if (_isCurrentSession(sessionId)) {
        _activeSessionId = -1;
        if (mounted) {
          _update(() {
            _isPreparing = false;
            _isSpeaking = false;
          });
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 判定与推进
  // ─────────────────────────────────────────────────────────────

  void _onCandidateTap(_CandidateTile tile) {
    if (_judging || tile.used) return;
    final target = _targetCharsOf(_lines[_currentLineIndex]);
    if (_filled.length >= target.length) return;
    HapticFeedback.lightImpact();
    _update(() {
      tile.used = true;
      _filled.add(tile.char);
    });

    if (_filled.length == target.length) {
      _judgeCurrentLine(_filled);
    }
  }

  void _onBackspace() {
    if (_judging || _filled.isEmpty) return;
    final removed = _filled.removeLast();
    _update(() {
      // 归还最近一个未用尽的同字候选格。
      for (final tile in _candidates.reversed) {
        if (tile.used && tile.char == removed) {
          tile.used = false;
          break;
        }
      }
    });
  }

  /// 逐句判定：去标点后逐字全对才计通过。
  void _judgeCurrentLine(List<String> answer) {
    final target = _targetCharsOf(_lines[_currentLineIndex]);
    final isCorrect =
        answer.length == target.length && _listEquals(answer, target);

    _snapshots.add(
      PoemLineResult(
        lineIndex: _sourceIndices[_currentLineIndex],
        lineText: _lines[_currentLineIndex],
        expected: target.join(),
        answer: answer.join(),
        passed: isCorrect,
      ),
    );
    _lineResults.add(isCorrect);
    _update(() => _judging = true);

    // 反馈期后推进下一句；末句则出结果。
    final activityId = _activityId;
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted || activityId != _activityId) return;
      _setupLine(_currentLineIndex + 1);
    });
  }

  static bool _listEquals(List<String> a, List<String> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  double get _score {
    if (_lineResults.isEmpty) return 0.0;
    final passed = _lineResults.where((r) => r).length;
    return passed / _lineResults.length;
  }

  Future<void> _onAllLinesComplete() async {
    if (_settling || _settled) return;
    _settling = true;
    _settlementError = null;
    _update(() => _isComplete = true);
    final completedAt = _completedAt ??= DateTime.now();
    _draft?.clock.finish();
    final duration = _settledDuration ??= _draft!.clock.elapsedSeconds;
    final activityId = _activityId;
    final total = _lineResults.length;
    final successful = _lineResults.where((r) => r).length;
    final stars = _targeted
        ? 0
        : LearningRewardCalculator.calculateStars(
            activityType: LearningActivityType.poemDictation,
            totalItems: total,
            successfulItems: successful,
          );
    final detailsJson = _detailsJson ??= PoemPracticeDetails(
      mode: 'dictation',
      targeted: _targeted,
      score: _score,
      lines: List.of(_snapshots),
    ).encode();
    final progress = ref.read(poemProgressRepoProvider);
    final stats = ref.read(userStatsRepoProvider);
    final activities = ref.read(learningActivityRepositoryProvider);
    final checkIn = ref.read(checkInRepoProvider);
    try {
      await _draft!.saveOrThrow();
      await _learningWrites.guard(() async {
        if (!_progressRecorded) {
          _draft!.assertCurrent();
          await progress.recordStudy(
            widget.poemId,
            activityId: activityId,
            completedAt: completedAt,
          );
          _progressRecorded = true;
        }
        _draft!.assertCurrent();
        await stats.updatePoemStats(learned: progress.learnedCount);
        _draft!.assertCurrent();
        await activities.record(
          id: activityId,
          activityType: LearningActivityType.poemDictation,
          totalItems: total,
          successfulItems: successful,
          poemId: widget.poemId,
          starsEarned: stars,
          durationSeconds: duration,
          completedAt: completedAt,
          detailsJson: detailsJson,
        );
        if (stars > 0) await stats.addStars(stars, activityId: activityId);
        _draft!.assertCurrent();
        await checkIn.updateForDate(
          completedAt,
          activityId: activityId,
          addPoems: 1,
          addStars: stars,
          addDuration: duration,
        );
      });
      await _draft!.complete(activityId);
      _settled = true;
      if (mounted) unawaited(ref.read(soundServiceProvider).playCompletion());
    } on Object catch (error, stack) {
      AppLogger.e(
        '听写结算失败',
        tag: 'PoemDictation',
        error: error,
        stackTrace: stack,
      );
      _settlementError = '学习记录保存失败，请重试';
    } finally {
      _settling = false;
      if (mounted) {
        ref.invalidate(poemProgressProvider(widget.poemId));
        ref.invalidate(filteredPoemsProvider);
        ref.invalidate(learnedCountProvider);
        ref.invalidate(userStatsProvider);
        ref.invalidate(todayPoemCountProvider);
        ref.invalidate(todayCheckInProvider);
        _update(() {});
      }
    }
  }

  void _exitWithResult() {
    if (_allowResultPop || !_settled) return;
    _allowResultPop = true;
    // 侧信道纪律：pop 前写入本次最终得分，复习页读取后自适应推进。
    final score = _score;
    if (_targeted) {
      ref.read(lastPracticeScoreProvider.notifier).state = null;
      Navigator.of(context).pop(PoemPracticeResult.targetedPracticeCompleted);
      return;
    }
    ref.read(lastPracticeScoreProvider.notifier).state = score;
    final result = score >= _kPassLine
        ? PoemPracticeResult.quizPassed
        : PoemPracticeResult.quizFailed;
    Navigator.of(context).pop(result);
  }

  void _restart() {
    if (!_settled) return;
    _update(() {
      _settledDuration = null;
      _draft?.restart();
      _activityId = _newActivityId();
      _completedAt = null;
      _settled = false;
      _progressRecorded = false;
      _settlementError = null;
      _lineResults.clear();
      _snapshots.clear();
      _detailsJson = null;
      _isComplete = false;
      _allowResultPop = false;
      _setupLine(0);
    });
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final poem = ref.watch(poemByIdProvider(widget.poemId));
    final theme = Theme.of(context);

    if (poem == null || (_initialized && _lines.isEmpty)) {
      return PoemPracticeUnavailable(title: '诗词听写', missing: poem == null);
    }
    if (_draftOpening || _lines.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('诗词听写')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope<PoemPracticeResult>(
      canPop: _allowResultPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isComplete && _settled) {
          _exitWithResult();
        } else {
          unawaited(_draft?.exit(context));
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('听写 · ${poem.title}'),
          // 点选 ⇄ 默写 模式切换：导航栏正下方（AppBar.bottom）。
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SpacingTokens.md,
                0,
                SpacingTokens.md,
                SpacingTokens.sm,
              ),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.touch_app_outlined, size: 18),
                    label: Text('点选'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.draw_outlined, size: 18),
                    label: Text('默写'),
                  ),
                ],
                selected: {_useTyping},
                onSelectionChanged: _judging
                    ? null
                    : (selection) {
                        final next = selection.first;
                        _update(() {
                          _useTyping = next;
                          _filled = [];
                          _handwriteStrokeData = null;
                        });
                        if (next) {
                          final target = _targetCharsOf(
                            _lines[_currentLineIndex],
                          );
                          if (target.isNotEmpty) {
                            unawaited(_loadHandwriteStrokeData(target.first));
                          }
                        }
                      },
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
            ),
          ),
        ),
        body: PoemDraftSaveStatus(
          draft: _draft,
          child: SafeArea(
            child: Stack(
              children: [
                _isComplete ? _buildResultCard(context) : _buildBody(context),
                // 准备期遮罩：合成期间挡住重入（TTS 竞态纪律）。
                if (_isPreparing)
                  Positioned.fill(
                    child: ColoredCard(
                      color: theme.colorScheme.surface,
                      backgroundOpacity: 0.6,
                      padding: EdgeInsets.zero,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.md),
      child: Column(
        children: [
          _buildProgressBar(context),
          const SizedBox(height: SpacingTokens.md),

          // 朗读状态提示（点击重听当前句；准备期禁用避免重入）
          InkWell(
            onTap: _isPreparing
                ? null
                : () => unawaited(_speakLine(_currentLineIndex)),
            borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.sm,
                vertical: SpacingTokens.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isSpeaking ? Icons.graphic_eq : Icons.hearing_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: SpacingTokens.xs),
                  Text(
                    _isSpeaking ? '正在朗读…' : '听写第 ${_currentLineIndex + 1} 句',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 点选模式：已填字格 + 候选字格（上下留白居中）。
          if (!_useTyping) ...[
            const Spacer(),
            _buildFilledSlots(context),
            const Spacer(),
            _buildCandidateGrid(context),
            const SizedBox(height: SpacingTokens.sm),
            TextButton.icon(
              onPressed: _onBackspace,
              icon: const Icon(Icons.backspace_outlined, size: 18),
              label: const Text('退一格'),
            ),
          ],

          // 手写默写模式：整句格位行 + 书写板紧跟状态行（听一句写一句）。
          if (_useTyping)
            Expanded(
              child: _handwriteLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.only(top: SpacingTokens.sm),
                      child: PoemSentenceWritingSheet(
                        key: ValueKey(
                          'dictation-sheet-$_activityId-$_currentLineIndex',
                        ),
                        pendingInk: _pendingInk,
                        onInkChanged: (ink) {
                          _pendingInk = ink;
                          _draft?.changed();
                        },
                        targetChars: _targetCharsOf(_lines[_currentLineIndex]),
                        confirmedChars: _handwritten,
                        currentStrokeData: _handwriteStrokeData,
                        onCharConfirmed: _onHandwriteCharConfirmed,
                        maxBoardSide: 240,
                      ),
                    ),
            ),

          const SizedBox(height: SpacingTokens.md),
        ],
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context) {
    final theme = Theme.of(context);
    final done = _lineResults.length;
    final progress = _lines.isEmpty ? 0.0 : done / _lines.length;
    return Row(
      children: [
        Text(
          '$done/${_lines.length}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SpacingTokens.radiusPill),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
            ),
          ),
        ),
      ],
    );
  }

  /// 点选模式的已填字格：对错配色（判定后立即反馈）。
  Widget _buildFilledSlots(BuildContext context) {
    final theme = Theme.of(context);
    final target = _targetCharsOf(_lines[_currentLineIndex]);

    return AutoFitLine(
      child: Wrap(
        alignment: WrapAlignment.center,
        children: List.generate(target.length, (i) {
          final filled = i < _filled.length;
          final char = filled ? _filled[i] : '';
          final isCorrect = _judging && filled && char == target[i];

          return Container(
            width: 40,
            height: 48,
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: _judging
                      ? (isCorrect
                            ? theme.semantic.success
                            : theme.colorScheme.error)
                      : theme.colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              char,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: _judging
                    ? (isCorrect
                          ? theme.semantic.success
                          : theme.colorScheme.error)
                    : theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                fontFamilyFallback: TypographyTokens.serifFallback,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCandidateGrid(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: SpacingTokens.sm,
      runSpacing: SpacingTokens.sm,
      alignment: WrapAlignment.center,
      children: _candidates.asMap().entries.map((entry) {
        final i = entry.key;
        final tile = entry.value;

        return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _onCandidateTap(tile),
                borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
                child: AnimatedContainer(
                  duration: 200.ms,
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: tile.used
                        ? theme.colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.5,
                          )
                        : theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.5,
                          ),
                    borderRadius: BorderRadius.circular(
                      SpacingTokens.radiusMedium,
                    ),
                    border: Border.all(
                      color: tile.used
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.08)
                          : theme.colorScheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    tile.char,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: tile.used
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.25)
                          : null,
                    ),
                  ),
                ),
              ),
            )
            .animate()
            .scale(
              begin: const Offset(0, 0),
              end: const Offset(1, 1),
              delay: (60 * i).ms,
              duration: 300.ms,
              curve: Curves.easeOutBack,
            )
            .fadeIn(delay: (60 * i).ms, duration: 200.ms);
      }).toList(),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 结果卡片
  // ─────────────────────────────────────────────────────────────

  Widget _buildResultCard(BuildContext context) {
    final theme = Theme.of(context);
    final score = _score;
    final passed = score >= _kPassLine;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child:
            ColoredCard(
                  color: passed
                      ? theme.semantic.success
                      : theme.semantic.caution,
                  width: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        passed
                            ? Icons.emoji_events_rounded
                            : Icons.refresh_rounded,
                        size: 56,
                        color: passed
                            ? theme.semantic.success
                            : theme.semantic.caution,
                      ),
                      const SizedBox(height: SpacingTokens.md),
                      Text(
                        passed ? '听写完成！' : '再听一遍，会更好！',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: passed
                              ? theme.semantic.success
                              : theme.semantic.caution,
                        ),
                      ),
                      const SizedBox(height: SpacingTokens.sm),
                      Text(
                        '总得分 ${(score * 100).round()}%'
                        '（${_lineResults.where((r) => r).length}/${_lineResults.length} 句）',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: SpacingTokens.md),
                      if (_targeted)
                        const Text('错句专项完成，仅记录练习；全诗掌握和复习轮次保持原值，不发累计星星。'),
                      for (final snapshot in _snapshots)
                        Padding(
                          padding: const EdgeInsets.only(top: SpacingTokens.sm),
                          child: PoemAnswerDifference(
                            expected: snapshot.expected,
                            answer: snapshot.answer,
                          ),
                        ),
                      const SizedBox(height: SpacingTokens.lg),
                      if (_settlementError != null) ...[
                        Text(
                          _settlementError!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                        TextButton(
                          onPressed: _settling ? null : _onAllLinesComplete,
                          child: const Text('重试保存'),
                        ),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _settled ? _exitWithResult : null,
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('完成'),
                            ),
                          ),
                          const SizedBox(width: SpacingTokens.md),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _settled ? _restart : null,
                              icon: const Icon(Icons.replay),
                              label: const Text('再来一次'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
                .animatePage(context)
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.1, end: 0, duration: 400.ms),
      ),
    );
  }
}

/// 候选字格：char + 使用标记（用尽置灰）。
class _CandidateTile {
  _CandidateTile(this.char);

  final String char;
  bool used = false;
}
