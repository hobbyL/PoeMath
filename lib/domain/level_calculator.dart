// lib/domain/level_calculator.dart
//
// 等级计算器：根据总星星数映射到等级（0-7）。
// 等级体系：童生(0) → 秀才(1) → 举人(2) → 进士(3) → 探花(4) → 榜眼(5) → 状元(6) → 诗仙(7)

/// 纯函数：根据总星星数计算等级。
class LevelCalculator {
  const LevelCalculator._();

  /// 各等级所需的最低星星数。
  ///
  /// - 童生(0): 0 星
  /// - 秀才(1): 50 星
  /// - 举人(2): 150 星
  /// - 进士(3): 300 星
  /// - 探花(4): 500 星
  /// - 榜眼(5): 800 星
  /// - 状元(6): 1200 星
  /// - 诗仙(7): 2000 星
  static const List<int> thresholds = [0, 50, 150, 300, 500, 800, 1200, 2000];

  /// 根据总星星数计算当前等级（0-7）。
  static int calculate(int totalStars) {
    var level = 0;
    for (var i = thresholds.length - 1; i >= 0; i--) {
      if (totalStars >= thresholds[i]) {
        level = i;
        break;
      }
    }
    return level;
  }

  /// 距下一等级还需多少星星。若已满级则返回 0。
  static int starsToNextLevel(int totalStars) {
    final currentLevel = calculate(totalStars);
    if (currentLevel >= thresholds.length - 1) return 0;
    return thresholds[currentLevel + 1] - totalStars;
  }

  /// 当前等级的进度百分比（0.0 ~ 1.0）。
  static double progress(int totalStars) {
    final currentLevel = calculate(totalStars);
    if (currentLevel >= thresholds.length - 1) return 1.0;
    final currentMin = thresholds[currentLevel];
    final nextMin = thresholds[currentLevel + 1];
    return (totalStars - currentMin) / (nextMin - currentMin);
  }
}
