// lib/features/textbook/writing/textbook_writing_overview.dart
//
// 层级：features/textbook/writing（写一写字卡总览，PRD R1）
// 职责：田字格字卡 + 拼音 + 进度小标 + 朗读 + 进入单字练习。
//
// 参照认一认字卡总览（`textbook_recognition_overview.dart`）：
// 瀑布流排布、TTS 生命周期状态机、Semantics 水平保持一致；
// 差异仅在卡面内容（田字格大字、进度小标、「去练字」入口）与数据源。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/tts/narration_audio_cache.dart';
import 'package:poemath/core/services/tts/narration_session.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/theme/color_tokens.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_writing_progress.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/textbook_recognition_review.dart';
import 'package:poemath/domain/textbook_writing_content.dart';
import 'package:poemath/domain/textbook_writing_review.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/writing/stroke_data_provider.dart';
import 'package:poemath/features/textbook/writing/writing_canvas.dart';
import 'package:poemath/features/textbook/writing/writing_providers.dart';

/// 写一写字卡总览：每张卡 = 拼音 + 田字格大字 + 进度小标 + 「去练字」。
///
/// 点击字身朗读该字（与认一认同款 TTS 状态机）；
/// [onPractice] 非空时卡片右下显示「去练字」入口。
class TextbookWritingOverview extends ConsumerStatefulWidget {
  const TextbookWritingOverview({
    super.key,
    required this.bookId,
    required this.lesson,
    this.routeObserver,
    this.onPractice,
  });

  final String bookId;
  final TextbookCourseLesson lesson;
  final RouteObserver<ModalRoute<dynamic>>? routeObserver;
  final ValueChanged<String>? onPractice;

  @override
  ConsumerState<TextbookWritingOverview> createState() =>
      _WritingOverviewState();
}

class _WritingOverviewState extends ConsumerState<TextbookWritingOverview>
    with WidgetsBindingObserver, RouteAware {
  static const double _cardWidth = 160;
  static const int _minimumColumns = 2;
  static const int _maximumColumns = 4;

  late final TtsService _tts;
  late final NarrationAudioCache _cache;
  NarrationSession? _session;
  NarrationStatus? _status;
  String? _activeTargetId;
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
  void didUpdateWidget(covariant TextbookWritingOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId != widget.bookId ||
        oldWidget.lesson.id != widget.lesson.id) {
      unawaited(_stopAudio());
    }
  }

  bool get _current => mounted && !_disposed;

  void _startAudio({required String targetId, required String text}) {
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
              _status = null;
            } else {
              _status = state.status;
            }
          });
        },
      );
      _session = session;
      _activeSessionId = session.sessionId;
      setState(() {
        _activeTargetId = targetId;
        _status = NarrationStatus.preparing;
      });
    } on Object {
      // 朗读失败不阻断练字入口；按钮提示回到「点击朗读」。
      if (!_current) return;
      setState(() {
        _activeTargetId = null;
        _status = null;
      });
    }
  }

  Future<void> _controlAudio({
    required String targetId,
    required String text,
  }) async {
    if (_changingControl) return;
    _changingControl = true;
    try {
      final session = _session;
      if (_activeTargetId != targetId || session == null) {
        _startAudio(targetId: targetId, text: text);
      } else if (_status == NarrationStatus.failed) {
        session.retry();
      } else if (_status == NarrationStatus.paused) {
        await session.resume();
      } else {
        await session.pause();
      }
    } on Object {
      if (_current) setState(() => _status = null);
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

  String _audioHint(String targetId, String text) {
    if (_activeTargetId != targetId) return '朗读$text';
    return switch (_status) {
      NarrationStatus.paused => '继续播放$text',
      NarrationStatus.failed => '重试朗读$text',
      NarrationStatus.preparing ||
      NarrationStatus.buffering ||
      NarrationStatus.playing =>
        '暂停$text读音',
      _ => '朗读$text',
    };
  }

  IconData _audioIcon(String targetId) {
    if (_activeTargetId != targetId) return Icons.volume_up_outlined;
    return switch (_status) {
      NarrationStatus.paused => Icons.play_arrow_rounded,
      NarrationStatus.failed => Icons.refresh_rounded,
      NarrationStatus.preparing ||
      NarrationStatus.buffering ||
      NarrationStatus.playing =>
        Icons.pause_rounded,
      _ => Icons.volume_up_outlined,
    };
  }

  static String _badgeLabel(WritingBadge badge) => switch (badge) {
        WritingBadge.none => '未练',
        WritingBadge.traced => '已描红',
        WritingBadge.written => '已自写',
      };

  static Color _badgeColor(ThemeData theme, WritingBadge badge) =>
      switch (badge) {
        WritingBadge.none => theme.colorScheme.onSurfaceVariant,
        WritingBadge.traced => theme.colorScheme.tertiary,
        WritingBadge.written => ColorTokens.success,
      };

  Widget _card(
    BuildContext context,
    WritingTarget target,
    WritingRecord? record,
    double width,
  ) {
    final theme = Theme.of(context);
    final active = _activeTargetId == target.id;
    final pinyin = target.pinyin;
    final badge = record?.badge ?? WritingBadge.none;
    final due = writingDueToday(record, recognitionDay(DateTime.now()));
    final badgeLabel = _badgeLabel(badge);
    final progressLabel = due ? '$badgeLabel，今日复习' : badgeLabel;
    final entryStyle = theme.textTheme.bodySmall!;
    final entryColor = theme.brightness == Brightness.dark
        ? Color.lerp(ColorTokens.poemSeal, theme.colorScheme.onSurface, 0.7)!
        : ColorTokens.poemSeal;
    final canPractice = widget.onPractice != null;
    void practice() => widget.onPractice!(target.id);
    return SizedBox(
      width: width,
      child: ColoredCard(
        key: ValueKey('writing-card-${target.id}'),
        color: active ? theme.colorScheme.secondary : theme.colorScheme.primary,
        backgroundOpacity: active ? 0.16 : 0.08,
        padding: EdgeInsets.zero,
        // 整卡进入练字：田字格是卡片最大的区域，只让「去练字」响应会
        // 让孩子的点按大多落空（用户反馈：点整个卡片都应能进入）。
        onTap: canPractice ? practice : null,
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                container: true,
                label:
                    '${target.text}，拼音${pinyin.isEmpty ? '未知' : pinyin}，$progressLabel',
                hint: canPractice ? '打开练字' : null,
                child: Padding(
                  key: ValueKey('writing-character-${target.id}'),
                  padding: const EdgeInsets.fromLTRB(
                    SpacingTokens.sm,
                    SpacingTokens.sm,
                    SpacingTokens.sm,
                    SpacingTokens.xs,
                  ),
                  child: _CardGrid(
                    key: ValueKey('writing-grid-${target.id}'),
                    character: target.text,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SpacingTokens.md,
                  0,
                  SpacingTokens.sm,
                  SpacingTokens.xs,
                ),
                // 进度、朗读与入口同一行：左「未练」右「去练字」。
                //
                // 「去练字」在整卡可点后只是视觉指引，不再做独立按钮：
                // 卡片最窄时（320pt 两倍字号）放不下 44pt 按钮 + 44pt 喇叭，
                // 右侧另起一列又会被挤断行。
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        excludeSemantics: true,
                        label: progressLabel,
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                badgeLabel,
                                key: ValueKey('writing-badge-${target.id}'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: _badgeColor(theme, badge),
                                ),
                              ),
                            ),
                            if (due) ...[
                              const SizedBox(width: SpacingTokens.xs),
                              Flexible(
                                child: Text(
                                  '今日复习',
                                  key: ValueKey('writing-due-${target.id}'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: entryColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    // 朗读独立成小按钮：整卡点击已用于进入练字，
                    // 读音仍要能单独触发（与认一认卡片朗读能力对齐）。
                    IconButton(
                      key: ValueKey('writing-audio-${target.id}'),
                      onPressed: () => _controlAudio(
                        targetId: target.id,
                        text: target.text,
                      ),
                      tooltip: _audioHint(target.id, target.text),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: SpacingTokens.minTapTarget,
                        height: SpacingTokens.minTapTarget,
                      ),
                      iconSize: SpacingTokens.md + SpacingTokens.xs,
                      color: theme.colorScheme.onSurfaceVariant,
                      icon: Icon(_audioIcon(target.id)),
                    ),
                    if (canPractice)
                      Expanded(
                        child: Semantics(
                          excludeSemantics: true,
                          label: '去练字，${target.text}',
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: AutoFitLine(
                              child: Row(
                                key: ValueKey('writing-practice-${target.id}'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '去练字',
                                    maxLines: 1,
                                    style: entryStyle.copyWith(
                                      color: entryColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: SpacingTokens.xs),
                                  Icon(
                                    Icons.chevron_right,
                                    size: SpacingTokens.md,
                                    color: entryColor,
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
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pack = ref.watch(textbookCourseProvider(widget.bookId)).valueOrNull;
    final strokes = ref.watch(writingStrokeDataProvider).valueOrNull;
    final progress = ref.watch(textbookWritingProgressProvider(widget.bookId));
    final targets = pack == null
        ? const <WritingTarget>[]
        : writingTargets(
            pack,
            widget.lesson,
            hasStrokeData: strokes?.hasStrokeDataSync ?? _noStrokeData,
          );
    if (targets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
        child: Text(
          '本课暂无会写字。',
          key: const ValueKey('writing-empty'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final records = progress.valueOrNull?.records;
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = SpacingTokens.sm;
        final available = constraints.maxWidth;
        final columns = ((available + gap) / (_cardWidth + gap))
            .floor()
            .clamp(_minimumColumns, _maximumColumns);
        return MasonryLayout(
          key: const ValueKey('writing-masonry'),
          columnCount: columns,
          gap: gap,
          children: [
            for (final target in targets)
              _card(
                context,
                target,
                records?[WritingProgress.targetKey(
                  widget.lesson.id,
                  target.id,
                )],
                (available - gap * (columns - 1)) / columns,
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

bool _noStrokeData(String character) => false;

/// 字卡田字格：复用练习页的 [TianziGridPainter] 画米字线，
/// 字符按格子边长推导字号（总览只需"看到这个字"，不描轮廓）。
///
/// 早先用固定 `displayMedium`（28px）字号 + `AutoFitLine`（只缩不放），
/// 在 160pt 宽的卡片里字只有格子的五分之一，用户反馈「格子很大、字很小」。
/// 现在与练习页降级字形一致，取格子边长的 72%。
class _CardGrid extends StatelessWidget {
  const _CardGrid({super.key, required this.character});

  final String character;

  /// 字符墨迹占田字格边长的比例，与练习页 `_paintCharacterFallback` 保持一致。
  static const double _characterScale = 0.72;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.biggest.shortestSide;
          return CustomPaint(
            painter: TianziGridPainter(
              gridColor: theme.colorScheme.outline.withValues(alpha: 0.6),
            ),
            child: Center(
              // AutoFitLine 兜底：无障碍大字号时仍等比缩回格内，不溢出。
              child: AutoFitLine(
                child: Text(
                  character,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontSize: side * _characterScale,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}