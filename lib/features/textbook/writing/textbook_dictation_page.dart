import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/tts/narration_session.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/textbook_dictation.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/writing/writing_canvas.dart';

enum _DictationMode { paper, handwriting }

enum _DictationStage { setup, practice, review }

class _DictationAnswer {
  _DictationAnswer(this.target);
  final TextbookDictationTarget target;

  /// 按画布边长归一化；旋转屏幕、预览缩放都不改变原始笔迹。
  List<List<Offset>> strokes = [];
  bool? correct;

  List<List<Offset>> strokesAt(double side) => [
    for (final stroke in strokes) [for (final point in stroke) point * side],
  ];
}

/// 本课随机听写：纸笔/屏幕共用题序与音频，完成整轮才展示答案。
/// 笔迹与家长核对仅属于本轮，不将听过题目当作已掌握或已描红。
class TextbookDictationPage extends ConsumerStatefulWidget {
  const TextbookDictationPage({
    super.key,
    required this.bookId,
    required this.lessonId,
    this.routeObserver,
  });

  final String bookId, lessonId;
  final RouteObserver<ModalRoute<dynamic>>? routeObserver;

  @override
  ConsumerState<TextbookDictationPage> createState() =>
      _TextbookDictationPageState();
}

class _TextbookDictationPageState extends ConsumerState<TextbookDictationPage>
    with WidgetsBindingObserver, RouteAware {
  _DictationMode _mode = _DictationMode.paper;
  _DictationStage _stage = _DictationStage.setup;
  int _interval = 0;
  int _index = 0;
  List<TextbookDictationTarget> _allTargets = [];
  List<_DictationAnswer> _answers = [];
  String? _sourceDigest;
  String? _invalidMessage;
  bool _heard = false;
  bool _paused = false;
  bool _controlling = false;
  bool _foreground = true;
  bool _disposed = false;
  bool _allowPop = false;
  bool _exitDialogOpen = false;
  int? _remaining;
  Timer? _timer;
  late final TtsService _tts;
  NarrationSession? _session;
  NarrationStatus? _audioStatus;
  int _activeSessionId = -1;
  ModalRoute<dynamic>? _route;
  late final int _profileRevision;
  StreamSubscription<String>? _profileChanges;
  StreamSubscription<dynamic>? _restore;

  bool get _current =>
      mounted &&
      !_disposed &&
      _invalidMessage == null &&
      _profileRevision == ProfileScope.revision;

  bool get _canPlay =>
      _current &&
      _stage == _DictationStage.practice &&
      !_paused &&
      _foreground &&
      _route?.isCurrent != false;

  _DictationAnswer get _answer => _answers[_index];

  Color get _accent {
    final scheme = Theme.of(context).colorScheme;
    return scheme.brightness == Brightness.dark
        ? scheme.onPrimaryContainer
        : scheme.primary;
  }

  ButtonStyle get _outlinedStyle =>
      OutlinedButton.styleFrom(foregroundColor: _accent);

  ButtonStyle get _textStyle => TextButton.styleFrom(foregroundColor: _accent);

  @override
  void initState() {
    super.initState();
    _profileRevision = ProfileScope.revision;
    _tts = ref.read(ttsServiceProvider);
    WidgetsBinding.instance.addObserver(this);
    _profileChanges = ProfileScope.changes.listen((_) {
      _invalidate('档案已切换，请返回后重新开始听写。');
    });
    _restore = HiveBoxes.meta.watch(key: 'practice_draft_epoch').listen((_) {
      _invalidate('学习数据已恢复，请返回后重新开始听写。');
    });
  }

  String _digest(TextbookCourseLesson lesson) =>
      textbookTextDigest(jsonEncode(lesson.toJson()));

  TextbookCourseLesson? _lesson(TextbookCoursePack? pack) =>
      pack?.lessons.where((l) => l.id == widget.lessonId).firstOrNull;

  void _invalidate(String message) {
    if (!mounted || _disposed) return;
    _cancelTimer();
    _stopAudio();
    setState(() {
      _invalidMessage = message;
      _paused = true;
    });
  }

  void _startRound(Iterable<TextbookDictationTarget> targets) {
    if (!_current) return;
    final shuffled = shuffledDictationTargets(targets);
    if (shuffled.isEmpty) return;
    _cancelTimer();
    _stopAudio();
    setState(() {
      _answers = [for (final target in shuffled) _DictationAnswer(target)];
      _index = 0;
      _stage = _DictationStage.practice;
      _paused = false;
      _heard = false;
      _remaining = null;
    });
    _playQuestion();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// 只取消本页持有的会话，旧页面的异步退出不能停止新页面的朗读。
  void _stopAudio() {
    final session = _session;
    _session = null;
    _activeSessionId = -1;
    _audioStatus = null;
    if (session != null) {
      unawaited(session.cancel().catchError((Object _) {}));
    }
  }

  void _playQuestion() {
    if (!_canPlay) return;
    _cancelTimer();
    _stopAudio();
    setState(() {
      _audioStatus = NarrationStatus.preparing;
      _remaining = null;
    });
    try {
      final session = _tts.startNarration(
        [_answer.target.prompt],
        bookId: widget.bookId,
        cache: ref.read(textbookFileServiceProvider).narrationCache,
        onSegmentStart: (_, id) {
          if (!_current || id != _activeSessionId) return;
          setState(() => _heard = true);
        },
        onState: (state, id) {
          if (!_current || id != _activeSessionId) return;
          setState(() {
            _audioStatus = state.status;
            if (state.status == NarrationStatus.completed) {
              _heard = true;
              _session = null;
              _activeSessionId = -1;
            } else if (state.status == NarrationStatus.stopped) {
              _session = null;
              _activeSessionId = -1;
              _paused = true;
            }
          });
          if (state.status == NarrationStatus.completed) _scheduleNext();
        },
      );
      _session = session;
      _activeSessionId = session.sessionId;
    } on Object {
      if (_current) {
        setState(() => _audioStatus = NarrationStatus.failed);
      }
    }
  }

  /// 从实际播报完成开始留出书写时间，生成音频的等待不占用间隔。
  void _scheduleNext() {
    _cancelTimer();
    if (!_canPlay ||
        _mode != _DictationMode.paper ||
        _interval == 0 ||
        _audioStatus != NarrationStatus.completed) {
      return;
    }
    setState(() => _remaining ??= _interval);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_canPlay) {
        _cancelTimer();
        return;
      }
      if (_remaining! <= 1) {
        _advance();
      } else {
        setState(() => _remaining = _remaining! - 1);
      }
    });
  }

  void _advance({bool skipped = false}) {
    if (!_canPlay || !_heard || _controlling) return;
    _cancelTimer();
    _stopAudio();
    setState(() {
      if (skipped) _answer.correct = false;
      _remaining = null;
      if (_index + 1 == _answers.length) {
        _stage = _DictationStage.review;
      } else {
        _index++;
        _heard = false;
      }
    });
    if (_stage == _DictationStage.practice) _playQuestion();
  }

  Future<void> _togglePause() async {
    if (!_current || _controlling) return;
    _controlling = true;
    final session = _session;
    final resuming = _paused;
    try {
      if (resuming) {
        if (session != null) await session.resume();
        if (!_current ||
            !_foreground ||
            _route?.isCurrent == false ||
            (session != null &&
                session != _session &&
                _audioStatus != NarrationStatus.completed)) {
          return;
        }
        setState(() => _paused = false);
        if (session == null && _audioStatus != NarrationStatus.completed) {
          _playQuestion();
        } else {
          _scheduleNext();
        }
      } else {
        _cancelTimer();
        if (_audioStatus == NarrationStatus.failed) _stopAudio();
        setState(() => _paused = true);
        await session?.pause();
      }
    } on Object {
      if (_current) {
        _stopAudio();
        setState(() {
          _paused = true;
          _audioStatus = NarrationStatus.failed;
        });
      }
    } finally {
      if (mounted && !_disposed) setState(() => _controlling = false);
    }
  }

  void _suspend() {
    _cancelTimer();
    _stopAudio();
    if (mounted && !_disposed && _stage == _DictationStage.practice) {
      setState(() => _paused = true);
    }
  }

  Future<void> _confirmExit() async {
    if (_exitDialogOpen) return;
    _exitDialogOpen = true;
    _suspend();
    try {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('结束本次听写？'),
          content: const Text('离开后，本轮笔迹和核对结果不会保留。'),
          actions: [
            TextButton(
              style: _textStyle,
              onPressed: () => Navigator.pop(context, false),
              child: const Text('留在本轮'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('结束听写'),
            ),
          ],
        ),
      );
      if (leave == true && mounted) {
        setState(() => _allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    } finally {
      _exitDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final course = ref.watch(textbookCourseProvider(widget.bookId));
    ref.listen(textbookCourseProvider(widget.bookId), (_, next) {
      if (_sourceDigest == null || _invalidMessage != null) return;
      final lesson = _lesson(next.valueOrNull);
      if (next.hasError ||
          (!next.isLoading &&
              (lesson == null || _digest(lesson) != _sourceDigest))) {
        _invalidate('课文内容已更新或移除，请返回后重新开始听写。');
      }
    });
    final lesson = _lesson(course.valueOrNull);
    final theme = Theme.of(context);
    final Widget body;
    if (_invalidMessage != null) {
      body = _notice(_invalidMessage!);
    } else if (course.hasError) {
      body = _notice(
        '会写字加载失败，请重试。',
        retry: () => ref.invalidate(textbookCourseProvider(widget.bookId)),
      );
    } else if (course.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (lesson == null) {
      body = _notice('找不到这课的会写字，请返回后重试。');
    } else {
      body = LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final side = math.min(width - SpacingTokens.md * 2, 280.0);
          return ListView(
            key: ValueKey(_stage),
            padding: const EdgeInsets.all(SpacingTokens.md),
            children: switch (_stage) {
              _DictationStage.setup => _setup(lesson, width),
              _DictationStage.practice => _practice(side),
              _DictationStage.review => _review(theme),
            },
          );
        },
      );
    }
    return PopScope<void>(
      canPop:
          _allowPop ||
          _stage == _DictationStage.setup ||
          _invalidMessage != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmExit());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(lesson == null ? '听写' : '听写·${lesson.title}'),
        ),
        body: SafeArea(child: body),
      ),
    );
  }

  Widget _notice(String text, {VoidCallback? retry}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          if (retry != null) ...[
            const SizedBox(height: SpacingTokens.md),
            FilledButton(onPressed: retry, child: const Text('重试')),
          ],
        ],
      ),
    ),
  );

  List<Widget> _setup(TextbookCourseLesson lesson, double width) {
    final theme = Theme.of(context);
    final targets = textbookDictationTargets(lesson);
    final modes = [
      for (final mode in _DictationMode.values)
        Semantics(
          selected: _mode == mode,
          child: AppTile(
            key: ValueKey('dictation-mode-${mode.name}'),
            icon: mode == _DictationMode.paper
                ? Icons.edit_note_outlined
                : Icons.draw_outlined,
            iconColor: _accent,
            title: mode == _DictationMode.paper ? '纸上听写' : '屏幕手写',
            subtitle: mode == _DictationMode.paper
                ? '准备纸笔，听完后在纸上写'
                : '在空白田字格中写，保留每题笔迹供核对',
            trailingIcon: _mode == mode
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            onTap: () => setState(() => _mode = mode),
          ),
        ),
    ];
    return [
      if (width >= ResponsiveLayout.mediumBreakpoint)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: modes[0]),
              const SizedBox(width: SpacingTokens.sm),
              Expanded(child: modes[1]),
            ],
          ),
        )
      else
        Column(
          children: [
            modes[0],
            const SizedBox(height: SpacingTokens.sm),
            modes[1],
          ],
        ),
      if (_mode == _DictationMode.paper) ...[
        const SizedBox(height: SpacingTokens.md),
        Text('播报节奏', style: theme.textTheme.titleSmall),
        const SizedBox(height: SpacingTokens.sm),
        Wrap(
          spacing: SpacingTokens.sm,
          runSpacing: SpacingTokens.xs,
          children: [
            for (final interval in [0, 10, 15, 20, 30])
              ChoiceChip(
                label: Text(interval == 0 ? '手动下一题' : '间隔 $interval 秒'),
                labelStyle: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
                checkmarkColor: _accent,
                selected: _interval == interval,
                onSelected: (_) => setState(() => _interval = interval),
              ),
          ],
        ),
      ],
      const SizedBox(height: SpacingTokens.lg),
      FilledButton.icon(
        key: const ValueKey('dictation-start'),
        onPressed: targets.isEmpty
            ? null
            : () {
                _allTargets = targets;
                _sourceDigest = _digest(lesson);
                _startRound(targets);
              },
        icon: const Icon(Icons.hearing_outlined),
        label: const Text('开始听写'),
      ),
      if (targets.isEmpty)
        const AppEmptyState(
          icon: Icons.hearing_outlined,
          title: '本课暂无会写字。',
          description: '请家长核对本课的书写内容。',
        ),
    ];
  }

  String get _playbackLabel {
    if (_paused) return '听写已暂停';
    return switch (_audioStatus) {
      NarrationStatus.preparing || NarrationStatus.buffering => '正在准备播报…',
      NarrationStatus.playing => '仔细听一听',
      NarrationStatus.failed => '播报暂时不可用，请点“再读一次”重试。',
      _ => _mode == _DictationMode.paper ? '在纸上写下这个字' : '在田字格中写下这个字',
    };
  }

  List<Widget> _practice(double side) {
    final theme = Theme.of(context);
    final handwriting = _mode == _DictationMode.handwriting;
    final canAdvance = _heard && !_paused && !_controlling;
    return [
      Text(
        '第 ${_index + 1} / ${_answers.length} 题',
        key: const ValueKey('dictation-progress'),
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge,
      ),
      const SizedBox(height: SpacingTokens.sm),
      LinearProgressIndicator(value: _index / _answers.length),
      const SizedBox(height: SpacingTokens.lg),
      Icon(
        _paused ? Icons.pause_circle_outline : Icons.hearing_outlined,
        size: SpacingTokens.xxl,
        color: _accent,
      ),
      const SizedBox(height: SpacingTokens.sm),
      Text(
        _playbackLabel,
        textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: SpacingTokens.md),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: SpacingTokens.sm,
        runSpacing: SpacingTokens.sm,
        children: [
          OutlinedButton.icon(
            style: _outlinedStyle,
            onPressed: _paused || _controlling ? null : _playQuestion,
            icon: const Icon(Icons.volume_up_outlined),
            label: const Text('再读一次'),
          ),
          OutlinedButton.icon(
            style: _outlinedStyle,
            onPressed: _controlling ? null : () => unawaited(_togglePause()),
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
            label: Text(_paused ? '继续听写' : '暂停听写'),
          ),
        ],
      ),
      const SizedBox(height: SpacingTokens.lg),
      if (handwriting) ...[
        Center(
          child: Semantics(
            label: '第 ${_index + 1} 题的空白书写区',
            child: WritingCanvas(
              key: ValueKey('dictation-input-$_index'),
              side: side,
              enabled: !_paused,
              strokes: _answer.strokesAt(side),
              onStrokesChanged: (strokes) => setState(() {
                _answer.strokes = [
                  for (final stroke in strokes)
                    [for (final point in stroke) point / side],
                ];
              }),
            ),
          ),
        ),
        const SizedBox(height: SpacingTokens.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: SpacingTokens.md,
          children: [
            TextButton(
              style: _textStyle,
              onPressed: _paused || _answer.strokes.isEmpty
                  ? null
                  : () => setState(() {
                      _answer.strokes = _answer.strokes.sublist(
                        0,
                        _answer.strokes.length - 1,
                      );
                    }),
              child: const Text('撤销一笔'),
            ),
            TextButton(
              style: _textStyle,
              onPressed: _paused || _answer.strokes.isEmpty
                  ? null
                  : () => setState(() => _answer.strokes = []),
              child: const Text('清空'),
            ),
          ],
        ),
        const SizedBox(height: SpacingTokens.md),
      ],
      if (_remaining != null) ...[
        Text(
          _index + 1 == _answers.length
              ? '$_remaining 秒后结束听写，统一核对'
              : '$_remaining 秒后播报下一题',
          key: const ValueKey('dictation-countdown'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SpacingTokens.md),
      ],
      FilledButton(
        key: const ValueKey('dictation-next'),
        onPressed: canAdvance && (!handwriting || _answer.strokes.isNotEmpty)
            ? _advance
            : null,
        child: Text(
          _index + 1 == _answers.length
              ? '完成听写，统一核对'
              : handwriting
              ? '写好了，下一题'
              : '下一题',
        ),
      ),
      if (handwriting)
        TextButton(
          key: const ValueKey('dictation-skip'),
          style: _textStyle,
          onPressed: canAdvance ? () => _advance(skipped: true) : null,
          child: const Text('不会写，先跳过'),
        ),
    ];
  }

  List<Widget> _review(ThemeData theme) {
    final checked = _answers.where((answer) => answer.correct != null).length;
    final correct = _answers.where((answer) => answer.correct == true).length;
    final wrong = _answers.where((answer) => answer.correct == false).toList();
    final allChecked = checked == _answers.length;
    return [
      Text('整轮核对', style: theme.textTheme.titleLarge),
      const SizedBox(height: SpacingTokens.sm),
      Text(
        '已核对 $checked / ${_answers.length}，写对 $correct 个，还要练 ${wrong.length} 个',
      ),
      const SizedBox(height: SpacingTokens.sm),
      const Text('请家长按听写顺序核对，选择“写对了”或“还要练”。'),
      const SizedBox(height: SpacingTokens.md),
      for (var i = 0; i < _answers.length; i++) ...[
        _reviewCard(i, theme),
        const SizedBox(height: SpacingTokens.md),
      ],
      if (!allChecked) ...[
        const Text('完成全部核对后，可以只听写还要练的字。'),
        const SizedBox(height: SpacingTokens.sm),
      ],
      FilledButton(
        key: const ValueKey('dictation-retry-wrong'),
        onPressed: allChecked && wrong.isNotEmpty
            ? () => _startRound(wrong.map((answer) => answer.target))
            : null,
        child: const Text('只听写错字'),
      ),
      const SizedBox(height: SpacingTokens.sm),
      OutlinedButton(
        key: const ValueKey('dictation-retry-all'),
        style: _outlinedStyle,
        onPressed: () => _startRound(_allTargets),
        child: const Text('全课再来一轮'),
      ),
    ];
  }

  Widget _reviewCard(int index, ThemeData theme) {
    final answer = _answers[index];
    final handwriting = _mode == _DictationMode.handwriting;
    return ColoredCard(
      key: ValueKey('dictation-review-$index'),
      color: theme.colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('第 ${index + 1} 题', style: theme.textTheme.titleSmall),
          const SizedBox(height: SpacingTokens.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final side = math.min(
                140.0,
                (constraints.maxWidth - SpacingTokens.md) / 2,
              );
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      const Text('标准字'),
                      const SizedBox(height: SpacingTokens.sm),
                      SizedBox.square(
                        dimension: side,
                        child: CustomPaint(
                          painter: TianziGridPainter(
                            gridColor: theme.colorScheme.outline,
                          ),
                          child: Center(
                            child: Text(
                              answer.target.text,
                              style: theme.textTheme.displayMedium?.copyWith(
                                fontSize: side * 0.72,
                                height: 1,
                              ),
                              textScaler: TextScaler.noScaling,
                            ),
                          ),
                        ),
                      ),
                      if (answer.target.pinyin.isNotEmpty)
                        Text(answer.target.pinyin),
                    ],
                  ),
                  if (handwriting)
                    Column(
                      children: [
                        const Text('我写的'),
                        const SizedBox(height: SpacingTokens.sm),
                        WritingCanvas(
                          key: ValueKey('dictation-answer-$index'),
                          side: side,
                          strokes: answer.strokesAt(280),
                          strokesSide: 280,
                          enabled: false,
                        ),
                        if (answer.strokes.isEmpty) const Text('未作答'),
                      ],
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: SpacingTokens.sm),
          Wrap(
            spacing: SpacingTokens.sm,
            runSpacing: SpacingTokens.xs,
            alignment: WrapAlignment.center,
            children: [
              ChoiceChip(
                key: ValueKey('dictation-correct-$index'),
                label: const Text('写对了'),
                labelStyle: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
                checkmarkColor: _accent,
                selected: answer.correct == true,
                onSelected: (_) => setState(() => answer.correct = true),
              ),
              ChoiceChip(
                key: ValueKey('dictation-wrong-$index'),
                label: const Text('还要练'),
                labelStyle: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
                checkmarkColor: _accent,
                selected: answer.correct == false,
                onSelected: (_) => setState(() => answer.correct = false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      widget.routeObserver?.unsubscribe(this);
      _route = route;
      if (route != null) widget.routeObserver?.subscribe(this, route);
    }
  }

  @override
  void didUpdateWidget(covariant TextbookDictationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId != widget.bookId ||
        oldWidget.lessonId != widget.lessonId) {
      _invalidate('课文已切换，请返回后重新开始听写。');
    }
  }

  @override
  void didPushNext() => _suspend();

  @override
  void didPop() => _suspend();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) _suspend();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimer();
    _stopAudio();
    widget.routeObserver?.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_profileChanges?.cancel());
    unawaited(_restore?.cancel());
    super.dispose();
  }
}
