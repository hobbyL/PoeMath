import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/services/tts/narration_audio_cache.dart';
import 'package:poemath/core/services/tts/narration_session.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_writing_attempt.dart';
import 'package:poemath/data/models/textbook_writing_progress.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/textbook_writing_repository.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/domain/textbook_recognition_review.dart';
import 'package:poemath/domain/textbook_writing_content.dart';
import 'package:poemath/domain/textbook_writing_review.dart';
import 'package:poemath/domain/writing_geometry.dart';
import 'package:poemath/domain/writing_stroke_data.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/writing/stroke_data_provider.dart';
import 'package:poemath/features/textbook/writing/writing_canvas.dart';
import 'package:poemath/features/textbook/writing/writing_jigsaw.dart';
import 'package:poemath/features/textbook/writing/writing_providers.dart';

/// 四阶段（PRD R2）：看笔顺 → 描红 → 空格自写 → 核对。
enum WritingStage { demonstrate, trace, free, check }

enum _WritingMode { write, puzzle }

extension on WritingStage {
  String get label => switch (this) {
    WritingStage.demonstrate => '看笔顺',
    WritingStage.trace => '描红',
    WritingStage.free => '自己写',
    WritingStage.check => '看一看',
  };
}

/// 单字书写练习页。
///
/// 家长确认是唯一权威判定（PRD R3）：几何比对只作"第 N 笔"教练提示，
/// 不设通过门槛，孩子可无限重写，也可直接请家长判定。
class WritingPracticePage extends ConsumerStatefulWidget {
  const WritingPracticePage({
    super.key,
    required this.bookId,
    required this.lessonId,
    required this.targetId,
    this.routeObserver,
  });

  final String bookId, lessonId, targetId;
  final RouteObserver<ModalRoute<dynamic>>? routeObserver;

  @override
  ConsumerState<WritingPracticePage> createState() =>
      _WritingPracticePageState();
}

class _WritingPracticePageState extends ConsumerState<WritingPracticePage>
    with WidgetsBindingObserver, RouteAware, TickerProviderStateMixin {
  TextbookCoursePack? _pack;
  TextbookCourseLesson? _lesson;
  WritingTarget? _target;
  CharacterStrokeData? _strokeData;

  /// 整份笔顺资产：指纹计算与单字数据同源，避免两处判定不一致。
  WritingStrokeAsset? _strokeAsset;
  WritingProgress? _progress;
  TextbookWritingRepository? _repository;
  late final TtsService _tts;
  late final NarrationAudioCache _cache;
  NarrationSession? _audioSession;
  NarrationStatus? _audioStatus;
  int _activeSessionId = -1;

  WritingStage _stage = WritingStage.demonstrate;
  _WritingMode _mode = _WritingMode.write;
  List<List<Offset>> _traced = [];
  List<List<Offset>> _free = [];
  WritingCheckResult? _check;
  DateTime? _traceStartedAt;
  DateTime? _freeStartedAt;

  AnimationController? _reveal;
  int _revealedStrokes = 0;
  bool _playing = false;

  bool _loading = true, _busy = false, _disposed = false;
  bool _openingRecords = false;
  String? _error;
  Future<void> Function()? _retry;
  String _profile = '';
  bool _scopeInvalid = false;
  ModalRoute<dynamic>? _route;
  StreamSubscription<dynamic>? _restore;
  StreamSubscription<String>? _profileChanges;
  int _loadId = 0;

  bool get _current =>
      mounted &&
      !_disposed &&
      !_scopeInvalid &&
      _profile == ProfileScope.currentId;

  String get _today => recognitionDay(DateTime.now());

  @override
  void initState() {
    super.initState();
    _profile = ProfileScope.currentId;
    _profileChanges = ProfileScope.changes.listen((_) {
      _scopeInvalid = true;
      unawaited(_stopAudio());
      if (mounted) {
        setState(() {
          _error = '档案已切换，请重新进入写一写';
          _retry = null;
        });
      }
    });
    _tts = ref.read(ttsServiceProvider);
    _cache = ref.read(textbookFileServiceProvider).narrationCache;
    WidgetsBinding.instance.addObserver(this);
    _restore = HiveBoxes.meta.watch(key: 'practice_draft_epoch').listen((_) {
      _scopeInvalid = true;
      unawaited(_stopAudio());
      if (mounted) {
        setState(() {
          _error = '学习数据已恢复，请重新进入写一写';
          _retry = null;
        });
      }
    });
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final generation = ++_loadId;
    final courses = ref.read(textbookCourseRepositoryProvider);
    final books = ref.read(textbookListProvider);
    if (mounted) {
      setState(() {
        _loading = true;
        _busy = false;
        _error = null;
      });
    }
    try {
      final book = books.where((b) => b.pdfSha256 == widget.bookId).firstOrNull;
      if (book == null) throw StateError('找不到这本教材');
      final pack = await courses.load(book);
      final lesson = pack?.lessons
          .where((l) => l.id == widget.lessonId)
          .firstOrNull;
      if (pack == null || lesson == null) throw StateError('找不到这课的会写字');
      final asset = await ref.read(writingStrokeDataProvider.future);
      final targets = writingTargets(
        pack,
        lesson,
        hasStrokeData: asset.hasStrokeDataSync,
      );
      final target = targets.where((t) => t.id == widget.targetId).firstOrNull;
      if (target == null) throw StateError('找不到这个字');
      final repo = TextbookWritingRepository(
        book: book,
        editionId: pack.edition.id,
        courses: courses,
        hasStrokeData: asset.hasStrokeDataSync,
        box: ref.read(textbookWritingBoxProvider),
      );
      final progress = await repo.load();
      if (!_current || generation != _loadId) return;
      setState(() {
        _pack = pack;
        _lesson = lesson;
        _target = target;
        _strokeData = asset[target.text];
        _strokeAsset = asset;
        _repository = repo;
        _progress = progress;
        _loading = false;
        _retry = null;
        // 无笔顺数据的字直接进入自由书写（AC6：可写但无几何核对）。
        if (_strokeData == null) {
          _stage = WritingStage.free;
          _freeStartedAt ??= DateTime.now();
        }
      });
      _prepareReveal();
    } on Object catch (error) {
      if (_current && generation == _loadId) {
        setState(() {
          _loading = false;
          _error = _message(error);
          _retry = _reload;
        });
      }
    }
  }

  void _prepareReveal() {
    final strokes = _strokeData;
    if (strokes == null) return;
    _reveal?.dispose();
    _revealedStrokes = 0;
    _playing = false;
    _reveal =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 700),
        )..addStatusListener((status) {
          if (status != AnimationStatus.completed) return;
          final total = strokes.strokeCount;
          if (!_current) return;
          if (_revealedStrokes + 1 >= total) {
            setState(() {
              _revealedStrokes = total;
              _playing = false;
            });
          } else {
            setState(() => _revealedStrokes++);
            _reveal?.forward(from: 0);
          }
        });
  }

  String _message(Object error) => error is FormatException
      ? error.message
      : error is StateError
      ? error.message.toString()
      : '保存或读取失败，请重试';

  Future<bool> _runWrite(
    Future<WritingProgress> Function() action, {
    VoidCallback? success,
    bool allowPageRetry = true,
  }) async {
    if (_busy || !_current) return false;
    final generation = _loadId;
    setState(() {
      _busy = true;
      _error = null;
    });
    var saved = false;
    try {
      final value = await action();
      if (_current && generation == _loadId) {
        setState(() {
          _progress = value;
          _retry = null;
        });
        saved = true;
      }
    } on Object catch (error) {
      if (_current && generation == _loadId) {
        setState(() {
          _error = _message(error);
          _retry = !allowPageRetry
              ? null
              : () async {
                  await _runWrite(action, success: success);
                };
        });
      }
    } finally {
      if (_current && generation == _loadId) setState(() => _busy = false);
    }
    if (saved && _current && generation == _loadId) success?.call();
    return saved;
  }

  /// 整课指纹。
  ///
  /// 必须与 [TextbookWritingRepository] 用**同一份**笔顺资产事实计算：
  /// 早期实现只把"当前字"当成有数据，导致页面算出的指纹与仓库不一致，
  /// 每次写入都被判为「写字内容已更新」。
  String get _fingerprint => writingLessonFingerprint(
    writingTargets(
      _pack!,
      _lesson!,
      hasStrokeData: _strokeAsset!.hasStrokeDataSync,
    ),
  );

  WritingRecord? get _record {
    final p = _progress;
    final t = _target;
    if (p == null || t == null) return null;
    return p.records[WritingProgress.targetKey(widget.lessonId, t.id)];
  }

  // ============ 阶段推进 ============

  void _goTo(WritingStage stage) {
    if (!_current) return;
    if (stage == WritingStage.trace) _traceStartedAt ??= DateTime.now();
    unawaited(_stopAudio());
    if (stage == WritingStage.demonstrate) {
      _restartReveal();
    }
    if (stage == WritingStage.free && _freeStartedAt == null) {
      _freeStartedAt = DateTime.now();
    }
    setState(() {
      _stage = stage;
      _check = null;
    });
    // 进入核对阶段即自动比对，孩子不用再点一次「核对笔顺」。
    if (stage == WritingStage.check &&
        _strokeData != null &&
        _free.isNotEmpty) {
      unawaited(_runCheck());
    }
  }

  void _restartReveal() {
    _reveal?.stop();
    setState(() {
      _revealedStrokes = 0;
      _playing = true;
    });
    _reveal?.forward(from: 0);
  }

  void _stepReveal(int delta) {
    final total = _strokeData?.strokeCount ?? 0;
    if (total == 0) return;
    _reveal?.stop();
    setState(() {
      _revealedStrokes = (_revealedStrokes + delta).clamp(0, total);
      _playing = false;
    });
  }

  Future<void> _finishTrace() async {
    final data = _strokeData;
    if (data == null) {
      _goTo(WritingStage.free);
      return;
    }
    await _recordStage(
      WritingStageDone.trace,
      onSaved: () => _goTo(WritingStage.free),
    );
  }

  Future<bool> _recordStage(
    WritingStageDone stage, {
    WritingAttempt? attempt,
    VoidCallback? onSaved,
  }) async {
    final repo = _repository;
    final target = _target;
    if (repo == null || target == null) return false;
    final expected = _progress;
    if (expected == null) return false;
    final now = DateTime.now();
    final startedAt = stage == WritingStageDone.trace
        ? _traceStartedAt ?? now
        : _freeStartedAt ?? now;
    final id =
        attempt?.id ?? 'stage-${stage.name}-${now.microsecondsSinceEpoch}';
    final WritingAttempt completed;
    try {
      completed =
          attempt ??
          WritingAttempt.captureWriting(
            id: id,
            kind: stage == WritingStageDone.trace
                ? WritingAttemptKind.trace
                : WritingAttemptKind.free,
            startedAt: startedAt,
            completedAt: now.isBefore(startedAt) ? startedAt : now,
            referenceStrokes: _strokeData?.strokes ?? const [],
            canvasSide: _canvasSide,
            strokes: [
              for (final stroke
                  in stage == WritingStageDone.trace ? _traced : _free)
                [
                  for (final point in stroke)
                    math.Point<double>(point.dx, point.dy),
                ],
            ],
          );
    } on Object catch (error) {
      if (_current) {
        setState(() {
          _error = _message(error);
          _retry = null;
        });
      }
      return false;
    }
    final lessonId = widget.lessonId;
    final fingerprint = _fingerprint;
    return _runWrite(
      () => repo.recordStage(
        lessonId: lessonId,
        fingerprint: fingerprint,
        targetId: target.id,
        stage: stage,
        operationId: id,
        expectedRevision: expected.revision,
        attempt: completed,
      ),
      success: () {
        if (stage == WritingStageDone.trace) _traceStartedAt = null;
        if (stage == WritingStageDone.free) {
          _freeStartedAt = _free.isEmpty ? DateTime.now() : null;
        }
        unawaited(_recordWritingActivity(completed));
        onSaved?.call();
      },
      allowPageRetry: stage != WritingStageDone.puzzle,
    );
  }

  Future<void> _recordWritingActivity(WritingAttempt attempt) async {
    try {
      await ref
          .read(learningActivityRepositoryProvider)
          .record(
            id: 'textbook-writing:${attempt.id}',
            activityType: LearningActivityType.textbookWriting,
            totalItems: 1,
            successfulItems: 1,
            starsEarned: 0,
            durationSeconds: attempt.durationSeconds,
            completedAt: attempt.completedAt,
          );
      ref.invalidate(todayLearningActivityCountsProvider);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '写一写完成活动保存失败',
        tag: 'TextbookWriting',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _runCheck() async {
    final data = _strokeData;
    final side = _canvasSide;
    if (data == null) return;
    final userStrokes = _free
        .where((stroke) => stroke.length > 1)
        .map(
          (stroke) => [
            for (final point in stroke) math.Point<double>(point.dx, point.dy),
          ],
        )
        .toList();
    // 参考 medians 用同一画布尺寸换算：把 1024 画布坐标映射到格内像素坐标。
    final scale = side / 1024;
    final refStrokes = [
      for (final median in data.medians)
        [
          for (final point in median)
            math.Point<double>(point.x * scale, point.y * scale),
        ],
    ];
    final result = checkWriting(
      userStrokes: userStrokes,
      referenceMedians: refStrokes,
    );
    final repo = _repository;
    final target = _target;
    if (repo != null && target != null && _progress != null) {
      await _runWrite(
        () => repo.recordGeometryPass(
          lessonId: widget.lessonId,
          fingerprint: _fingerprint,
          targetId: target.id,
          passed: result.allPassed,
          operationId: 'geom-${DateTime.now().microsecondsSinceEpoch}',
          expectedRevision: _progress!.revision,
        ),
      );
    }
    if (_current) setState(() => _check = result);
  }

  Future<void> _confirmByParent() async {
    final repo = _repository;
    final target = _target;
    if (repo == null || target == null || _progress == null) return;
    final passed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('家长确认'),
        content: Text('「${target.text}」写得好吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('还要练'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('写得好'),
          ),
        ],
      ),
    );
    if (passed == null || !_current) return;
    await _runWrite(
      () => repo.recordParentConfirm(
        lessonId: widget.lessonId,
        fingerprint: _fingerprint,
        targetId: target.id,
        passed: passed,
        day: _today,
        operationId: 'parent-${DateTime.now().microsecondsSinceEpoch}',
        expectedRevision: _progress!.revision,
      ),
      success: () {
        if (passed && _current) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('已记录，做得好！')));
        }
      },
    );
  }

  // ============ 音频 ============

  void _playCharacter() {
    final target = _target;
    if (target == null || target.text.isEmpty) return;
    if (!_current) return;
    final status = _audioStatus;
    if (_audioSession != null &&
        (status == NarrationStatus.playing ||
            status == NarrationStatus.preparing ||
            status == NarrationStatus.buffering)) {
      unawaited(_audioSession?.pause());
      return;
    }
    if (_audioSession != null && status == NarrationStatus.paused) {
      unawaited(_audioSession?.resume());
      return;
    }
    unawaited(_startAudio(target.text));
  }

  Future<void> _startAudio(String text) async {
    try {
      final session = _tts.startNarration(
        [text],
        bookId: widget.bookId,
        cache: _cache,
        onState: (state, id) {
          if (!_current || id != _activeSessionId) return;
          setState(() {
            if (state.status == NarrationStatus.completed ||
                state.status == NarrationStatus.stopped) {
              _audioSession = null;
              _activeSessionId = -1;
              _audioStatus = null;
            } else {
              _audioStatus = state.status;
            }
          });
        },
      );
      _audioSession = session;
      _activeSessionId = session.sessionId;
      setState(() => _audioStatus = NarrationStatus.preparing);
    } on Object {
      if (_current) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('语音暂时不可用')));
      }
    }
  }

  Future<void> _stopAudio() async {
    final session = _audioSession;
    if (session == null) return;
    _audioSession = null;
    _activeSessionId = -1;
    if (_current) setState(() => _audioStatus = null);
    try {
      await session.cancel();
    } on Object {
      // 停止音频失败不影响页面状态。
    }
  }

  Future<void> _openRecords() async {
    if (_busy || !_current || _openingRecords || _route?.isCurrent == false) {
      return;
    }
    _openingRecords = true;
    final generation = _loadId;
    final path = AppRoutes.textbookWritingRecordsOf(
      widget.bookId,
      widget.lessonId,
    );
    try {
      await _stopAudio();
      if (!mounted ||
          !_current ||
          _busy ||
          generation != _loadId ||
          _route?.isCurrent == false) {
        return;
      }
      await context.push<void>(path);
    } finally {
      _openingRecords = false;
    }
  }

  // ============ 画布尺寸 ============

  double get _canvasSide {
    final width = MediaQuery.sizeOf(context).width;
    return math.min(width - SpacingTokens.md * 2, 320);
  }

  // ============ build ============

  void _selectMode(_WritingMode mode) {
    if (_busy || !_current || _mode == mode) return;
    unawaited(_stopAudio());
    if (mode == _WritingMode.puzzle) _reveal?.stop();
    setState(() {
      _mode = mode;
      _playing = false;
    });
  }

  void _writeAfterPuzzle() {
    _selectMode(_WritingMode.write);
    _goTo(_strokeData == null ? WritingStage.free : WritingStage.trace);
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    if (_loading || target == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorView(),
      );
    }
    final labelStyle = Theme.of(context).textTheme.labelLarge!;
    final labelHeight =
        MediaQuery.textScalerOf(context).scale(labelStyle.fontSize!) *
        (labelStyle.height ?? 1);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        titleSpacing: SpacingTokens.sm,
        toolbarHeight: math.max(
          kToolbarHeight,
          labelHeight + SpacingTokens.sm * 4,
        ),
        title: SegmentedButton<_WritingMode>(
          key: const ValueKey('writing-mode'),
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            minimumSize: const Size(
              SpacingTokens.minTapTarget,
              SpacingTokens.minTapTarget,
            ),
            padding: const EdgeInsets.all(SpacingTokens.sm),
          ),
          segments: const [
            ButtonSegment(
              value: _WritingMode.write,
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('写一写', maxLines: 1),
              ),
            ),
            ButtonSegment(
              value: _WritingMode.puzzle,
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('拼一拼', maxLines: 1),
              ),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: _busy || !_current
              ? null
              : (selection) => _selectMode(selection.single),
        ),
        actions: [
          IconButton(
            key: const ValueKey('writing-records-entry'),
            onPressed: _busy || !_current ? null : _openRecords,
            tooltip: '练习记录',
            icon: const Icon(Icons.history_outlined),
          ),
          IconButton(
            onPressed: _playCharacter,
            tooltip: '朗读',
            icon: Icon(
              _audioStatus == NarrationStatus.playing
                  ? Icons.volume_up
                  : Icons.volume_up_outlined,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error case final message?)
              Padding(
                padding: const EdgeInsets.all(SpacingTokens.md),
                child: ColoredCard(
                  color: Theme.of(context).colorScheme.error,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(message),
                      if (_retry != null)
                        TextButton(
                          onPressed: _busy ? null : _retry,
                          child: const Text('重试'),
                        ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: _mode.index,
                children: [
                  ListView(
                    padding: const EdgeInsets.all(SpacingTokens.md),
                    children: [
                      _stepper(),
                      const SizedBox(height: SpacingTokens.md),
                      ..._stageContent(),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(SpacingTokens.md),
                    child: WritingJigsaw(
                      key: ValueKey((
                        widget.bookId,
                        widget.lessonId,
                        widget.targetId,
                      )),
                      character: target.text,
                      strokeData: _strokeData,
                      enabled:
                          !_busy && _current && _mode == _WritingMode.puzzle,
                      onCompleted: (attempt) => _recordStage(
                        WritingStageDone.puzzle,
                        attempt: attempt,
                      ),
                      onWrite: _writeAfterPuzzle,
                    ),
                  ),
                ],
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(SpacingTokens.md),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _errorView() => ListView(
    padding: const EdgeInsets.all(SpacingTokens.md),
    children: [
      ColoredCard(
        color: Theme.of(context).colorScheme.error,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_error ?? '加载失败'),
            if (_retry != null)
              TextButton(onPressed: _retry, child: const Text('重试')),
          ],
        ),
      ),
    ],
  );

  /// 时间轴式步骤条：当前步与已完成步用深色，未到达的用浅色。
  ///
  /// 已完成 = 顺序在 [当前步] 之前；因此「自己写」完成后「看一看」也是深色。
  Widget _stepper() {
    final theme = Theme.of(context);
    final hasData = _strokeData != null;
    final stages = hasData
        ? WritingStage.values
        : [WritingStage.free, WritingStage.check];
    final current = stages.indexOf(_stage);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: SpacingTokens.sm,
      runSpacing: SpacingTokens.xs,
      children: [
        for (var i = 0; i < stages.length; i++)
          _stepDot(theme, stages[i], done: i < current, active: i == current),
      ],
    );
  }

  Widget _stepDot(
    ThemeData theme,
    WritingStage stage, {
    required bool done,
    required bool active,
  }) {
    final reached = done || active;
    final color = reached
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: _busy ? null : () => _goTo(stage),
      borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: SpacingTokens.minTapTarget,
          minHeight: SpacingTokens.minTapTarget,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SpacingTokens.sm,
            vertical: SpacingTokens.xs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? Icons.circle : Icons.circle_outlined,
                size: SpacingTokens.sm,
                color: color,
              ),
              const SizedBox(height: SpacingTokens.xs),
              Text(
                stage.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _stageContent() => switch (_stage) {
    WritingStage.demonstrate => _demonstrateStage(),
    WritingStage.trace => _traceStage(),
    WritingStage.free => _freeStage(),
    WritingStage.check => _checkStage(),
  };

  List<Widget> _demonstrateStage() {
    final data = _strokeData;
    if (data == null) return const [];
    final theme = Theme.of(context);
    return [
      Center(
        child: SizedBox.square(
          dimension: _canvasSide,
          child: _reveal == null
              ? const SizedBox.shrink()
              : AnimatedBuilder(
                  animation: _reveal!,
                  builder: (context, _) => CustomPaint(
                    key: const ValueKey('writing-demo'),
                    painter: StrokeRevealPainter(
                      strokes: data.strokes,
                      medians: data.medians,
                      revealed: _playing
                          ? (_revealedStrokes < data.strokeCount
                                ? _revealedStrokes
                                : data.strokeCount)
                          : _revealedStrokes,
                      progress: _playing ? _reveal!.value : 1,
                      color: theme.colorScheme.onSurface,
                      gridColor: theme.colorScheme.outline,
                      side: _canvasSide,
                    ),
                  ),
                ),
        ),
      ),
      const SizedBox(height: SpacingTokens.md),
      Text(
        '共 ${data.strokeCount} 笔',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: SpacingTokens.sm),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () => _stepReveal(-1),
            tooltip: '上一笔',
            icon: const Icon(Icons.skip_previous),
          ),
          IconButton.filled(
            onPressed: () {
              if (_playing) {
                _reveal?.stop();
                setState(() => _playing = false);
              } else {
                _restartReveal();
              }
            },
            tooltip: _playing ? '暂停' : '重播',
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          ),
          IconButton(
            onPressed: () => _stepReveal(1),
            tooltip: '下一笔',
            icon: const Icon(Icons.skip_next),
          ),
        ],
      ),
      const SizedBox(height: SpacingTokens.md),
      FilledButton(
        onPressed: () => _goTo(WritingStage.trace),
        child: const Text('开始描红'),
      ),
    ];
  }

  List<Widget> _traceStage() {
    final data = _strokeData;
    if (data == null) return const [];
    return [
      Center(
        child: WritingCanvas(
          key: const ValueKey('writing-trace'),
          strokes: _traced,
          enabled: !_busy && _current,
          onStrokesChanged: (next) => setState(() => _traced = next),
          referenceStrokes: data.strokes,
          traceOpacity: 0.22,
          side: _canvasSide,
        ),
      ),
      const SizedBox(height: SpacingTokens.sm),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    if (_traced.isEmpty) return;
                    setState(() {
                      _traced = _traced.sublist(0, _traced.length - 1);
                    });
                  },
            child: const Text('撤销一笔'),
          ),
          const SizedBox(width: SpacingTokens.sm),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _traced = [];
                    _traceStartedAt = DateTime.now();
                  }),
            child: const Text('清空'),
          ),
        ],
      ),
      const SizedBox(height: SpacingTokens.sm),
      FilledButton(
        onPressed: _busy ? null : _finishTrace,
        child: const Text('描完了，自己写'),
      ),
    ];
  }

  List<Widget> _freeStage() {
    final data = _strokeData;
    return [
      Center(
        child: WritingCanvas(
          key: const ValueKey('writing-free'),
          strokes: _free,
          enabled: !_busy && _current,
          onStrokesChanged: (next) {
            setState(() => _free = next);
          },
          showCharacter: data == null ? _target!.text : null,
          side: _canvasSide,
        ),
      ),
      const SizedBox(height: SpacingTokens.sm),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    if (_free.isEmpty) return;
                    setState(() => _free = _free.sublist(0, _free.length - 1));
                  },
            child: const Text('撤销一笔'),
          ),
          const SizedBox(width: SpacingTokens.sm),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _free = [];
                    _freeStartedAt = DateTime.now();
                  }),
            child: const Text('清空'),
          ),
        ],
      ),
      const SizedBox(height: SpacingTokens.sm),
      FilledButton(
        onPressed: _busy
            ? null
            : () async {
                await _recordStage(
                  WritingStageDone.free,
                  onSaved: () {
                    if (_free.isNotEmpty) _goTo(WritingStage.check);
                  },
                );
              },
        child: const Text('写好了，看一看'),
      ),
      if (_strokeData == null) ...[
        const SizedBox(height: SpacingTokens.md),
        Text(
          '这个字暂时没有笔顺数据，可以自由书写。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ];
  }

  List<Widget> _checkStage() {
    final theme = Theme.of(context);
    final data = _strokeData;
    final result = _check;
    final record = _record;
    final previewSide = (_canvasSide - SpacingTokens.lg) / 2;
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            children: [
              Text('参考', style: theme.textTheme.labelMedium),
              const SizedBox(height: SpacingTokens.xs),
              MiniTianziGrid(
                referenceStrokes: data?.strokes,
                character: data == null ? _target!.text : null,
                side: previewSide,
              ),
            ],
          ),
          const SizedBox(width: SpacingTokens.lg),
          Column(
            children: [
              Text('我写的', style: theme.textTheme.labelMedium),
              const SizedBox(height: SpacingTokens.xs),
              WritingCanvas(
                strokes: _free,
                enabled: false,
                side: previewSide,
                strokesSide: _canvasSide,
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: SpacingTokens.md),
      if (data == null)
        ColoredCard(
          color: theme.colorScheme.secondary,
          child: const Text('这个字暂时没有笔顺数据，请家长看一看写得对不对。'),
        )
      else if (result != null) ...[
        if (result.allPassed)
          ColoredCard(
            color: theme.colorScheme.primary,
            child: const Text('笔顺和笔画都对啦，写得很好！'),
          )
        else
          ColoredCard(
            color: theme.colorScheme.secondary,
            child: Text(_faultMessage(result)),
          ),
      ] else
        FilledButton(
          onPressed: _busy ? null : _runCheck,
          child: const Text('核对笔顺'),
        ),
      const SizedBox(height: SpacingTokens.md),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy
                  ? null
                  : () {
                      setState(() {
                        _free = [];
                        _freeStartedAt = null;
                      });
                      _goTo(WritingStage.free);
                    },
              child: const Text('重写'),
            ),
          ),
          const SizedBox(width: SpacingTokens.md),
          Expanded(
            child: FilledButton(
              key: const ValueKey('writing-parent-confirm'),
              onPressed: _busy ? null : _confirmByParent,
              child: Text(
                (record?.parentConfirms ?? 0) > 0 ? '请家长再看一次' : '写得好✓',
              ),
            ),
          ),
        ],
      ),
      if ((record?.parentConfirms ?? 0) > 0) ...[
        const SizedBox(height: SpacingTokens.sm),
        Text(
          '家长已确认 ${record!.parentConfirms} 次'
          '${record.lastParentDay == null ? '' : '（${record.lastParentDay}）'}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    ];
  }

  String _faultMessage(WritingCheckResult result) {
    if (result.fault == StrokeFault.strokesCount) {
      return '这个字有 ${result.expectedStrokes} 笔，你写了 '
          '${result.actualStrokes} 笔，再数一数笔画。';
    }
    final index = (result.firstBadStroke ?? 0) + 1;
    return switch (result.fault) {
      StrokeFault.direction => '第 $index 笔的方向不太对，再试一次。',
      StrokeFault.startPoint => '第 $index 笔的起笔位置不太对，再试一次。',
      StrokeFault.endPoint => '第 $index 笔的收笔位置不太对，再试一次。',
      StrokeFault.shape => '第 $index 笔的形状不太对，再试一次。',
      StrokeFault.length => '第 $index 笔长了一点或短了一点，再试一次。',
      _ => '再看一遍笔顺，慢慢来。',
    };
  }

  // ============ 生命周期 ============

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
  void didUpdateWidget(covariant WritingPracticePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId != widget.bookId ||
        oldWidget.lessonId != widget.lessonId ||
        oldWidget.targetId != widget.targetId) {
      unawaited(_stopAudio());
      _mode = _WritingMode.write;
      _stage = WritingStage.demonstrate;
      _traced = [];
      _free = [];
      _check = null;
      _freeStartedAt = null;
      _traceStartedAt = null;
      unawaited(_reload());
    }
  }

  @override
  void didPushNext() => unawaited(_stopAudio());
  @override
  void didPop() => unawaited(_stopAudio());
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        state != AppLifecycleState.inactive) {
      unawaited(_stopAudio());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _loadId++;
    _reveal?.dispose();
    widget.routeObserver?.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_restore?.cancel());
    unawaited(_profileChanges?.cancel());
    unawaited(_stopAudio());
    super.dispose();
  }
}
