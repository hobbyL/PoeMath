// lib/features/poem/widgets/poem_handwriting_pad.dart
//
// 诗词默写手写板：单字田字格手写 + 笔顺几何核对。
//
// 判定哲学与教材「写一写」一致：几何比对只作教练提示，不设通过门槛——
// 核对不过可无限重写，也可「就这样」带错推进（记为未写出，由整句/
// 整诗判定与结果页纠正）。默写场景全程不展示参考字形，避免泄露答案；
// 无笔顺数据的字降级为自由书写「下一个」直通。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/domain/writing_geometry.dart';
import 'package:poemath/domain/writing_stroke_data.dart';
import 'package:poemath/features/textbook/writing/writing_canvas.dart';

/// 手写确认结果：笔迹随回调上交，父组件可在句子格里缩放预览。
class PoemHandwrittenChar {
  const PoemHandwrittenChar({
    required this.character,
    required this.strokes,
    required this.passed,
    this.checked = false,
    this.side = 240,
  });

  /// 格位上的目标字（非孩子实际写的字——默写不回显对错字形）。
  final String character;

  /// 孩子笔迹（板内局部坐标，side 见 [PoemHandwritingPad.side]）。
  final List<List<Offset>> strokes;

  /// 几何核对通过 / 自由书写直通为 true；「就这样」带错推进为 false。
  final bool passed;

  /// 是否经过几何核对（false = 无数据降级直通或带错推进）。
  final bool checked;
  final double side;

  Map<String, dynamic> toJson() => {
    'character': character,
    'passed': passed,
    'checked': checked,
    'side': side,
    'strokes': [
      for (final stroke in strokes)
        [
          for (final point in stroke) [point.dx, point.dy],
        ],
    ],
  };

  factory PoemHandwrittenChar.fromJson(Map<String, dynamic> json) {
    final side = (json['side'] as num).toDouble();
    if (!side.isFinite || side <= 0) throw const FormatException('手写画布尺寸无效');
    final strokes = (json['strokes'] as List)
        .map(
          (stroke) => (stroke as List).map((value) {
            final point = value as List;
            final x = (point[0] as num).toDouble();
            final y = (point[1] as num).toDouble();
            if (!x.isFinite || !y.isFinite) {
              throw const FormatException('手写笔迹坐标无效');
            }
            return Offset(x, y);
          }).toList(),
        )
        .toList();
    return PoemHandwrittenChar(
      character: json['character'] as String,
      strokes: strokes,
      passed: json['passed'] as bool,
      checked: json['checked'] as bool,
      side: side,
    );
  }
}

/// 单字手写默写板。
///
/// [strokeData] 为 null 时走降级路径：自由书写后「下一个」直通。
/// [onConfirmed] 保证每个字只回调一次；父组件据此推进并换新目标字
/// （用新 key 重建本组件，内部状态随之重置）。
class PoemHandwritingPad extends StatefulWidget {
  const PoemHandwritingPad({
    super.key,
    required this.character,
    required this.strokeData,
    required this.onConfirmed,
    this.side = 240,
    this.initialInk,
    this.onInkChanged,
  });

  final String character;
  final CharacterStrokeData? strokeData;
  final ValueChanged<PoemHandwrittenChar> onConfirmed;
  final double side;
  final PoemHandwrittenChar? initialInk;
  final ValueChanged<PoemHandwrittenChar>? onInkChanged;

  @override
  State<PoemHandwritingPad> createState() => _PoemHandwritingPadState();
}

class _PoemHandwritingPadState extends State<PoemHandwritingPad> {
  List<List<Offset>> _strokes = [];
  WritingCheckResult? _result;
  bool _answered = false; // 防重入：每字只回调一次

  @override
  void initState() {
    super.initState();
    final ink = widget.initialInk;
    if (ink != null && ink.character == widget.character) {
      _strokes = [
        for (final stroke in ink.strokes)
          [for (final point in stroke) point * (widget.side / ink.side)],
      ];
    }
  }

  @override
  void didUpdateWidget(covariant PoemHandwritingPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.side != widget.side) {
      _strokes = [
        for (final stroke in _strokes)
          [for (final point in stroke) point * (widget.side / oldWidget.side)],
      ];
    }
  }

  void _changeInk(List<List<Offset>> strokes) {
    setState(() {
      _strokes = strokes;
      _result = null;
    });
    widget.onInkChanged?.call(_emit(passed: false, checked: false));
  }

  /// medians（1024 字体画布坐标）缩放到格内像素坐标后比对，口径同写一写。
  void _runCheck() {
    final data = widget.strokeData;
    if (data == null || _answered || _strokes.isEmpty) return;
    final scale = widget.side / 1024;
    final result = checkWriting(
      userStrokes: [
        for (final stroke in _strokes)
          if (stroke.length > 1)
            [
              for (final point in stroke)
                math.Point<double>(point.dx, point.dy),
            ],
      ],
      referenceMedians: [
        for (final median in data.medians)
          [
            for (final point in median)
              math.Point<double>(point.x * scale, point.y * scale),
          ],
      ],
    );
    setState(() => _result = result);
    if (result.allPassed) {
      _answered = true;
      widget.onConfirmed(_emit(passed: true));
    }
  }

  /// 核对不过：放弃当前字，带错推进。
  void _giveUp() {
    if (_answered) return;
    _answered = true;
    widget.onConfirmed(_emit(passed: false, checked: false));
  }

  /// 无笔顺数据：自由书写直通（诚实自负，与写一写家长确认同哲学）。
  void _nextFreeform() {
    if (_answered || _strokes.isEmpty) return;
    _answered = true;
    widget.onConfirmed(_emit(passed: true, checked: false));
  }

  PoemHandwrittenChar _emit({required bool passed, bool? checked}) =>
      PoemHandwrittenChar(
        // 格位目标字随笔迹上交（格位预览与判定用），板上全程不显示。
        character: widget.character,
        strokes: List.of(_strokes.map((s) => List<Offset>.of(s))),
        passed: passed,
        checked: checked ?? passed,
        side: widget.side,
      );

  void _undoStroke() {
    if (_strokes.isEmpty) return;
    _changeInk(_strokes.sublist(0, _strokes.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.strokeData;
    final failed = _result != null && !_result!.allPassed;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        WritingCanvas(
          strokes: _strokes,
          onStrokesChanged: _changeInk,
          side: widget.side,
        ),
        const SizedBox(height: SpacingTokens.sm),
        if (!failed)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _strokes.isEmpty ? null : _undoStroke,
                child: const Text('撤销一笔'),
              ),
              const SizedBox(width: SpacingTokens.sm),
              TextButton(
                onPressed: _strokes.isEmpty ? null : () => _changeInk([]),
                child: const Text('清空'),
              ),
              const SizedBox(width: SpacingTokens.sm),
              FilledButton(
                onPressed: _strokes.isEmpty
                    ? null
                    : data == null
                    ? _nextFreeform
                    : _runCheck,
                child: Text(data == null ? '下一个' : '核对'),
              ),
            ],
          ),
        if (failed) ...[
          Text(
            _faultMessage(_result!),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _changeInk([]),
                  child: const Text('重写'),
                ),
              ),
              const SizedBox(width: SpacingTokens.md),
              Expanded(
                child: FilledButton(
                  onPressed: _giveUp,
                  child: const Text('就这样'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _faultMessage(WritingCheckResult result) {
    // 默写场景不回显目标字（避免泄露答案），只给笔画层面的教练提示。
    if (result.fault == StrokeFault.strokesCount) {
      return '这个字有 ${result.expectedStrokes} 笔，'
          '写了 ${result.actualStrokes} 笔，再试一次。';
    }
    final index = (result.firstBadStroke ?? 0) + 1;
    return switch (result.fault) {
      StrokeFault.direction => '第 $index 笔的方向不太对，再试一次。',
      StrokeFault.startPoint => '第 $index 笔的起笔位置不太对，再试一次。',
      StrokeFault.endPoint => '第 $index 笔的收笔位置不太对，再试一次。',
      StrokeFault.shape => '第 $index 笔的形状不太对，再试一次。',
      StrokeFault.length => '第 $index 笔长了一点或短了一点，再试一次。',
      _ => '再看一遍这个字，再试一次。',
    };
  }
}
