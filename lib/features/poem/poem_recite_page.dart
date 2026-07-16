// lib/features/poem/poem_recite_page.dart
//
// 背诵练习页：逐句选字闯关 + 默写模式。
// 动画基于 flutter_animate，撒花复用 ConfettiOverlay。

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/confetti_overlay.dart';
import 'package:poemath/core/widgets/celebration_dialog.dart';
import 'package:poemath/domain/achievement_check_helper.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

/// 背诵难度级别。
enum ReciteLevel {
  easy('简单', '每句填 1 字'),
  medium('中等', '每句填一半'),
  hard('困难', '每句全填'),
  dictation('默写', '键盘输入全文');

  const ReciteLevel(this.label, this.desc);
  final String label;
  final String desc;
}

// ─────────────────────────────────────────────────────────────────
// 中文标点集合（不作为填空目标）
// ─────────────────────────────────────────────────────────────────
const _punctuation = {
  '，', '。', '！', '？', '、', '；', '：',
  '“', '”',
  '‘', '’',
  '（', '）', '《', '》', '【', '】', '…', '—', '　',
  ',', '.', '!', '?', ':', ';', '"', "'", '(', ')', ' ',
};

bool _isPunctuation(String ch) => _punctuation.contains(ch);

/// 当诗中唯一字不够 6 个候选时的兜底字池。
const _fallbackPool = [
  '山', '水', '风', '月', '花', '云', '雨', '春', '秋', '雪',
  '天', '地', '日', '夜', '人', '心', '梦', '鸟', '树', '石',
];

class PoemRecitePage extends ConsumerStatefulWidget {
  const PoemRecitePage({super.key, required this.poemId});

  final String poemId;

  @override
  ConsumerState<PoemRecitePage> createState() => _PoemRecitePageState();
}

class _PoemRecitePageState extends ConsumerState<PoemRecitePage> {
  final _random = Random();
  final _celebrationCtrl = CelebrationController();
  final _dictController = TextEditingController();

  // ── 诗句数据 ──
  List<String> _lines = [];
  List<String> _pinyinLines = [];
  List<String> _allCharsPool = []; // 全诗去重非标点字符

  // ── 关卡状态 ──
  ReciteLevel _level = ReciteLevel.easy;
  int _currentLineIndex = 0;
  List<int> _blankPositions = [];
  int _currentBlankIdx = 0;
  Map<int, String> _filledChars = {};
  List<String> _candidates = [];
  bool _showHint = false;
  bool _hintUsedThisLine = false;
  int _wrongAttemptsThisLine = 0;

  // ── 动画触发 ──
  bool _shakeActive = false; // 选错抖动
  bool _correctFlash = false; // 选对闪光
  int _lineAnimKey = 0; // 换句时 +1 触发入场动画

  // ── 统计 ──
  int _totalStars = 0;
  int _linesCompleted = 0;
  bool _isComplete = false;
  final _startTime = DateTime.now();

  // ── 默写模式 ──
  bool _showDictDiff = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initPoem());
  }

  @override
  void dispose() {
    _celebrationCtrl.dispose();
    _dictController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // 初始化
  // ─────────────────────────────────────────────────────────────

  void _initPoem() {
    final poem = ref.read(poemByIdProvider(widget.poemId));
    if (poem == null) return;

    final lines = poem.content.split('\n').where((l) => l.isNotEmpty).toList();
    final pinyinLines = poem.pinyin.isNotEmpty
        ? poem.pinyin.split('\n')
        : List.filled(lines.length, '');

    // 收集全诗非标点字符（用于生成干扰项）
    final pool = <String>{};
    for (final line in lines) {
      for (final ch in line.characters) {
        if (!_isPunctuation(ch)) pool.add(ch);
      }
    }

    setState(() {
      _lines = lines;
      _pinyinLines = pinyinLines;
      _allCharsPool = pool.toList();
      _setupLine(0);
    });
  }

  void _setupLine(int index) {
    if (index >= _lines.length) {
      _onAllLinesComplete();
      return;
    }

    final chars = _lines[index].characters.toList();
    final blanks = _generateBlanks(chars);

    setState(() {
      _currentLineIndex = index;
      _blankPositions = blanks;
      _currentBlankIdx = 0;
      _filledChars = {};
      _showHint = false;
      _hintUsedThisLine = false;
      _wrongAttemptsThisLine = 0;
      _shakeActive = false;
      _correctFlash = false;
      _lineAnimKey++;

      if (blanks.isNotEmpty) {
        _candidates = _generateCandidates(chars[blanks[0]]);
      }
    });
  }

  // ─────────────────────────────────────────────────────────────
  // 填空生成
  // ─────────────────────────────────────────────────────────────

  List<int> _generateBlanks(List<String> chars) {
    final nonPunct = <int>[];
    for (var i = 0; i < chars.length; i++) {
      if (!_isPunctuation(chars[i])) nonPunct.add(i);
    }
    if (nonPunct.isEmpty) return [];

    switch (_level) {
      case ReciteLevel.easy:
        nonPunct.shuffle(_random);
        return [nonPunct.first];
      case ReciteLevel.medium:
        nonPunct.shuffle(_random);
        final count = (nonPunct.length / 2).ceil();
        return nonPunct.take(count).toList()..sort();
      case ReciteLevel.hard:
        return nonPunct;
      case ReciteLevel.dictation:
        return [];
    }
  }

  List<String> _generateCandidates(String correct) {
    final candidates = <String>{correct};
    final pool = List.of(_allCharsPool)..shuffle(_random);

    for (final ch in pool) {
      if (candidates.length >= 6) break;
      if (ch != correct) candidates.add(ch);
    }

    // 兜底
    final fallback = List.of(_fallbackPool)..shuffle(_random);
    for (final ch in fallback) {
      if (candidates.length >= 6) break;
      if (!candidates.contains(ch)) candidates.add(ch);
    }

    final result = candidates.toList()..shuffle(_random);
    return result;
  }

  // ─────────────────────────────────────────────────────────────
  // 交互事件
  // ─────────────────────────────────────────────────────────────

  void _onCandidateTap(String char) {
    if (_blankPositions.isEmpty || _currentBlankIdx >= _blankPositions.length) {
      return;
    }

    final blankPos = _blankPositions[_currentBlankIdx];
    final correctChar =
        _lines[_currentLineIndex].characters.toList()[blankPos];

    if (char == correctChar) {
      HapticFeedback.lightImpact();
      setState(() {
        _filledChars[blankPos] = char;
        _correctFlash = true;
      });

      // 短暂延迟后检查是否还有下一个空
      Future.delayed(350.ms, () {
        if (!mounted) return;
        setState(() => _correctFlash = false);

        if (_currentBlankIdx + 1 < _blankPositions.length) {
          // 下一个空
          setState(() {
            _currentBlankIdx++;
            _showHint = false;
            final nextBlankPos = _blankPositions[_currentBlankIdx];
            final nextCorrect =
                _lines[_currentLineIndex].characters.toList()[nextBlankPos];
            _candidates = _generateCandidates(nextCorrect);
          });
        } else {
          // 本句全部填完
          _onLineComplete();
        }
      });
    } else {
      // 选错
      HapticFeedback.mediumImpact();
      setState(() {
        _wrongAttemptsThisLine++;
        _shakeActive = true;
      });
      Future.delayed(400.ms, () {
        if (mounted) setState(() => _shakeActive = false);
      });
    }
  }

  void _onLineComplete() {
    // 计算本句星级
    int stars;
    if (_wrongAttemptsThisLine == 0 && !_hintUsedThisLine) {
      stars = 3;
    } else if (_wrongAttemptsThisLine <= 1 && !_hintUsedThisLine) {
      stars = 2;
    } else {
      stars = 1;
    }

    setState(() {
      _totalStars += stars;
      _linesCompleted++;
    });

    // 短暂高亮后进入下一句
    Future.delayed(800.ms, () {
      if (!mounted) return;
      _setupLine(_currentLineIndex + 1);
    });
  }

  void _toggleHint() {
    setState(() {
      _showHint = !_showHint;
      if (_showHint) _hintUsedThisLine = true;
    });
  }

  Future<void> _onAllLinesComplete() async {
    // 记录学习
    final progressRepo = ref.read(poemProgressRepoProvider);
    await progressRepo.recordStudy(widget.poemId);
    ref.invalidate(poemProgressProvider(widget.poemId));

    final statsRepo = ref.read(userStatsRepoProvider);
    await statsRepo.updatePoemStats(learned: progressRepo.learnedCount);

    // 记录星星到全局统计
    if (_totalStars > 0) {
      await statsRepo.addStars(_totalStars);
    }

    ref.invalidate(learnedCountProvider);
    ref.invalidate(userStatsProvider);
    ref.invalidate(todayPoemCountProvider);

    // 成就自动检查
    final newlyUnlocked = await checkAchievements(ref);
    ref.invalidate(unlockedAchievementsCountProvider);

    if (!mounted) return;

    // 成就解锁庆祝（撒花 + 弹窗，在背诵完成撒花之前展示）
    if (newlyUnlocked.isNotEmpty) {
      _celebrationCtrl.play();
      final names = newlyUnlocked.map((a) => a.title).join('、');
      showCelebration(
        context,
        type: CelebrationType.achievement,
        subtitle: names,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      if (!mounted) return;
    }

    _celebrationCtrl.play();
    setState(() => _isComplete = true);
  }

  void _restart() {
    setState(() {
      _totalStars = 0;
      _linesCompleted = 0;
      _isComplete = false;
      _showDictDiff = false;
      _dictController.clear();
      _setupLine(0);
    });
  }

  void _changeLevel(ReciteLevel level) {
    setState(() {
      _level = level;
      _totalStars = 0;
      _linesCompleted = 0;
      _isComplete = false;
      _showDictDiff = false;
      _dictController.clear();
      _setupLine(0);
    });
  }

  void _showLevelSheet(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: SpacingTokens.md),
                Text(
                  '选择难度',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: SpacingTokens.sm),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final l in ReciteLevel.values)
                        ListTile(
                          leading: Icon(
                            _levelIcon(l),
                            color: _level == l
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          title: Text(l.label),
                          subtitle: Text(l.desc),
                          selected: _level == l,
                          selectedColor: theme.colorScheme.primary,
                          onTap: () {
                            Navigator.pop(ctx);
                            _changeLevel(l);
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _levelIcon(ReciteLevel l) {
    return switch (l) {
      ReciteLevel.easy => Icons.sentiment_satisfied,
      ReciteLevel.medium => Icons.sentiment_neutral,
      ReciteLevel.hard => Icons.sentiment_dissatisfied,
      ReciteLevel.dictation => Icons.edit_note,
    };
  }

  // ─────────────────────────────────────────────────────────────
  // 默写模式：逐字比对
  // ─────────────────────────────────────────────────────────────

  Future<void> _submitDictation() async {
    setState(() => _showDictDiff = true);

    // 简单计分：正确字数 / 总字数
    final original = _lines.join('\n');
    final input = _dictController.text;
    final origChars = original.characters.toList();
    final inputChars = input.characters.toList();
    int correct = 0;
    for (var i = 0; i < origChars.length && i < inputChars.length; i++) {
      if (origChars[i] == inputChars[i]) correct++;
    }
    final accuracy = origChars.isEmpty ? 0.0 : correct / origChars.length;

    // 计算星级
    if (accuracy >= 0.95) {
      _totalStars = 3;
    } else if (accuracy >= 0.8) {
      _totalStars = 2;
    } else {
      _totalStars = 1;
    }

    await _onAllLinesComplete();
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
        appBar: AppBar(title: const Text('背诵练习')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(poem.title),
        actions: [
          InkWell(
            onTap: () => _showLevelSheet(context),
            borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_level.label, style: theme.textTheme.labelLarge),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: _isComplete
                ? _buildResultCard(context)
                : _level == ReciteLevel.dictation
                    ? _buildDictation(context)
                    : _buildCharSelect(context),
          ),
          ConfettiOverlay(controller: _celebrationCtrl),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 选字模式主体
  // ─────────────────────────────────────────────────────────────

  Widget _buildCharSelect(BuildContext context) {
    final theme = Theme.of(context);
    final lineChars = _lines[_currentLineIndex].characters.toList();
    final allFilled = _blankPositions.isNotEmpty &&
        _filledChars.length == _blankPositions.length;

    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.md),
      child: Column(
        children: [
          // ── 诗人信息 ──
          _buildAuthorInfo(context),
          const SizedBox(height: SpacingTokens.sm),

          // ── 进度条 ──
          _buildProgressBar(context),
          const SizedBox(height: SpacingTokens.lg),

          // ── 上一句（灰色回顾） ──
          if (_currentLineIndex > 0)
            Text(
              _lines[_currentLineIndex - 1],
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                letterSpacing: 2,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(duration: 300.ms),

          const Spacer(),

          // ── 当前句（含拼音提示） ──
          _buildCurrentLine(context, lineChars, allFilled),

          const Spacer(),

          // ── 候选字区 ──
          if (!allFilled) ...[
            _buildCandidateGrid(context),
            const SizedBox(height: SpacingTokens.md),

            // ── 提示按钮 ──
            TextButton.icon(
              onPressed: _toggleHint,
              icon: Icon(
                _showHint
                    ? Icons.lightbulb
                    : Icons.lightbulb_outline,
                size: 18,
              ),
              label: Text(_showHint ? '已显示提示' : '显示拼音提示'),
            ),
          ],

          if (allFilled)
            Text(
              '✓ 正确！',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            )
                .animate()
                .fadeIn(duration: 300.ms)
                .scale(
                  begin: const Offset(0.5, 0.5),
                  end: const Offset(1, 1),
                  duration: 300.ms,
                  curve: Curves.easeOutBack,
                ),

          const SizedBox(height: SpacingTokens.md),
        ],
      ),
    );
  }

  Widget _buildAuthorInfo(BuildContext context) {
    final poem = ref.read(poemByIdProvider(widget.poemId))!;
    final theme = Theme.of(context);
    return Text(
      '〔${poem.dynasty}〕${poem.author}',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _lines.isEmpty ? 0.0 : _linesCompleted / _lines.length;
    return Row(
      children: [
        Text(
          '${_currentLineIndex + 1}/${_lines.length}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SpacingTokens.radiusPill),
            child: AnimatedContainer(
              duration: 600.ms,
              curve: Curves.easeOutBack,
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
              ),
            ),
          ),
        ),
        const SizedBox(width: SpacingTokens.sm),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_rounded,
              size: 16,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(width: 2),
            Text(
              '$_totalStars',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCurrentLine(
    BuildContext context,
    List<String> lineChars,
    bool allFilled,
  ) {
    final theme = Theme.of(context);

    // 预加载拼音数据用于定位
    List<String> pinyinParts = [];
    if (_showHint && _currentLineIndex < _pinyinLines.length) {
      pinyinParts = _pinyinLines[_currentLineIndex].split(' ');
    }

    Widget lineWidget = Wrap(
      alignment: WrapAlignment.center,
      children: lineChars.asMap().entries.map((entry) {
        final i = entry.key;
        final char = entry.value;
        final isBlank = _blankPositions.contains(i);
        final isFilled = _filledChars.containsKey(i);
        final isActiveBlank = isBlank &&
            !isFilled &&
            _blankPositions.indexOf(i) == _currentBlankIdx;

        if (isBlank && !isFilled) {
          // 空白槽位
          Widget slot = _BlankSlot(
            isActive: isActiveBlank,
            shake: isActiveBlank && _shakeActive,
          );

          // 在活跃空白槽位上方显示拼音提示
          if (isActiveBlank && _showHint) {
            final pinyin =
                i < pinyinParts.length ? pinyinParts[i] : '';
            if (pinyin.isNotEmpty && !_isPunctuation(pinyin)) {
              slot = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pinyin,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.tertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 300.ms)
                      .slideY(
                        begin: 0.3,
                        end: 0,
                        duration: 300.ms,
                      ),
                  slot,
                ],
              );
            }
          }

          return slot;
        }

        final displayChar = isFilled ? _filledChars[i]! : char;
        final color = isFilled
            ? theme.colorScheme.primary
            : allFilled
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface;

        Widget charWidget = Text(
          displayChar,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: color,
            fontWeight:
                isFilled ? FontWeight.bold : FontWeight.normal,
            letterSpacing: 2,
            height: 2,
          ),
        );

        // 刚填入的字：缩放入场
        if (isFilled && _correctFlash) {
          charWidget = charWidget
              .animate()
              .scale(
                begin: const Offset(1.3, 1.3),
                end: const Offset(1, 1),
                duration: 300.ms,
                curve: Curves.easeOutBack,
              );
        }

        return charWidget;
      }).toList(),
    );

    // 整句完成时加光泽
    if (allFilled) {
      lineWidget = lineWidget.animate().shimmer(
            duration: 800.ms,
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          );
    }

    // 换句入场动画
    return KeyedSubtree(
      key: ValueKey(_lineAnimKey),
      child: lineWidget
          .animate()
          .fadeIn(duration: 400.ms)
          .slideX(begin: 0.15, end: 0, duration: 400.ms, curve: Curves.easeOut),
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
        final char = entry.value;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _onCandidateTap(char),
            borderRadius:
                BorderRadius.circular(SpacingTokens.radiusMedium),
            child: AnimatedContainer(
              duration: 200.ms,
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer
                    .withValues(alpha: 0.5),
                borderRadius:
                    BorderRadius.circular(SpacingTokens.radiusMedium),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                char,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
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
  // 默写模式
  // ─────────────────────────────────────────────────────────────

  Widget _buildDictation(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: Column(
        children: [
          _buildAuthorInfo(context),
          const SizedBox(height: SpacingTokens.md),
          Text(
            '请默写全文',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: SpacingTokens.md),
          Expanded(
            child: _showDictDiff
                ? _buildDiffResult(context)
                : TextField(
                    controller: _dictController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: InputDecoration(
                      hintText: '在此默写…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          SpacingTokens.radiusMedium,
                        ),
                      ),
                    ),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 2,
                      letterSpacing: 1,
                    ),
                  ),
          ),
          const SizedBox(height: SpacingTokens.md),
          if (!_showDictDiff)
            FilledButton.icon(
              onPressed: _dictController.text.trim().isEmpty
                  ? null
                  : _submitDictation,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('提交默写'),
            ),
        ],
      ),
    );
  }

  Widget _buildDiffResult(BuildContext context) {
    final theme = Theme.of(context);
    final original = _lines.join('\n');
    final input = _dictController.text;
    final origChars = original.characters.toList();
    final inputChars = input.characters.toList();
    final maxLen = max(origChars.length, inputChars.length);

    return SingleChildScrollView(
      child: Wrap(
        children: List.generate(maxLen, (i) {
          final origCh = i < origChars.length ? origChars[i] : '';
          final inputCh = i < inputChars.length ? inputChars[i] : '';

          if (origCh == '\n' || inputCh == '\n') {
            return SizedBox(
              width: double.infinity,
              height: theme.textTheme.titleMedium?.fontSize ?? 20,
            );
          }

          final isCorrect = origCh == inputCh;
          final isMissing = inputCh.isEmpty;

          Color color;
          String display;
          if (isCorrect) {
            color = theme.colorScheme.primary;
            display = origCh;
          } else if (isMissing) {
            color = theme.colorScheme.onSurface.withValues(alpha: 0.3);
            display = origCh;
          } else {
            color = theme.colorScheme.error;
            display = inputCh;
          }

          return Text(
            display,
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: isCorrect ? FontWeight.normal : FontWeight.bold,
              decoration: isCorrect ? null : TextDecoration.underline,
              decorationColor: color,
              height: 2,
              letterSpacing: 1,
            ),
          );
        }),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 结果卡片
  // ─────────────────────────────────────────────────────────────

  Widget _buildResultCard(BuildContext context) {
    final theme = Theme.of(context);
    final elapsed = DateTime.now().difference(_startTime).inSeconds;
    final maxStars = _level == ReciteLevel.dictation ? 3 : _lines.length * 3;
    final displayStars = _totalStars.clamp(0, 3);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 星星
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                final filled = i < displayStars;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.xs,
                  ),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 48,
                    color: filled
                        ? theme.colorScheme.secondary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  )
                      .animate()
                      .scale(
                        begin: const Offset(0, 0),
                        end: const Offset(1, 1),
                        delay: (200 * i).ms,
                        duration: 400.ms,
                        curve: Curves.elasticOut,
                      ),
                );
              }),
            ),
            const SizedBox(height: SpacingTokens.lg),

            Text(
              _resultTitle(displayStars),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ).animate().fadeIn(delay: 600.ms, duration: 400.ms),

            const SizedBox(height: SpacingTokens.lg),

            // 统计数据
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatItem(
                  label: '得分',
                  value: '$_totalStars/$maxStars',
                  icon: Icons.star_rounded,
                  color: theme.colorScheme.secondary,
                ),
                _StatItem(
                  label: '用时',
                  value: '${elapsed}s',
                  icon: Icons.timer_outlined,
                  color: theme.colorScheme.tertiary,
                ),
                _StatItem(
                  label: '句数',
                  value: '${_lines.length}',
                  icon: Icons.format_list_numbered,
                  color: theme.colorScheme.primary,
                ),
              ],
            )
                .animate()
                .fadeIn(delay: 800.ms, duration: 400.ms)
                .slideY(begin: 0.2, end: 0, delay: 800.ms, duration: 400.ms),

            const SizedBox(height: SpacingTokens.xl),

            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('返回'),
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
            ).animate().fadeIn(delay: 1000.ms, duration: 400.ms),
          ],
        ),
      ),
    );
  }

  String _resultTitle(int stars) {
    if (stars >= 3) return '太棒了！完美背诵！';
    if (stars >= 2) return '不错！继续加油！';
    return '再练练，会更好！';
  }
}

// ═════════════════════════════════════════════════════════════════
// 子组件
// ═════════════════════════════════════════════════════════════════

/// 空白槽位 Widget。
class _BlankSlot extends StatelessWidget {
  const _BlankSlot({required this.isActive, this.shake = false});

  final bool isActive;
  final bool shake;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget slot = Container(
      width: 28,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withValues(alpha: 0.3),
            width: isActive ? 3 : 2,
          ),
        ),
      ),
    );

    if (isActive) {
      slot = slot
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(begin: 0.95, end: 1.05, duration: 800.ms);
    }

    if (shake) {
      slot = slot.animate().shakeX(duration: 400.ms, hz: 5, amount: 6);
    }

    return slot;
  }
}

/// 结果页统计项。
class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: SpacingTokens.xs),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
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
