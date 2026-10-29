// lib/features/poem/widgets/poem_sentence_writing_sheet.dart
//
// 诗句手写默写板：整句显示为一排田字格（纸上默写观感），
// 孩子在活跃格逐字书写，写满一句由父组件判定。
//
// - 每格 = 目标字（汉字）或自动落位标点（灰显小字）；
// - 书写区复用 PoemHandwritingPad（田字格 + 笔顺核对），
//   与下方格位行联动：确认一字，格位即显示该字笔迹缩略；
// - 句子过长自动换行（Wrap），格宽随句长收缩（1-99 字可用）。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/domain/writing_stroke_data.dart';
import 'package:poemath/features/poem/widgets/poem_handwriting_pad.dart';
import 'package:poemath/features/textbook/writing/writing_canvas.dart';

/// 诗句手写默写板。
///
/// [targetChars] 为整句字符（含标点）；[confirmedChars] 为已确认笔迹
/// （父组件持有，重建时保序传入）；[onCharConfirmed] 每字回调一次。
class PoemSentenceWritingSheet extends StatelessWidget {
  const PoemSentenceWritingSheet({
    super.key,
    required this.targetChars,
    required this.confirmedChars,
    required this.currentStrokeData,
    required this.onCharConfirmed,
    this.maxBoardSide = 240,
  });

  final List<String> targetChars;
  final List<PoemHandwrittenChar> confirmedChars;
  final CharacterStrokeData? currentStrokeData;
  final ValueChanged<PoemHandwrittenChar> onCharConfirmed;
  final double maxBoardSide;

  /// 当前活跃格下标 = 已确认字数。
  int get _activeIndex => confirmedChars.length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hanziCount =
        targetChars.where((ch) => !_isPunct(ch)).length.clamp(1, 99);

    // 格宽随句长收缩；标点占位约半格。书写板保持独立可用尺寸。
    final slotSize = (math.min(
              (MediaQuery.sizeOf(context).width - SpacingTokens.lg * 2) /
                  (hanziCount * 1.15),
              72.0,
            ) +
            28)
        .clamp(30.0, 72.0);
    final currentChar =
        _activeIndex < targetChars.length ? targetChars[_activeIndex] : '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 格位行：整句一排田字格 ──
        Wrap(
          alignment: WrapAlignment.center,
          spacing: SpacingTokens.xs,
          runSpacing: SpacingTokens.xs,
          children: [
            for (var i = 0; i < targetChars.length; i++)
              _CharSlot(
                expected: targetChars[i],
                written: i < confirmedChars.length ? confirmedChars[i] : null,
                active: i == _activeIndex,
                size: slotSize,
                boardSide: maxBoardSide,
              ),
          ],
        ),
        const SizedBox(height: SpacingTokens.md),
        // ── 活跃格书写板 ──
        if (currentChar.isNotEmpty)
          Align(
            child: PoemHandwritingPad(
              key: ValueKey('sheet-pad-$_activeIndex-$currentChar'),
              character: currentChar,
              strokeData: currentStrokeData,
              side: maxBoardSide,
              onConfirmed: onCharConfirmed,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: Text(
              '本句完成',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  static bool _isPunct(String ch) =>
      ch != ch.trim() ||
      const {
        '，', '。', '！', '？', '、', '；', '：', '“', '”', '‘', '’',
        '（', '）', '《', '》', '【', '】', '…', '—', ',', '.', '!', '?',
        ':', ';', '"', "'", '(', ')',
      }.contains(ch);
}

/// 单个格位：空格（淡框）/ 活跃格（高亮框）/ 已写格（笔迹缩略）。
class _CharSlot extends StatelessWidget {
  const _CharSlot({
    required this.expected,
    required this.written,
    required this.active,
    required this.size,
    required this.boardSide,
  });

  /// 该格的目标字（标点则灰显小字自动落位）。
  final String expected;
  final PoemHandwrittenChar? written;
  final bool active;
  final double size;
  final double boardSide;

  bool get _isPunct => PoemSentenceWritingSheet._isPunct(expected);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final written = this.written;

    Widget content;
    if (written != null) {
      // 已写：笔迹缩略（无笔顺数据直通时也是真笔迹；空笔迹兜底显字形）。
      content = written.strokes.isEmpty
          ? Text(
              expected,
              style: TextStyle(fontSize: size * 0.6),
            )
          : FittedBox(
              child: SizedBox.square(
                dimension: boardSide,
                child: WritingCanvas(
                  strokes: written.strokes,
                  enabled: false,
                  side: boardSide,
                ),
              ),
            );
    } else if (_isPunct) {
      // 标点位：灰显小字（不手写，自动落位）。
      content = Text(
        expected,
        style: TextStyle(
          fontSize: size * 0.5,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    } else {
      content = const SizedBox.shrink();
    }

    final borderColor = active
        ? theme.colorScheme.primary
        : written != null
            ? theme.colorScheme.outline
            : theme.colorScheme.outline.withValues(alpha: 0.4);

    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(
          color: borderColor,
          width: active ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: content,
    );
  }
}
