import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  test('关闭音效时不初始化平台播放器', () async {
    final settings = SettingsRepository();
    await settings.setSoundEnabled(false);
    final service = SoundService(settings);
    addTearDown(service.dispose);

    expect(service.hasPlayer, isFalse);
    await service.play(SoundEffect.correct);
    expect(service.hasPlayer, isFalse);
  });
}
