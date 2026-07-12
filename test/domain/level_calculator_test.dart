// test/domain/level_calculator_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/domain/level_calculator.dart';

void main() {
  group('LevelCalculator', () {
    test('calculate returns 0 for 0 stars', () {
      expect(LevelCalculator.calculate(0), 0);
    });

    test('calculate returns 0 for 49 stars', () {
      expect(LevelCalculator.calculate(49), 0);
    });

    test('calculate returns 1 (秀才) at 50 stars', () {
      expect(LevelCalculator.calculate(50), 1);
    });

    test('calculate returns 2 (举人) at 150 stars', () {
      expect(LevelCalculator.calculate(150), 2);
    });

    test('calculate returns 3 (进士) at 300 stars', () {
      expect(LevelCalculator.calculate(300), 3);
    });

    test('calculate returns 4 (探花) at 500 stars', () {
      expect(LevelCalculator.calculate(500), 4);
    });

    test('calculate returns 5 (榜眼) at 800 stars', () {
      expect(LevelCalculator.calculate(800), 5);
    });

    test('calculate returns 6 (状元) at 1200 stars', () {
      expect(LevelCalculator.calculate(1200), 6);
    });

    test('calculate returns 7 (诗仙) at 2000 stars', () {
      expect(LevelCalculator.calculate(2000), 7);
    });

    test('calculate returns 7 for very high stars', () {
      expect(LevelCalculator.calculate(99999), 7);
    });

    test('starsToNextLevel returns correct gap', () {
      expect(LevelCalculator.starsToNextLevel(0), 50); // 0→50
      expect(LevelCalculator.starsToNextLevel(30), 20); // 30→50
      expect(LevelCalculator.starsToNextLevel(50), 100); // 50→150
      expect(LevelCalculator.starsToNextLevel(100), 50); // 100→150
    });

    test('starsToNextLevel returns 0 at max level', () {
      expect(LevelCalculator.starsToNextLevel(2000), 0);
      expect(LevelCalculator.starsToNextLevel(5000), 0);
    });

    test('progress returns correct percentage', () {
      // Level 0: 0..49 → 0/50
      expect(LevelCalculator.progress(0), 0.0);
      expect(LevelCalculator.progress(25), 0.5);

      // Level 1: 50..149 → (stars-50)/100
      expect(LevelCalculator.progress(50), 0.0);
      expect(LevelCalculator.progress(100), 0.5);

      // Max level → 1.0
      expect(LevelCalculator.progress(2000), 1.0);
    });
  });
}
