// lib/features/poem/poem_read_along_page.dart
//
// 层级：features/poem
// 职责：诗词朗读跟读评分页 — TTS 范读 + 语音识别跟读 + 逐字对比评分。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/services/speech/hybrid_speech_recognition_service.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';
import 'package:poemath/features/poem/widgets/read_along_voice_status_button.dart';

/// 跟读状态。
enum _ReadAlongPhase {
  /// 等待用户操作。
  idle,

  /// 准备初始化模型、权限和录音。
  preparing,

  /// TTS 范读中。
  modelReading,

  /// 语音录制中。
  recording,

  /// 本地识别收尾及可选云端识别中。
  processing,

  /// 显示本句得分。
  scored,

  /// 全部完成。
  complete,
}

class PoemReadAlongPage extends ConsumerStatefulWidget {
  const PoemReadAlongPage({
    super.key,
    required this.poemId,
    this.speechRecognitionService,
  });

  final String poemId;
  final SpeechRecognitionService? speechRecognitionService;

  @override
  ConsumerState<PoemReadAlongPage> createState() => _PoemReadAlongPageState();
}

class _PoemReadAlongPageState extends ConsumerState<PoemReadAlongPage> {
  static const _maxRecordingDurationSeconds = 15;

  late final SpeechRecognitionService _speech;
  late final TtsService _tts;
  bool _speechAvailable = false;
  Timer? _recordingTimer;
  Future<void>? _speechInitialization;
  SpeechRecognitionSource _recognitionSource = SpeechRecognitionSource.local;

  /// 诗句列表（按换行拆分）。
  List<String> _lines = [];

  /// 当前行索引。
  int _currentLine = 0;

  /// 当前阶段。
  _ReadAlongPhase _phase = _ReadAlongPhase.idle;

  /// 每行的识别文本。
  final List<String> _recognizedTexts = [];

  /// 每行的准确率（0.0 ~ 1.0）。
  final List<double> _scores = [];

  /// 当前实时识别文本。
  String _liveText = '';

  /// 当前录音已持续秒数。
  int _recordingElapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _speech = widget.speechRecognitionService ??
        ref.read(speechRecognitionServiceProvider);
    _tts = ref.read(ttsServiceProvider);
    unawaited(_initSpeech());
  }

  /// 语音识别初始化失败的原因描述。
  String _speechUnavailableReason = '';

  Future<void> _initSpeech() async {
    final existingInitialization = _speechInitialization;
    if (existingInitialization != null) {
      await existingInitialization;
      return;
    }

    final initialization = _initializeSpeech();
    _speechInitialization = initialization;
    try {
      await initialization;
    } finally {
      if (identical(_speechInitialization, initialization)) {
        _speechInitialization = null;
      }
    }
  }

  Future<void> _initializeSpeech() async {
    try {
      await _speech.initialize();
      _speechAvailable = true;
      _speechUnavailableReason = '';
    } on SpeechRecognitionException catch (error) {
      _speechAvailable = false;
      _speechUnavailableReason = error.message;
    } on Object catch (error, stackTrace) {
      _speechAvailable = false;
      _speechUnavailableReason = '离线语音模型初始化失败';
      AppLogger.e(
        '离线语音模型初始化失败',
        tag: 'PoemReadAlong',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    unawaited(_speech.cancel());
    unawaited(
      _tts.stop().onError(
            (error, stackTrace) => AppLogger.e(
              '退出跟读页时停止范读失败',
              tag: 'PoemReadAlong',
              error: error,
              stackTrace: stackTrace,
            ),
          ),
    );
    super.dispose();
  }

  /// 将诗词内容按换行拆分成行。
  List<String> _splitLines(String content) {
    return content
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // ============ TTS 范读 ============

  Future<void> _playModelReading() async {
    if (_phase != _ReadAlongPhase.idle && _phase != _ReadAlongPhase.scored) {
      return;
    }

    final scaffold = ScaffoldMessenger.of(context);
    setState(() => _phase = _ReadAlongPhase.modelReading);

    try {
      await _tts.speak(_lines[_currentLine]);
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '诗词范读失败',
        tag: 'PoemReadAlong',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          const SnackBar(
            content: Text('范读失败，请检查系统语音服务后重试'),
          ),
        );
      }
    } finally {
      if (mounted && _phase == _ReadAlongPhase.modelReading) {
        setState(() => _phase = _ReadAlongPhase.idle);
      }
    }
  }

  Future<void> _stopModelReading() async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await _tts.stop();
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '停止诗词范读失败',
        tag: 'PoemReadAlong',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          const SnackBar(content: Text('停止范读失败，请稍后重试')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _phase = _ReadAlongPhase.idle);
      }
    }
  }

  // ============ 语音识别录制 ============

  Future<void> _startRecording() async {
    if (!mounted ||
        (_phase != _ReadAlongPhase.idle && _phase != _ReadAlongPhase.scored)) {
      return;
    }
    setState(() {
      _phase = _ReadAlongPhase.preparing;
      _liveText = '';
      _recordingElapsedSeconds = 0;
    });

    if (!_speechAvailable) {
      await _initSpeech();
      if (!_speechAvailable && mounted) {
        setState(() => _phase = _ReadAlongPhase.idle);
        _showSpeechUnavailableDialog();
      }
      if (!_speechAvailable) return;
    }
    if (!mounted || _phase != _ReadAlongPhase.preparing) return;

    // 停止 TTS
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await _tts.stop();
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '开始跟读前停止范读失败',
        tag: 'PoemReadAlong',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _phase = _ReadAlongPhase.idle);
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          const SnackBar(content: Text('无法开始跟读，请稍后重试')),
        );
      }
      return;
    }

    if (!mounted || _phase != _ReadAlongPhase.preparing) return;

    try {
      await _speech.start(
        onPartialResult: (text) {
          if (mounted &&
              (_phase == _ReadAlongPhase.preparing ||
                  _phase == _ReadAlongPhase.recording)) {
            setState(() => _liveText = text);
          }
        },
      );
      if (!mounted) {
        await _speech.cancel();
        return;
      }
      if (_phase != _ReadAlongPhase.preparing) {
        await _speech.cancel();
        return;
      }
      setState(() => _phase = _ReadAlongPhase.recording);
      _startRecordingTimer();
    } on SpeechPermissionDeniedException {
      if (mounted) setState(() => _phase = _ReadAlongPhase.idle);
      _speechUnavailableReason = '未获得麦克风权限';
      if (mounted) _showSpeechUnavailableDialog();
    } on SpeechRecognitionException catch (error, stackTrace) {
      AppLogger.e(
        '开始离线跟读失败',
        tag: 'PoemReadAlong',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _phase = _ReadAlongPhase.idle);
        scaffold.clearSnackBars();
        scaffold.showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '开始跟读录音失败',
        tag: 'PoemReadAlong',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _phase = _ReadAlongPhase.idle);
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          const SnackBar(content: Text('无法开始跟读，请检查麦克风权限')),
        );
      }
    }
  }

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _phase != _ReadAlongPhase.recording) {
        timer.cancel();
        _recordingTimer = null;
        return;
      }

      final elapsed = _recordingElapsedSeconds + 1;
      setState(() => _recordingElapsedSeconds = elapsed);
      if (elapsed >= _maxRecordingDurationSeconds) {
        timer.cancel();
        _recordingTimer = null;
        unawaited(_stopRecording());
      }
    });
  }

  void _showSpeechUnavailableDialog() {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SpacingTokens.radiusLarge),
        ),
        title: Row(
          children: [
            Icon(
              Icons.mic_off_rounded,
              color: theme.colorScheme.error,
              size: 24,
            ),
            const SizedBox(width: SpacingTokens.sm),
            const Text('语音识别不可用'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _speechUnavailableReason,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SpacingTokens.md),
            Text(
              '请尝试以下操作：',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: SpacingTokens.sm),
            Text(
              '1. 确认已授予麦克风权限\n'
              '2. 确认设备有足够的可用存储空间\n'
              '3. 重新进入页面后重试',
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.6,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _applyRecognitionResult(SpeechRecognitionResult result) {
    final recognized = result.text;
    final original = _lines[_currentLine];
    final score = _calculateAccuracy(original, recognized);

    setState(() {
      _recognizedTexts.add(recognized);
      _scores.add(score);
      _recognitionSource = result.source;
      _phase = _ReadAlongPhase.scored;
    });

    // 触觉反馈
    final settingsRepo = ref.read(settingsRepositoryProvider);
    if (settingsRepo.hapticEnabled) {
      if (score >= 0.8) {
        HapticFeedback.lightImpact();
      } else {
        HapticFeedback.mediumImpact();
      }
    }

    // 音效
    final sound = ref.read(soundServiceProvider);
    if (score >= 0.6) {
      sound.play(SoundEffect.correct);
    } else {
      sound.play(SoundEffect.wrong);
    }
  }

  Future<void> _stopRecording() async {
    if (_phase != _ReadAlongPhase.recording) return;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final scaffold = ScaffoldMessenger.of(context);
    setState(() => _phase = _ReadAlongPhase.processing);

    try {
      final result = await _speech.stop();
      if (!mounted) return;
      _applyRecognitionResult(result);
      if (result.fellBackFromCloud) {
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          const SnackBar(content: Text('高精度识别暂不可用，已使用离线结果')),
        );
      }
    } on SpeechRecognitionException catch (error, stackTrace) {
      AppLogger.e(
        '跟读识别失败',
        tag: 'PoemReadAlong',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _phase = _ReadAlongPhase.idle);
        scaffold.clearSnackBars();
        scaffold.showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '跟读识别失败',
        tag: 'PoemReadAlong',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _phase = _ReadAlongPhase.idle);
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          const SnackBar(content: Text('语音识别失败，请重新朗读')),
        );
      }
    }
  }

  // ============ 评分算法 ============

  /// 基于最长公共子序列 (LCS) 计算字符准确率。
  ///
  /// 去除标点符号后比较，返回 0.0 ~ 1.0。
  double _calculateAccuracy(String original, String recognized) {
    final originalClean = _removePunctuation(original);
    final recognizedClean = _removePunctuation(recognized);

    if (originalClean.isEmpty) return 1.0;
    if (recognizedClean.isEmpty) return 0.0;

    final lcsLen = _lcsLength(originalClean, recognizedClean);
    return lcsLen / originalClean.length;
  }

  /// 去除中英文标点和空格。
  String _removePunctuation(String text) {
    return text.replaceAll(
      RegExp('[，。！？、；：""' '（）《》\\s,.!?;:\'"()\\[\\]{}]'),
      '',
    );
  }

  /// 最长公共子序列长度（动态规划）。
  int _lcsLength(String a, String b) {
    final m = a.length;
    final n = b.length;
    // 使用滚动数组节省空间
    var prev = List.filled(n + 1, 0);
    var curr = List.filled(n + 1, 0);

    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          curr[j] = prev[j - 1] + 1;
        } else {
          curr[j] = curr[j - 1] > prev[j] ? curr[j - 1] : prev[j];
        }
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
      curr.fillRange(0, n + 1, 0);
    }

    return prev[n];
  }

  /// 逐字对比：返回原文每个字符是否匹配的列表。
  List<bool> _charMatches(String original, String recognized) {
    final origClean = _removePunctuation(original);
    final recClean = _removePunctuation(recognized);

    if (origClean.isEmpty) return [];
    if (recClean.isEmpty) return List.filled(origClean.length, false);

    // 使用 LCS 回溯确定匹配位置
    final m = origClean.length;
    final n = recClean.length;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));

    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        if (origClean[i - 1] == recClean[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }

    // 回溯
    final matches = List.filled(m, false);
    var i = m;
    var j = n;
    while (i > 0 && j > 0) {
      if (origClean[i - 1] == recClean[j - 1]) {
        matches[i - 1] = true;
        i--;
        j--;
      } else if (dp[i - 1][j] > dp[i][j - 1]) {
        i--;
      } else {
        j--;
      }
    }

    return matches;
  }

  // ============ 导航 ============

  void _nextLine() {
    if (_currentLine < _lines.length - 1) {
      setState(() {
        _currentLine++;
        _phase = _ReadAlongPhase.idle;
        _liveText = '';
      });
    } else {
      setState(() => _phase = _ReadAlongPhase.complete);
    }
  }

  void _retryLine() {
    // 移除最后一次得分
    if (_recognizedTexts.isNotEmpty) {
      _recognizedTexts.removeLast();
      _scores.removeLast();
    }
    setState(() {
      _phase = _ReadAlongPhase.idle;
      _liveText = '';
    });
  }

  double get _overallScore {
    if (_scores.isEmpty) return 0;
    return _scores.reduce((a, b) => a + b) / _scores.length;
  }

  IconData _scoreIconData(double score) {
    if (score >= 0.9) return Icons.star_rounded;
    if (score >= 0.7) return Icons.thumb_up_rounded;
    if (score >= 0.5) return Icons.fitness_center_rounded;
    return Icons.refresh_rounded;
  }

  String _scoreLabel(double score) {
    if (score >= 0.9) return '太棒了！';
    if (score >= 0.7) return '读得不错！';
    if (score >= 0.5) return '继续加油！';
    return '再试一次吧';
  }

  Color _scoreColor(double score, ThemeData theme) {
    if (score >= 0.8) return theme.semantic.success;
    if (score >= 0.6) return theme.semantic.caution;
    return theme.colorScheme.error;
  }

  // ============ UI ============

  @override
  Widget build(BuildContext context) {
    final poem = ref.watch(poemByIdProvider(widget.poemId));
    final theme = Theme.of(context);

    if (poem == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('跟读练习')),
        body: const Center(child: Text('诗词未找到')),
      );
    }

    if (_lines.isEmpty) {
      _lines = _splitLines(poem.content);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(poem.title),
        actions: [
          if (_phase != _ReadAlongPhase.complete)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: SpacingTokens.md),
                child: Text(
                  '${_currentLine + 1} / ${_lines.length}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: _phase == _ReadAlongPhase.complete
            ? _buildCompleteView(theme)
            : _buildPracticeView(theme),
      ),
      // 操作按钮固定在底部，避免 Spacer 在 ListView 中导致渲染异常
      bottomNavigationBar: _phase != _ReadAlongPhase.complete
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SpacingTokens.lg,
                  vertical: SpacingTokens.md,
                ),
                child: _buildActionArea(),
              ),
            )
          : null,
    );
  }

  Widget _buildPracticeView(ThemeData theme) {
    return AnimatedPageBody(
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg),
      children: [
        const SizedBox(height: SpacingTokens.xl),

        // 进度条
        _buildProgressBar(theme),
        const SizedBox(height: SpacingTokens.xl),

        // 当前行文本
        _buildLineCard(theme),
        const SizedBox(height: SpacingTokens.lg),

        // 识别结果 / 实时文本
        if (_phase == _ReadAlongPhase.recording ||
            _phase == _ReadAlongPhase.processing ||
            _phase == _ReadAlongPhase.scored)
          _buildRecognitionResult(theme),
      ],
    );
  }

  Widget _buildProgressBar(ThemeData theme) {
    final progress = _lines.isEmpty
        ? 0.0
        : (_currentLine + (_phase == _ReadAlongPhase.scored ? 1 : 0)) /
            _lines.length;

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(SpacingTokens.radiusPill),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
          ),
        ),
        const SizedBox(height: SpacingTokens.xs),
        // 已完成行的得分预览
        if (_scores.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _scores.map((s) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SpacingTokens.xs / 2,
                ),
                child: Icon(
                  _scoreIconData(s),
                  size: 16,
                  color: _scoreColor(s, Theme.of(context)),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildLineCard(ThemeData theme) {
    final line = _lines[_currentLine];
    final isActive = _phase == _ReadAlongPhase.modelReading;

    return ColoredCard(
      color: isActive ? theme.colorScheme.primary : theme.colorScheme.surface,
      backgroundOpacity: isActive ? 0.12 : 0.06,
      width: double.infinity,
      child: Column(
        children: [
          if (_phase == _ReadAlongPhase.scored)
            _buildColoredLine(theme)
          else
            Text(
              line,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.8,
                letterSpacing: 2,
                color: isActive ? theme.colorScheme.primary : null,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  /// 评分后显示逐字着色的原文。
  Widget _buildColoredLine(ThemeData theme) {
    final original = _lines[_currentLine];
    final recognized = _recognizedTexts.isNotEmpty ? _recognizedTexts.last : '';
    final matches = _charMatches(original, recognized);

    // 还原原始文本的逐字着色（包含标点）
    var cleanIdx = 0;

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.8,
          letterSpacing: 2,
        ),
        children: original.runes.map((rune) {
          final char = String.fromCharCode(rune);
          final isPunctuation = _removePunctuation(char).isEmpty;

          if (isPunctuation) {
            // 标点符号用默认色
            return TextSpan(text: char);
          }

          final isMatch = cleanIdx < matches.length && matches[cleanIdx];
          cleanIdx++;

          return TextSpan(
            text: char,
            style: TextStyle(
              color: isMatch ? theme.semantic.success : theme.colorScheme.error,
              fontWeight: isMatch ? FontWeight.w600 : FontWeight.w800,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRecognitionResult(ThemeData theme) {
    if (_phase == _ReadAlongPhase.recording) {
      return Column(
        children: [
          Text(
            _liveText.isEmpty ? '请开始朗读…' : _liveText,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    if (_phase == _ReadAlongPhase.processing) {
      return Column(
        children: [
          Text(
            '正在生成识别结果…',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    // scored 阶段
    final score = _scores.isNotEmpty ? _scores.last : 0.0;
    final percent = (score * 100).round();

    return Column(
      children: [
        // 分数显示
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _scoreIconData(score),
              size: 32,
              color: _scoreColor(score, theme),
            ),
            const SizedBox(width: SpacingTokens.sm),
            Text(
              '$percent分',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: _scoreColor(score, theme),
              ),
            ),
          ],
        )
            .animate()
            .scale(
              begin: const Offset(0.5, 0.5),
              end: const Offset(1.0, 1.0),
              duration: 400.ms,
              curve: Curves.elasticOut,
            )
            .fadeIn(duration: 300.ms),
        const SizedBox(height: SpacingTokens.xs),
        Text(
          _scoreLabel(score),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: _scoreColor(score, theme),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: SpacingTokens.sm),
        // 识别到的文字
        if (_recognizedTexts.isNotEmpty && _recognizedTexts.last.isNotEmpty)
          ColoredCard(
            color: theme.colorScheme.surfaceContainerHighest,
            backgroundOpacity: 0.5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _recognitionSource == SpeechRecognitionSource.tencentCloud
                      ? '高精度识别结果'
                      : '离线识别结果',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: SpacingTokens.xs),
                Text(
                  _recognizedTexts.last,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildActionArea() {
    final mediaQuery = MediaQuery.of(context);
    final reduceMotion =
        mediaQuery.disableAnimations || mediaQuery.accessibleNavigation;

    return AnimatedSwitcher(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            axis: Axis.horizontal,
            alignment: Alignment.centerLeft,
            fixedCrossAxisSizeFactor: 1,
            child: child,
          ),
        );
      },
      layoutBuilder: (currentChild, previousChildren) {
        return currentChild ?? const SizedBox.shrink();
      },
      child: KeyedSubtree(
        key: ValueKey(_actionAreaKey),
        child: _buildActionButtons(),
      ),
    );
  }

  Object get _actionAreaKey {
    switch (_phase) {
      case _ReadAlongPhase.preparing:
      case _ReadAlongPhase.recording:
      case _ReadAlongPhase.processing:
        return 'voice-status';
      case _ReadAlongPhase.idle:
      case _ReadAlongPhase.modelReading:
      case _ReadAlongPhase.scored:
      case _ReadAlongPhase.complete:
        return _phase;
    }
  }

  Widget _buildActionButtons() {
    switch (_phase) {
      case _ReadAlongPhase.idle:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _playModelReading,
                icon: const Icon(Icons.volume_up),
                label: const Text('听一听'),
              ),
            ),
            const SizedBox(width: SpacingTokens.sm),
            Expanded(
              child: FilledButton.icon(
                onPressed: _startRecording,
                icon: const Icon(Icons.mic),
                label: const Text('读一读'),
              ),
            ),
          ],
        );

      case _ReadAlongPhase.modelReading:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _stopModelReading,
            icon: const Icon(Icons.stop),
            label: const Text('停止播放'),
          ),
        );

      case _ReadAlongPhase.preparing:
        return const ReadAlongVoiceStatusButton(
          status: ReadAlongVoiceStatus.preparing,
          elapsedSeconds: 0,
          onPressed: null,
        );

      case _ReadAlongPhase.recording:
        return ReadAlongVoiceStatusButton(
          status: ReadAlongVoiceStatus.recording,
          elapsedSeconds: _recordingElapsedSeconds,
          onPressed: () => unawaited(_stopRecording()),
        );

      case _ReadAlongPhase.processing:
        return const ReadAlongVoiceStatusButton(
          status: ReadAlongVoiceStatus.processing,
          elapsedSeconds: 0,
          onPressed: null,
        );

      case _ReadAlongPhase.scored:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _retryLine,
                icon: const Icon(Icons.refresh),
                label: const Text('重读'),
              ),
            ),
            const SizedBox(width: SpacingTokens.sm),
            Expanded(
              child: FilledButton.icon(
                onPressed: _nextLine,
                icon: Icon(
                  _currentLine < _lines.length - 1
                      ? Icons.arrow_forward
                      : Icons.check,
                ),
                label: Text(
                  _currentLine < _lines.length - 1 ? '下一句' : '查看结果',
                ),
              ),
            ),
          ],
        );

      case _ReadAlongPhase.complete:
        return const SizedBox.shrink();
    }
  }

  Widget _buildCompleteView(ThemeData theme) {
    final overall = _overallScore;
    final percent = (overall * 100).round();
    final stars = overall >= 0.9
        ? 3
        : overall >= 0.7
            ? 2
            : overall >= 0.5
                ? 1
                : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: Column(
        children: [
          const SizedBox(height: SpacingTokens.xl),

          // 星星
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              final filled = i < stars;
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SpacingTokens.xs,
                ),
                child: Icon(
                  filled ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 48,
                  color: filled
                      ? theme.semantic.caution
                      : theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.3),
                ),
              );
            }),
          )
              .animate()
              .scale(
                begin: const Offset(0.3, 0.3),
                end: const Offset(1.0, 1.0),
                duration: 600.ms,
                curve: Curves.elasticOut,
              )
              .fadeIn(duration: 300.ms),
          const SizedBox(height: SpacingTokens.md),

          // 总分
          Text(
            '$percent 分',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: _scoreColor(overall, theme),
            ),
          ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
          const SizedBox(height: SpacingTokens.xs),
          Text(
            _scoreLabel(overall),
            style: theme.textTheme.titleMedium?.copyWith(
              color: _scoreColor(overall, theme),
            ),
          ),
          const SizedBox(height: SpacingTokens.xl),

          // 每行得分明细
          ColoredCard(
            color: theme.colorScheme.primary,
            backgroundOpacity: 0.06,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '各句得分',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: SpacingTokens.sm),
                ...List.generate(_lines.length, (i) {
                  final score = i < _scores.length ? _scores[i] : 0.0;
                  final pct = (score * 100).round();
                  return Padding(
                    padding: const EdgeInsets.only(
                      bottom: SpacingTokens.sm,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _scoreIconData(score),
                          size: 18,
                          color: _scoreColor(score, theme),
                        ),
                        const SizedBox(width: SpacingTokens.sm),
                        Expanded(
                          child: Text(
                            _lines[i],
                            style: theme.textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: SpacingTokens.sm),
                        Text(
                          '$pct分',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _scoreColor(score, theme),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),

          // 操作按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _currentLine = 0;
                      _phase = _ReadAlongPhase.idle;
                      _recognizedTexts.clear();
                      _scores.clear();
                      _liveText = '';
                    });
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('再练一次'),
                ),
              ),
              const SizedBox(width: SpacingTokens.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check),
                  label: const Text('完成'),
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.lg),
        ],
      ),
    );
  }
}
