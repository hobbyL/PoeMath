// lib/features/poem/widgets/read_along_voice_status_button.dart
//
// 层级：features/poem/widgets
// 职责：诗词跟读的准备、录音和识别状态按钮及动画。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';

/// 跟读语音操作区的可视状态。
enum ReadAlongVoiceStatus {
  preparing,
  recording,
  processing,
}

/// 全宽跟读状态按钮，支持录音计时和减少动画设置。
class ReadAlongVoiceStatusButton extends StatefulWidget {
  const ReadAlongVoiceStatusButton({
    required this.status,
    required this.elapsedSeconds,
    required this.onPressed,
    super.key,
  });

  final ReadAlongVoiceStatus status;
  final int elapsedSeconds;
  final VoidCallback? onPressed;

  @override
  State<ReadAlongVoiceStatusButton> createState() =>
      _ReadAlongVoiceStatusButtonState();
}

class _ReadAlongVoiceStatusButtonState extends State<ReadAlongVoiceStatusButton>
    with SingleTickerProviderStateMixin {
  static const _animationDuration = Duration(milliseconds: 920);
  static const _transitionDuration = Duration(milliseconds: 220);

  late final AnimationController _animationController;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: _animationDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mediaQuery = MediaQuery.of(context);
    _reduceMotion =
        mediaQuery.disableAnimations || mediaQuery.accessibleNavigation;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant ReadAlongVoiceStatusButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _syncAnimation() {
    if (!_reduceMotion && !_animationController.isAnimating) {
      _animationController.repeat();
    } else if (_reduceMotion && _animationController.isAnimating) {
      _animationController.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRecording = widget.status == ReadAlongVoiceStatus.recording;
    final backgroundColor =
        isRecording ? theme.colorScheme.error : theme.colorScheme.primary;
    final foregroundColor =
        isRecording ? theme.colorScheme.onError : theme.colorScheme.onPrimary;

    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      label: _semanticLabel,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: widget.onPressed,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(
              SpacingTokens.minTapTarget + SpacingTokens.sm,
            ),
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            disabledBackgroundColor: backgroundColor,
            disabledForegroundColor: foregroundColor,
            animationDuration:
                _reduceMotion ? Duration.zero : _transitionDuration,
          ),
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              final phase = _reduceMotion ? 0.0 : _animationController.value;
              return _buildStatusContent(
                phase: phase,
                foregroundColor: foregroundColor,
              );
            },
          ),
        ),
      ),
    );
  }

  String get _semanticLabel {
    switch (widget.status) {
      case ReadAlongVoiceStatus.preparing:
        return '准备录音';
      case ReadAlongVoiceStatus.recording:
        return '录音中，已录制 ${widget.elapsedSeconds} 秒';
      case ReadAlongVoiceStatus.processing:
        return '识别中';
    }
  }

  Widget _buildStatusContent({
    required double phase,
    required Color foregroundColor,
  }) {
    switch (widget.status) {
      case ReadAlongVoiceStatus.preparing:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _VoiceDots(phase: phase, color: foregroundColor),
            const SizedBox(width: SpacingTokens.sm),
            const Text('准备录音'),
          ],
        );
      case ReadAlongVoiceStatus.recording:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _VoiceBars(phase: phase, color: foregroundColor),
            const SizedBox(width: SpacingTokens.sm),
            const Text('录音中'),
            const SizedBox(width: SpacingTokens.sm),
            Text('${widget.elapsedSeconds}秒'),
          ],
        );
      case ReadAlongVoiceStatus.processing:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _VoiceDots(phase: phase, color: foregroundColor),
            const SizedBox(width: SpacingTokens.sm),
            const Text('识别中'),
          ],
        );
    }
  }
}

class _VoiceBars extends StatelessWidget {
  const _VoiceBars({required this.phase, required this.color});

  static const _baseHeights = <double>[7, 14, 19, 14, 8];

  final double phase;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('read-along-voice-bars'),
      width: SpacingTokens.xl,
      height: SpacingTokens.md + SpacingTokens.xs,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var index = 0; index < _baseHeights.length; index++)
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(
                1,
                0.58 +
                    0.42 *
                        ((math.sin(
                                  phase * math.pi * 2 + index * 0.82,
                                ) +
                                1) /
                            2),
                1,
              ),
              child: Container(
                width: SpacingTokens.xs,
                height: _baseHeights[index],
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.84),
                  borderRadius: BorderRadius.circular(SpacingTokens.xs / 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VoiceDots extends StatelessWidget {
  const _VoiceDots({required this.phase, required this.color});

  final double phase;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('read-along-voice-dots'),
      width: SpacingTokens.lg,
      height: SpacingTokens.md,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var index = 0; index < 3; index++)
            Transform.translate(
              offset: Offset(
                0,
                -2.5 * ((math.sin(phase * math.pi * 2 + index * 0.72) + 1) / 2),
              ),
              child: Container(
                width: SpacingTokens.xs,
                height: SpacingTokens.xs,
                decoration: BoxDecoration(
                  color: color.withValues(
                    alpha: 0.42 +
                        0.58 *
                            ((math.sin(
                                      phase * math.pi * 2 + index * 0.72,
                                    ) +
                                    1) /
                                2),
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
