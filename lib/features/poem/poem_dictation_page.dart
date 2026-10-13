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

/// 中文标点集合（不作为听写目标），口径与背诵页一致。
const _punctuation = {
  '，', '。', '！', '？', '、', '；', '：', '“', '”', '‘', '’',
  '（', '）', '《', '》', '【', '】', '…', '—', '　',
  ',', '.', '!', '?', ':', ';', '"', "'", '(', ')', ' ',
};

bool _isPunctuation(String ch) => _punctuation.contains(ch);

/// 候选字不够时的兜底字池（与背诵页同款）。
const _fallbackPool = [
  '山', '水', '风', '月', '花', '云', '雨', '春', '秋', '雪',
  '天', '地', '日', '夜', '人', '心', '梦', '鸟', '树', '石',
];

/// 及格线：与 QuizSession.isPassed 同口径。
const double _kPassLine = 0.8;

class PoemDictationPage extends ConsumerStatefulWidget {
  const PoemDictationPage({super.key, required this.poemId});

  final String poemId;

  @override
  ConsumerState<PoemDictationPage> createState() =>
      _PoemDictationPageState();
}

class _PoemDictationPageState extends ConsumerState<PoemDictationPage> {
  // ── 诗句数据 ──
  List<String> _lines = [];
  final List<bool> _lineResults = [];

  // ── 关卡状态 ──
  int _currentLineIndex = 0;
  bool _isComplete = false;
  bool _allowResultPop = false;

  // ── 输入模式 ──
  bool _useTyping = false;
  final _typeController = TextEditingController();

  // ── 点选模式 ──
  List<_CandidateTile> _candidates = [];
  List<String> _filled = [];
  bool _judging = false; // 本句已判定，等待推进的反馈期

  // ── TTS ──
  late final TtsService _tts;
  bool _isPreparing = false;
  bool _isSpeaking = false;
  int _activeSessionId = -1;

  bool _isCurrentSession(int sessionId) => sessionId == _activeSessionId;

  @override
  void initState() {
    super.initState();
    _tts = ref.read(ttsServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initPoem());
  }

  @override
  void dispose() {
    // 退出停播纪律：与 assistant / detail 页一致。
    unawaited(_tts.stop().onError((_, __) {}));
    _typeController.dispose();
    super.dispose();
  }

  void _initPoem() {
    // 侧信道纪律：进入时清空，防止上一次练习的陈旧分数被误消费。
    ref.read(lastPracticeScoreProvider.notifier).state = null;
    final poem = ref.read(poemByIdProvider(widget.poemId));
    if (poem == null) return;

    final lines = poem.content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    setState(() {
      _lines = lines;
      _lineResults.clear();
      _setupLine(0);
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

    setState(() {
      _currentLineIndex = index;
      _filled = [];
      _judging = false;
      _typeController.clear();
      _candidates = _generateCandidates(target);
    });
    // 进入新句自动朗读（听一句，写一句）。
    unawaited(_speakLine(index));
  }

  /// 候选字池：本句全部字（含重复）+ 干扰字，凑满 12 个（句长更长则全用）。
  List<_CandidateTile> _generateCandidates(List<String> target) {
    final tiles = target.map((ch) => _CandidateTile(ch)).toList();

    final lineSet = target.toSet();
    final distractPool = <String>[
      ..._allPoemChars.where((ch) => !lineSet.contains(ch)),
      ..._fallbackPool.where((ch) => !lineSet.contains(ch)),
    ]..shuffle();

    final want = tiles.length >= 12 ? 0 : 12 - tiles.length;
    tiles.addAll(
      distractPool.take(want).map((ch) => _CandidateTile(ch)),
    );

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
    setState(() {
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
            setState(() => _isPreparing = false);
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
          setState(() {
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
    if (_filled.length >= target.length) return;    HapticFeedback.lightImpact();
    setState(() {
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
    setState(() {
      // 归还最近一个未用尽的同字候选格。
      for (final tile in _candidates.reversed) {
        if (tile.used && tile.char == removed) {
          tile.used = false;
          break;
        }
      }
    });
  }

  void _submitTyped() {
    if (_judging) return;
    final typed = _typeController.text;
    final typedChars =
        typed.characters.where((ch) => !_isPunctuation(ch)).toList();
    if (typedChars.isEmpty) return;
    _judgeCurrentLine(typedChars);
  }

  /// 逐句判定：去标点后逐字全对才计通过。
  void _judgeCurrentLine(List<String> answer) {
    final target = _targetCharsOf(_lines[_currentLineIndex]);
    final isCorrect =
        answer.length == target.length && _listEquals(answer, target);

    _lineResults.add(isCorrect);
    setState(() => _judging = true);

    // 反馈期后推进下一句；末句则出结果。
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
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

  void _onAllLinesComplete() {
    // 末句朗读已在句内完成，直接出结果。
    setState(() => _isComplete = true);
  }

  void _exitWithResult() {
    if (_allowResultPop) return;
    _allowResultPop = true;
    // 侧信道纪律：pop 前写入本次最终得分，复习页读取后自适应推进。
    final score = _score;
    ref.read(lastPracticeScoreProvider.notifier).state = score;
    final result = score >= _kPassLine
        ? PoemPracticeResult.quizPassed
        : PoemPracticeResult.quizFailed;
    Navigator.of(context).pop(result);
  }

  void _restart() {
    setState(() {
      _lineResults.clear();
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

    if (poem == null || _lines.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('诗词听写')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope<PoemPracticeResult>(
      canPop: !_isComplete || _allowResultPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isComplete) _exitWithResult();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('听写 · ${poem.title}'),
          actions: [
            // 再听一遍当前句
            IconButton(
              onPressed: () => unawaited(_speakLine(_currentLineIndex)),
              tooltip: '再听一遍',
              icon: const Icon(Icons.volume_up_outlined),
            ),
            // 点选 ⇄ 打字 模式切换
            Padding(
              padding: const EdgeInsets.only(right: SpacingTokens.sm),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.touch_app_outlined, size: 18),
                    label: Text('点选'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.keyboard_outlined, size: 18),
                    label: Text('打字'),
                  ),
                ],
                selected: {_useTyping},
                onSelectionChanged: _judging
                    ? null
                    : (selection) {
                        setState(() => _useTyping = selection.first);
                      },
                showSelectedIcon: false,
              ),
            ),
          ],
        ),
        body: SafeArea(
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
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
            ],
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
          const SizedBox(height: SpacingTokens.lg),

          // 朗读状态提示
          Row(
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

          const Spacer(),

          // 已填字格（两种模式共用展示；打字模式显示输入框）
          _useTyping ? _buildTypingInput(context) : _buildFilledSlots(context),

          const Spacer(),

          // 点选模式：候选字格
          if (!_useTyping) ...[
            _buildCandidateGrid(context),
            const SizedBox(height: SpacingTokens.sm),
            TextButton.icon(
              onPressed: _onBackspace,
              icon: const Icon(Icons.backspace_outlined, size: 18),
              label: const Text('退一格'),
            ),
          ],

          if (_useTyping)
            FilledButton.icon(
              onPressed: _submitTyped,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('确认本句'),
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
            margin: const EdgeInsets.symmetric(
              horizontal: 2,
              vertical: 4,
            ),
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
                    ? theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5)
                    : theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
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

  Widget _buildTypingInput(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _typeController,
      enabled: !_judging,
      maxLines: 1,
      textAlign: TextAlign.center,
      style: theme.textTheme.headlineSmall?.copyWith(
        letterSpacing: 4,
        fontFamilyFallback: TypographyTokens.serifFallback,
      ),
      decoration: InputDecoration(
        hintText: '听到什么，写什么…',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        ),
      ),
      onSubmitted: (_) => _submitTyped(),
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
        child: ColoredCard(
          color: passed ? theme.semantic.success : theme.semantic.caution,
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                passed ? Icons.emoji_events_rounded : Icons.refresh_rounded,
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

              // 逐句对错清单；错句附原文
              ..._lineResults.asMap().entries.map((entry) {
                final i = entry.key;
                final ok = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
                  child: Row(
                    children: [
                      Icon(
                        ok ? Icons.check_circle : Icons.cancel,
                        size: 18,
                        color: ok
                            ? theme.semantic.success
                            : theme.colorScheme.error,
                      ),
                      const SizedBox(width: SpacingTokens.sm),
                      Expanded(
                        child: Text(
                          '第 ${i + 1} 句${ok ? '' : '：${_lines[i]}'}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: ok
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: SpacingTokens.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _exitWithResult,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('完成'),
                    ),
                  ),
                  const SizedBox(width: SpacingTokens.md),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _restart,
                      icon: const Icon(Icons.replay),
                      label: const Text('再来一次'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        )
            .animate()
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
