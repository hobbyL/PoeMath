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

  /// 自定义星星形状。
  Path _starPath(Size size) {
    final path = Path();
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outerR = size.width / 2;
    final innerR = outerR * 0.4;
    const points = 5;
    for (var i = 0; i < points * 2; i++) {
      final angle = (i * pi / points) - (pi / 2);
      final r = i.isEven ? outerR : innerR;
      final x = cx + r * cos(angle);
      final y = cy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 主粒子发射器：顶部中央，向下爆发
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: controller,
            blastDirection: pi / 2,
            blastDirectionality: BlastDirectionality.explosive,
            maxBlastForce: 30,
            minBlastForce: 10,
            emissionFrequency: 0.06,
            numberOfParticles: 30,
            gravity: 0.15,
            shouldLoop: false,
            createParticlePath: _starPath,
            colors: const [
              Color(0xFFFFC107), // 金色
              Color(0xFFFF5722), // 橙色
              Color(0xFF4CAF50), // 绿色
              Color(0xFF2196F3), // 蓝色
              Color(0xFFE91E63), // 粉色
              Color(0xFF9C27B0), // 紫色
              Color(0xFFFFEB3B), // 黄色
            ],
          ),
        ),
        // 左侧发射器
        Align(
          alignment: Alignment.topLeft,
          child: ConfettiWidget(
            confettiController: controller,
            blastDirection: -pi / 4, // 右下方向
            blastDirectionality: BlastDirectionality.explosive,
            maxBlastForce: 25,
            minBlastForce: 8,
            emissionFrequency: 0.08,
            numberOfParticles: 15,
            gravity: 0.2,
            shouldLoop: false,
            colors: const [
              Color(0xFFFFC107),
              Color(0xFF4CAF50),
              Color(0xFFE91E63),
              Color(0xFF9C27B0),
            ],
          ),
        ),
        // 右侧发射器
        Align(
          alignment: Alignment.topRight,
          child: ConfettiWidget(
            confettiController: controller,
            blastDirection: -3 * pi / 4, // 左下方向
            blastDirectionality: BlastDirectionality.explosive,
            maxBlastForce: 25,
            minBlastForce: 8,
            emissionFrequency: 0.08,
            numberOfParticles: 15,
            gravity: 0.2,
            shouldLoop: false,
            colors: const [
              Color(0xFFFF5722),
              Color(0xFF2196F3),
              Color(0xFFFFEB3B),
              Color(0xFF00BCD4),
            ],
          ),
        ),
      ],
    );
  }
}
