// lib/core/widgets/confetti_overlay.dart
//
// 答题正确时的 confetti 粒子效果叠加层。
// 用法：在页面 Stack 中放入此 Widget，调用 controller.play() 触发。

import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

/// Confetti 叠加层 Widget。
///
/// 需要在页面 initState 中创建 [ConfettiController]，
/// 答题正确时调用 `controller.play()`，然后在延时后 `controller.stop()`。
class ConfettiOverlay extends StatelessWidget {
  const ConfettiOverlay({super.key, required this.controller});

  final ConfettiController controller;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConfettiWidget(
        confettiController: controller,
        blastDirection: pi / 2, // 向下
        blastDirectionality: BlastDirectionality.explosive,
        maxBlastForce: 20,
        minBlastForce: 8,
        emissionFrequency: 0.05,
        numberOfParticles: 20,
        gravity: 0.2,
        shouldLoop: false,
        colors: const [
          Color(0xFFFFC107), // 金色
          Color(0xFFFF5722), // 橙色
          Color(0xFF4CAF50), // 绿色
          Color(0xFF2196F3), // 蓝色
          Color(0xFFE91E63), // 粉色
        ],
      ),
    );
  }
}
