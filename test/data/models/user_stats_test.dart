// test/data/models/user_stats_test.dart
//
// 单元测试：UserStats 模型。

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/user_stats.dart';

void main() {
  group('UserStats', () {
    test('默认值正确', () {
      final stats = UserStats(profileId: 'default');
      expect(stats.totalStars, 0);
      expect(stats.level, 0);
      expect(stats.levelName, '童生');
      expect(stats.mathAccuracy, 0.0);
    });

    test('levelName 映射正确', () {
      final stats = UserStats(profileId: 'default');
      expect(stats.levelName, '童生');

      stats.level = 1;
      expect(stats.levelName, '秀才');

      stats.level = 6;
      expect(stats.levelName, '状元');

      stats.level = 7;
      expect(stats.levelName, '诗仙');
    });

    test('mathAccuracy 计算正确', () {
      final stats = UserStats(
        profileId: 'default',
        mathTotalProblems: 100,
        mathTotalCorrect: 85,
      );
      expect(stats.mathAccuracy, closeTo(0.85, 0.001));
    });

    test('mathAccuracy 总题数为 0 时返回 0', () {
      final stats = UserStats(profileId: 'default');
      expect(stats.mathAccuracy, 0.0);
    });

    test('levelNames 包含 8 个等级', () {
      expect(UserStats.levelNames.length, 8);
      expect(UserStats.levelNames.first, '童生');
      expect(UserStats.levelNames.last, '诗仙');
    });
  });
}
