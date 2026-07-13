// test/data/repositories/settings_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  late SettingsRepository repo;

  setUp(() async {
    await setUpHiveForTesting();
    repo = SettingsRepository();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  group('SettingsRepository', () {
    group('themeMode', () {
      test('默认值为 system', () {
        expect(repo.themeMode, 'system');
      });

      test('setThemeMode 保存并读取', () async {
        await repo.setThemeMode('dark');
        expect(repo.themeMode, 'dark');

        await repo.setThemeMode('light');
        expect(repo.themeMode, 'light');
      });
    });

    group('soundEnabled', () {
      test('默认值为 true', () {
        expect(repo.soundEnabled, isTrue);
      });

      test('setSoundEnabled 保存并读取', () async {
        await repo.setSoundEnabled(false);
        expect(repo.soundEnabled, isFalse);
      });
    });

    group('hapticEnabled', () {
      test('默认值为 true', () {
        expect(repo.hapticEnabled, isTrue);
      });

      test('setHapticEnabled 保存并读取', () async {
        await repo.setHapticEnabled(false);
        expect(repo.hapticEnabled, isFalse);
      });
    });

    group('selectedGrade', () {
      test('默认值为 1', () {
        expect(repo.selectedGrade, 1);
      });

      test('setSelectedGrade 保存并读取', () async {
        await repo.setSelectedGrade(3);
        expect(repo.selectedGrade, 3);
      });
    });

    group('ttsSpeed', () {
      test('默认值为 0.5', () {
        expect(repo.ttsSpeed, 0.5);
      });

      test('setTtsSpeed 保存并读取', () async {
        await repo.setTtsSpeed(0.8);
        expect(repo.ttsSpeed, 0.8);
      });
    });

    group('pinyinVisible', () {
      test('默认值为 true', () {
        expect(repo.pinyinVisible, isTrue);
      });

      test('setPinyinVisible 保存并读取', () async {
        await repo.setPinyinVisible(false);
        expect(repo.pinyinVisible, isFalse);
      });
    });
  });
}
