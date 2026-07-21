// lib/features/math/widgets/number_keypad.dart
//
// 儿童友好数字键盘组件。

import 'package:flutter/material.dart';
import 'package:poemath/core/theme/design_tokens.dart';

/// 儿童友好数字键盘，用于口算练习答题。
///
/// 特性：
/// - 前三行三列，最后一行按模式显示 3 或 4 个操作键
/// - 按钮 ≥56pt（逻辑像素）
/// - 0-9 数字 + 退格 + 提交
/// - 按下有轻微视觉反馈
/// - 可配置小数点或余数省略号，特殊输入模式仍保留提交键
class NumberKeypad extends StatelessWidget {
  const NumberKeypad({
    super.key,
    required this.onNumberTap,
    required this.onBackspace,
    required this.onSubmit,
    this.showDecimal = false,
    this.showEllipsis = false,
    this.submitEnabled = true,
  });

  /// 数字键回调（0-9）
  final ValueChanged<String> onNumberTap;

  /// 退格回调
  final VoidCallback onBackspace;

  /// 提交回调
  final VoidCallback onSubmit;

  /// 是否显示小数点（默认 false）
  final bool showDecimal;

  /// 是否显示省略号（用于余数模式，默认 false）
  final bool showEllipsis;

  /// 提交按钮是否可用
  final bool submitEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 1-9 在前 3 行，最后一行始终保留提交按钮。
    // showEllipsis 优先级最高（余数模式），showDecimal 次之（小数模式）。
    final specialKey = showEllipsis
        ? '…'
        : showDecimal
            ? '.'
            : null;

    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      [
        '⌫',
        '0',
        if (specialKey != null) specialKey,
        '✓',
      ],
    ];

    return Container(
      padding: const EdgeInsets.all(SpacingTokens.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SpacingTokens.radiusLarge),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: keys.map((row) {
            return Padding(
              padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
              child: Row(
                children: row.map((key) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SpacingTokens.xs,
                      ),
                      child: _buildKey(context, key),
                    ),
                  );
                }).toList(),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildKey(BuildContext context, String key) {
    final theme = Theme.of(context);

    // 特殊键：退格、提交
    final isBackspace = key == '⌫';
    final isSubmit = key == '✓';

    final buttonColor = isSubmit
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHigh;

    final textColor =
        isSubmit ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    return Material(
      color: buttonColor,
      borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
      child: InkWell(
        onTap: () {
          if (isBackspace) {
            onBackspace();
          } else if (isSubmit) {
            if (submitEnabled) onSubmit();
          } else {
            onNumberTap(key);
          }
        },
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          child: isBackspace
              ? Icon(
                  Icons.backspace_outlined,
                  color: textColor,
                  size: 24,
                )
              : isSubmit
                  ? Icon(
                      Icons.check_rounded,
                      color: textColor,
                      size: 28,
                    )
                  : Text(
                      key,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
        ),
      ),
    );
  }
}
