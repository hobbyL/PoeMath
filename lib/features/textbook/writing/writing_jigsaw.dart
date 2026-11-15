import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/domain/character_puzzle.dart';
import 'package:poemath/domain/writing_stroke_data.dart';
import 'package:poemath/features/textbook/writing/writing_path.dart';

/// 同一个完整字形切成不等大的纸片，拖动拼回去。保存由单字页负责。
class WritingJigsaw extends StatefulWidget {
  const WritingJigsaw({
    super.key,
    required this.character,
    required this.strokeData,
    required this.onCompleted,
    required this.onWrite,
    this.enabled = true,
  });

  final String character;
  final CharacterStrokeData? strokeData;
  final Future<bool> Function(String roundId, DateTime startedAt) onCompleted;
  final VoidCallback onWrite;
  final bool enabled;

  @override
  State<WritingJigsaw> createState() => _WritingJigsawState();
}

class _WritingJigsawState extends State<WritingJigsaw> {
  final _boardKey = GlobalKey();
  Path? _glyph;
  List<PuzzlePoint> _inkPoints = const [];
  CharacterPuzzleLayout? _layout;
  Set<int> _placed = {};
  int? _selected;
  String? _placementMessage;
  String _roundId = '';
  late DateTime _roundStartedAt;
  bool _showHint = true;
  bool _saving = false;
  bool _saved = false;
  bool _prepared = false;
  int _roundNumber = 0;

  bool get _complete =>
      _layout != null && _placed.length == _layout!.pieces.length;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _prepareGlyph();
  }

  @override
  void didUpdateWidget(covariant WritingJigsaw oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.character != widget.character ||
        oldWidget.strokeData != widget.strokeData) {
      _showHint = true;
      _prepared = false;
      _glyph = null;
      _layout = null;
    }
    if (widget.enabled && !_prepared) _prepareGlyph();
  }

  void _prepareGlyph() {
    _prepared = true;
    _glyph = null;
    _layout = null;
    _inkPoints = const [];
    final data = widget.strokeData;
    if (data == null || data.strokes.isEmpty) return;
    final outline = characterOutline(data.strokes);
    final bounds = outline.getBounds();
    if (bounds.isEmpty || !bounds.longestSide.isFinite) return;
    // 使用真实轮廓范围，完整保留少量超出原 1024 画布的笔画。
    final scale = 0.82 / bounds.longestSide;
    final normalized = outline.transform(
      Float64List.fromList([
        scale,
        0,
        0,
        0,
        0,
        scale,
        0,
        0,
        0,
        0,
        1,
        0,
        0.5 - bounds.center.dx * scale,
        0.5 - bounds.center.dy * scale,
        0,
        1,
      ]),
    );
    final points = <PuzzlePoint>[];
    const samples = 48;
    for (var y = 0; y < samples; y++) {
      for (var x = 0; x < samples; x++) {
        final point = Offset((x + 0.5) / samples, (y + 0.5) / samples);
        if (normalized.contains(point)) {
          points.add(math.Point(point.dx, point.dy));
        }
      }
    }
    if (points.length < 6) return;
    _glyph = normalized;
    _inkPoints = points;
    _newRound();
  }

  void _newRound() {
    _roundStartedAt = DateTime.now();
    _roundId =
        'jigsaw-${_roundStartedAt.microsecondsSinceEpoch}-${++_roundNumber}';
    final seed = _roundId.codeUnits.fold<int>(
      0,
      (value, code) => (value * 31 + code) & 0x7fffffff,
    );
    _layout = createCharacterPuzzle(inkPoints: _inkPoints, seed: seed);
    _placed = {};
    _selected = null;
    _placementMessage = null;
    _saved = false;
    _saving = false;
  }

  void _place(CharacterPuzzlePiece piece) {
    if (!widget.enabled || _saving || _placed.contains(piece.id)) return;
    setState(() {
      _placed = {..._placed, piece.id};
      _selected = null;
      _placementMessage = null;
    });
    if (_complete) unawaited(_saveCompletion());
  }

  Future<void> _saveCompletion() async {
    if (_saving || _saved || !widget.enabled || !_complete) return;
    final round = _roundId;
    setState(() => _saving = true);
    try {
      final saved = await widget.onCompleted(round, _roundStartedAt);
      if (mounted && round == _roundId) setState(() => _saved = saved);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '拼装完成记录保存失败',
        tag: 'TextbookWriting',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted && round == _roundId) setState(() => _saving = false);
    }
  }

  void _drop(DragTargetDetails<CharacterPuzzlePiece> details, double side) {
    if (!widget.enabled || _saving) return;
    final box = _boardKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    final piece = details.data;
    final layout = _layout;
    if (layout == null ||
        piece.id < 0 ||
        piece.id >= layout.pieces.length ||
        !identical(layout.pieces[piece.id], piece)) {
      return;
    }
    final local = box.globalToLocal(details.offset);
    final expected = Offset(piece.bounds.left * side, piece.bounds.top * side);
    if ((local - expected).distance <=
        math.max(SpacingTokens.lg, side * 0.10)) {
      _place(piece);
    } else {
      _tryAgain();
    }
  }

  void _tryAgain() {
    if (mounted) setState(() => _placementMessage = '再挪一挪，让笔画接起来。');
  }

  void _tapBoard(TapUpDetails details, double side) {
    final selected = _selected;
    final layout = _layout;
    if (selected == null || layout == null || !widget.enabled) return;
    final point = math.Point(
      details.localPosition.dx / side,
      details.localPosition.dy / side,
    );
    if (layout.pieces[selected].contains(point)) {
      _place(layout.pieces[selected]);
    } else {
      _tryAgain();
    }
  }

  Widget _piece(CharacterPuzzlePiece piece, double side, ColorScheme scheme) {
    const trayScale = 0.58;
    final width = piece.bounds.width * side;
    final height = piece.bounds.height * side;
    final selected = _selected == piece.id;
    Widget paint(double boardSide) => SizedBox(
      width: piece.bounds.width * boardSide,
      height: piece.bounds.height * boardSide,
      child: CustomPaint(
        painter: _PiecePainter(
          piece: piece,
          glyph: _glyph!,
          boardSide: boardSide,
          paper: scheme.surfaceContainerHigh,
          ink: scheme.onSurface,
          edge: selected ? scheme.primary : scheme.outline,
        ),
      ),
    );
    final child = SizedBox(
      width: math.max(SpacingTokens.minTapTarget, width * trayScale),
      height: math.max(SpacingTokens.minTapTarget, height * trayScale),
      child: Center(child: paint(side * trayScale)),
    );
    void select() => setState(() {
      _selected = selected ? null : piece.id;
      _placementMessage = _selected == null ? null : '点一下放置位置，也可以拖动碎片。';
    });
    return Semantics(
      label: '碎片 ${piece.id + 1}',
      hint: '拖到拼装区，或先选中再点放置位置',
      button: true,
      selected: selected,
      enabled: widget.enabled,
      onTap: widget.enabled ? select : null,
      child: ExcludeSemantics(
        child: Draggable<CharacterPuzzlePiece>(
          key: ValueKey('jigsaw-piece-${piece.id}'),
          data: piece,
          maxSimultaneousDrags: widget.enabled && !_saving ? 1 : 0,
          hitTestBehavior: HitTestBehavior.opaque,
          // 缩略碎片与反馈大小不同。固定反馈中心，不使用缩略图的按下坐标。
          dragAnchorStrategy: (_, _, _) => Offset(width / 2, height / 2),
          feedback: paint(side),
          childWhenDragging: Opacity(opacity: 0.25, child: child),
          onDragStarted: () => setState(() => _placementMessage = null),
          child: InkWell(
            onTap: widget.enabled ? select : null,
            borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = _layout;
    if (layout == null) {
      return AppEmptyState(
        key: const ValueKey('jigsaw-unavailable'),
        icon: Icons.extension_outlined,
        title: '这个字暂时没有拼装字形',
        description: '可以先练习自己写。',
        actions: [
          FilledButton(
            onPressed: widget.enabled ? widget.onWrite : null,
            child: const Text('自己写'),
          ),
        ],
      );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: SpacingTokens.sm,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                _complete
                    ? '拼好了！'
                    : '已拼 ${_placed.length}/${layout.pieces.length}',
                key: const ValueKey('jigsaw-progress'),
                style: theme.textTheme.titleMedium,
              ),
            ),
            Semantics(
              toggled: _showHint,
              child: TextButton.icon(
                key: const ValueKey('jigsaw-hint-toggle'),
                onPressed: widget.enabled
                    ? () => setState(() => _showHint = !_showHint)
                    : null,
                icon: Icon(
                  _showHint
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                label: Text(_showHint ? '关闭提示' : '开启提示'),
              ),
            ),
          ],
        ),
        const SizedBox(height: SpacingTokens.sm),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 碎片区单独滚动，始终保留拼装区，短屏不必把整字滚出视口。
              final side = math.min(
                320.0,
                math.min(constraints.maxWidth, constraints.maxHeight * 0.58),
              );
              return Column(
                children: [
                  Center(child: _board(layout, side, scheme)),
                  const SizedBox(height: SpacingTokens.md),
                  Expanded(child: _tray(layout, side, theme)),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: SpacingTokens.md),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: SpacingTokens.sm,
          runSpacing: SpacingTokens.sm,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('jigsaw-restart'),
              onPressed: widget.enabled && !_saving && (!_complete || _saved)
                  ? () => setState(_newRound)
                  : null,
              icon: const Icon(Icons.refresh),
              label: Text(_complete ? '再拼一次' : '重新拼装'),
            ),
            if (_complete && _saved)
              FilledButton(
                onPressed: widget.enabled ? widget.onWrite : null,
                child: const Text('去写一写'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _board(
    CharacterPuzzleLayout layout,
    double side,
    ColorScheme scheme,
  ) => DragTarget<CharacterPuzzlePiece>(
    onWillAcceptWithDetails: (details) =>
        widget.enabled &&
        !_saving &&
        details.data.id >= 0 &&
        details.data.id < layout.pieces.length &&
        !_placed.contains(details.data.id) &&
        identical(layout.pieces[details.data.id], details.data),
    onAcceptWithDetails: (details) => _drop(details, side),
    builder: (context, candidates, rejected) => GestureDetector(
      onTapUp: (details) => _tapBoard(details, side),
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        label: '${widget.character}的拼装区',
        child: SizedBox.square(
          key: _boardKey,
          dimension: side,
          child: CustomPaint(
            key: const ValueKey('jigsaw-board'),
            painter: WritingJigsawBoardPainter(
              glyph: _glyph!,
              layout: layout,
              placed: _placed,
              showHint: _showHint,
              paper: scheme.surfaceContainerLow,
              ink: scheme.onSurface,
              edge: candidates.isEmpty ? scheme.outline : scheme.primary,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _tray(CharacterPuzzleLayout layout, double side, ThemeData theme) {
    if (_complete) {
      if (_saved) return const SizedBox.shrink();
      return SingleChildScrollView(
        child: Column(
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                _saving ? '正在保存拼装记录…' : '拼装记录还没保存，请重试。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (!_saved && !_saving)
              TextButton.icon(
                key: const ValueKey('jigsaw-save-retry'),
                onPressed: widget.enabled ? _saveCompletion : null,
                icon: const Icon(Icons.refresh),
                label: const Text('重试保存'),
              ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      key: const ValueKey('jigsaw-tray'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_placementMessage case final message?) ...[
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SpacingTokens.sm),
          ],
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: SpacingTokens.md,
            runSpacing: SpacingTokens.sm,
            children: [
              for (final id in layout.trayOrder)
                if (!_placed.contains(id))
                  _piece(layout.pieces[id], side, theme.colorScheme),
            ],
          ),
        ],
      ),
    );
  }
}

Path _piecePath(CharacterPuzzlePiece piece) {
  final path = Path()..moveTo(piece.outline.first.x, piece.outline.first.y);
  for (final point in piece.outline.skip(1)) {
    path.lineTo(point.x, point.y);
  }
  return path..close();
}

class _PiecePainter extends CustomPainter {
  const _PiecePainter({
    required this.piece,
    required this.glyph,
    required this.boardSide,
    required this.paper,
    required this.ink,
    required this.edge,
  });
  final CharacterPuzzlePiece piece;
  final Path glyph;
  final double boardSide;
  final Color paper, ink, edge;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(boardSide);
    canvas.translate(-piece.bounds.left, -piece.bounds.top);
    final path = _piecePath(piece);
    canvas.drawPath(path, Paint()..color = paper);
    canvas.save();
    canvas.clipPath(path);
    canvas.drawPath(glyph, Paint()..color = ink);
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 / boardSide,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PiecePainter old) =>
      old.piece != piece ||
      old.glyph != glyph ||
      old.boardSide != boardSide ||
      old.paper != paper ||
      old.ink != ink ||
      old.edge != edge;
}

/// 整字提示和已吸附碎片共用同一字形与分片坐标。
class WritingJigsawBoardPainter extends CustomPainter {
  const WritingJigsawBoardPainter({
    required this.glyph,
    required this.layout,
    required this.placed,
    required this.showHint,
    required this.paper,
    required this.ink,
    required this.edge,
  });
  final Path glyph;
  final CharacterPuzzleLayout layout;
  final Set<int> placed;
  final bool showHint;
  final Color paper, ink, edge;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    canvas.save();
    canvas.scale(side);
    if (placed.length == layout.pieces.length) {
      canvas.drawPath(glyph, Paint()..color = ink);
    } else {
      if (showHint) {
        canvas.drawPath(glyph, Paint()..color = ink.withValues(alpha: 0.16));
      }
      for (final piece in layout.pieces) {
        if (!placed.contains(piece.id)) continue;
        final path = _piecePath(piece);
        canvas.drawPath(path, Paint()..color = paper);
        canvas.save();
        canvas.clipPath(path);
        canvas.drawPath(glyph, Paint()..color = ink);
        canvas.restore();
        canvas.drawPath(
          path,
          Paint()
            ..color = edge.withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1 / side,
        );
      }
    }
    canvas.restore();
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(WritingJigsawBoardPainter old) =>
      old.glyph != glyph ||
      old.layout != layout ||
      old.placed != placed ||
      old.showHint != showHint ||
      old.paper != paper ||
      old.ink != ink ||
      old.edge != edge;
}
