// lib/math_engine/models/difficulty_level.dart
//
// 口算难度级别。

/// 口算练习难度级别。
enum DifficultyLevel {
  easy('简单', '基础题'),
  medium('中等', '标准题'),
  hard('困难', '挑战题');

  const DifficultyLevel(this.label, this.desc);
  final String label;
  final String desc;
}
