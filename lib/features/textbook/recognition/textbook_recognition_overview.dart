import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/tts/narration_audio_cache.dart';
import 'package:poemath/core/services/tts/narration_session.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/theme/color_tokens.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/textbook_recognition_content.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

class TextbookRecognitionOverview extends ConsumerStatefulWidget {
  const TextbookRecognitionOverview({
    super.key,
    required this.bookId,
    required this.lesson,
    this.routeObserver,
    this.onRecognize,
  });

  final String bookId;
  final TextbookCourseLesson lesson;
  final RouteObserver<ModalRoute<dynamic>>? routeObserver;
  final ValueChanged<String>? onRecognize;

  @override
  ConsumerState<TextbookRecognitionOverview> createState() => _OverviewState();
}

class _OverviewState extends ConsumerState<TextbookRecognitionOverview>
    with WidgetsBindingObserver, RouteAware {
  static const double _targetCardWidth = 160;
  static const int _minimumColumns = 2;
  static const int _maximumColumns = 4;

  late final TtsService _tts;
  late final NarrationAudioCache _cache;
  NarrationSession? _session;
  NarrationStatus? _status;
  String? _activeTargetId;
  String? _activeAudioKey;
  String? _audioError;
  ModalRoute<dynamic>? _route;
  int _activeSessionId = -1;
  bool _changingControl = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _tts = ref.read(ttsServiceProvider);
    _cache = ref.read(textbookFileServiceProvider).narrationCache;
    WidgetsBinding.instance.addObserver(this);
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
  void didUpdateWidget(covariant TextbookRecognitionOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId != widget.bookId ||
        oldWidget.lesson.id != widget.lesson.id) {
      unawaited(_stopAudio());
    }
  }

  bool get _current => mounted && !_disposed;

  void _startAudio({
    required TextbookCourseVocabulary target,
    required String audioKey,
    required String text,
  }) {
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
              _session = null;
              _activeSessionId = -1;
              _activeTargetId = null;
              _activeAudioKey = null;
              _status = null;
            } else {
              _status = state.status;
              if (state.status == NarrationStatus.failed) {
                _audioError = state.message ?? '语音播放失败，可以重试';
              }
            }
          });
        },
      );
      _session = session;
      _activeSessionId = session.sessionId;
      setState(() {
        _activeTargetId = target.id;
        _activeAudioKey = audioKey;
        _status = NarrationStatus.preparing;
        _audioError = null;
      });
    } on Object {
      setState(() => _audioError = '语音暂时不可用，可以重试');
    }
  }

  Future<void> _controlAudio({
    required TextbookCourseVocabulary target,
    required String audioKey,
    required String text,
  }) async {
    if (_changingControl) return;
    _changingControl = true;
    try {
      final currentTarget = _activeAudioKey == audioKey;
      final session = _session;
      if (!currentTarget || session == null) {
        _startAudio(target: target, audioKey: audioKey, text: text);
      } else if (_status == NarrationStatus.failed) {
        setState(() => _audioError = null);
        session.retry();
      } else if (_status == NarrationStatus.paused) {
        await session.resume();
      } else {
        await session.pause();
      }
    } on Object {
      if (_current) setState(() => _audioError = '语音操作失败，可以重试');
    } finally {
      _changingControl = false;
    }
  }

  Future<void> _stopAudio() async {
    final session = _session;
    final ownsService =
        session != null && session.sessionId == _tts.currentSessionId;
    _session = null;
    _activeSessionId = -1;
    if (_current) {
      setState(() {
        _activeTargetId = null;
        _activeAudioKey = null;
        _status = null;
      });
    }
    try {
      if (ownsService) {
        await _tts.stop();
      } else {
        await session?.cancel();
      }
    } on Object {/* 页面退出不应被播放器清理失败阻塞。 */}
  }

  String _audioHint({
    required String audioKey,
    required String text,
  }) {
    if (_activeAudioKey != audioKey) return '点击朗读$text';
    return switch (_status) {
      NarrationStatus.paused => '点击继续播放$text',
      NarrationStatus.failed => '点击重试朗读$text',
      NarrationStatus.preparing ||
      NarrationStatus.buffering ||
      NarrationStatus.playing =>
        '点击暂停$text读音',
      _ => '点击朗读$text',
    };
  }

  String _audioKey(String targetId, String text) => '$targetId\u0000$text';

  Widget _card(
    BuildContext context,
    TextbookCourseVocabulary target,
    double width,
  ) {
    final theme = Theme.of(context);
    final active = _activeTargetId == target.id;
    final pinyin = recognitionCardPinyin(widget.lesson, target);
    final note = recognitionCardNote(widget.lesson, target);
    final characterAudioKey = _audioKey(target.id, target.text);
    final noteAudioKey =
        note == null ? null : _audioKey('${target.id}:note', note.text);
    final entryStyle = theme.textTheme.bodySmall!;
    final entryLabel = TextPainter(
      text: TextSpan(text: '去认字', style: entryStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final entryWidth = (entryLabel.width +
            SpacingTokens.md +
            SpacingTokens.xs +
            SpacingTokens.sm * 2)
        .clamp(0.0, width - SpacingTokens.sm);
    entryLabel.dispose();
    return SizedBox(
      width: width,
      child: ColoredCard(
        key: ValueKey('recognition-card-${target.id}'),
        color: active ? theme.colorScheme.secondary : theme.colorScheme.primary,
        backgroundOpacity: active ? 0.16 : 0.08,
        padding: EdgeInsets.zero,
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Semantics(
                container: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      button: true,
                      label:
                          '${target.text}，拼音${pinyin.isEmpty ? '未知' : pinyin}',
                      hint: _audioHint(
                        audioKey: characterAudioKey,
                        text: target.text,
                      ),
                      child: InkWell(
                        key: ValueKey('recognition-character-${target.id}'),
                        onTap: () => _controlAudio(
                          target: target,
                          audioKey: characterAudioKey,
                          text: target.text,
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            SpacingTokens.md + SpacingTokens.xs,
                            SpacingTokens.lg,
                            SpacingTokens.md + SpacingTokens.xs,
                            note == null && widget.onRecognize != null
                                ? SpacingTokens.minTapTarget + SpacingTokens.sm
                                : SpacingTokens.md,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                pinyin.isEmpty ? '—' : pinyin,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: SpacingTokens.sm),
                              AutoFitLine(
                                child: Text(
                                  target.text,
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  style:
                                      theme.textTheme.displayMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (note != null) ...[
                      const Divider(
                        height: 0,
                        indent: SpacingTokens.md,
                        endIndent: SpacingTokens.md,
                      ),
                      Semantics(
                        button: true,
                        label: note.text,
                        hint: _audioHint(
                          audioKey: noteAudioKey!,
                          text: note.text,
                        ),
                        child: InkWell(
                          key: ValueKey('recognition-note-${target.id}'),
                          onTap: () => _controlAudio(
                            target: target,
                            audioKey: noteAudioKey,
                            text: note.text,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              SpacingTokens.md + SpacingTokens.xs,
                              SpacingTokens.md,
                              SpacingTokens.md + SpacingTokens.xs,
                              SpacingTokens.lg,
                            ),
                            child: Text.rich(
                              TextSpan(
                                text: note.text,
                                children: [
                                  if (widget.onRecognize != null)
                                    WidgetSpan(
                                      child: SizedBox(
                                        height: SpacingTokens.lg,
                                        width: entryWidth.clamp(
                                          0.0,
                                          width -
                                              (SpacingTokens.md +
                                                      SpacingTokens.xs) *
                                                  2,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.onRecognize != null)
                PositionedDirectional(
                  end: 0,
                  bottom: 0,
                  child: SizedBox(
                    width: entryWidth,
                    child: TextButton(
                      key: ValueKey('recognition-practice-${target.id}'),
                      onPressed: () => widget.onRecognize!(target.id),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          SpacingTokens.minTapTarget,
                          SpacingTokens.minTapTarget,
                        ),
                        alignment: Alignment.bottomCenter,
                        padding: const EdgeInsets.fromLTRB(
                          SpacingTokens.sm,
                          0,
                          SpacingTokens.sm,
                          SpacingTokens.xs,
                        ),
                        foregroundColor: theme.brightness == Brightness.dark
                            ? Color.lerp(
                                ColorTokens.poemSeal,
                                theme.colorScheme.onSurface,
                                0.7,
                              )
                            : ColorTokens.poemSeal,
                        textStyle: entryStyle,
                      ),
                      child: Semantics(
                        label: '去认字，${target.text}',
                        excludeSemantics: true,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: Text('去认字', maxLines: 1)),
                            SizedBox(width: SpacingTokens.xs),
                            Icon(
                              Icons.chevron_right,
                              size: SpacingTokens.md,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final targets = widget.lesson.recognitionCharacters;
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = SpacingTokens.sm;
        final available = constraints.maxWidth;
        final columns = ((available + gap) / (_targetCardWidth + gap))
            .floor()
            .clamp(_minimumColumns, _maximumColumns);
        final cardWidth = (available - gap * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_audioError case final message?) ...[
              Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: SpacingTokens.sm),
            ],
            _MasonryLayout(
              key: const ValueKey('recognition-masonry'),
              columnCount: columns,
              gap: gap,
              children: [
                for (final target in targets) _card(context, target, cardWidth),
              ],
            ),
          ],
        );
      },
    );
  }

  @override
  void didPushNext() => unawaited(_stopAudio());

  @override
  void didPop() => unawaited(_stopAudio());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_stopAudio());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.routeObserver?.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopAudio());
    super.dispose();
  }
}

class _MasonryLayout extends MultiChildRenderObjectWidget {
  const _MasonryLayout({
    super.key,
    required this.columnCount,
    required this.gap,
    required super.children,
  });

  final int columnCount;
  final double gap;

  @override
  _RenderMasonry createRenderObject(BuildContext context) =>
      _RenderMasonry(columnCount: columnCount, gap: gap);

  @override
  void updateRenderObject(BuildContext context, _RenderMasonry renderObject) {
    renderObject
      ..columnCount = columnCount
      ..gap = gap;
  }
}

class _MasonryParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderMasonry extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _MasonryParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _MasonryParentData> {
  _RenderMasonry({required int columnCount, required double gap})
      : _columnCount = columnCount,
        _gap = gap;

  int _columnCount;
  double _gap;

  int get columnCount => _columnCount;
  set columnCount(int value) {
    if (_columnCount == value) return;
    _columnCount = value;
    markNeedsLayout();
  }

  double get gap => _gap;
  set gap(double value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _MasonryParentData) {
      child.parentData = _MasonryParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : constraints.minWidth;
    final columns = _columnCount.clamp(1, 8);
    final columnWidth =
        ((width - _gap * (columns - 1)) / columns).clamp(0.0, double.infinity);
    final columnHeights = List<double>.filled(columns, 0);
    var maxHeight = 0.0;

    var child = firstChild;
    while (child != null) {
      var shortestColumn = 0;
      for (var column = 1; column < columns; column++) {
        if (columnHeights[column] < columnHeights[shortestColumn]) {
          shortestColumn = column;
        }
      }
      child.layout(
        BoxConstraints.tightFor(width: columnWidth),
        parentUsesSize: true,
      );
      final y = columnHeights[shortestColumn];
      final parentData = child.parentData! as _MasonryParentData;
      parentData.offset = Offset(
        shortestColumn * (columnWidth + _gap),
        y,
      );
      columnHeights[shortestColumn] = y + child.size.height + _gap;
      maxHeight = maxHeight < columnHeights[shortestColumn]
          ? columnHeights[shortestColumn]
          : maxHeight;
      child = childAfter(child);
    }

    size = constraints.constrain(
      Size(width, maxHeight == 0 ? 0 : maxHeight - _gap),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
