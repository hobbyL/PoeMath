import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/domain/completion_sound.dart';

import '../../helpers/hive_test_helper.dart';

class _MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(AssetSource('')));
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
    await service.playCompletion();
    expect(service.hasPlayer, isFalse);
  });

  test('完成播放读取最新选择，试听可在关闭音效时播放且不修改设置', () async {
    final player = _MockAudioPlayer();
    final paths = <String>[];
    when(() => player.play(any())).thenAnswer((call) async {
      paths.add((call.positionalArguments.single as AssetSource).path);
    });
    when(player.dispose).thenAnswer((_) async {});
    final settings = SettingsRepository();
    final service = SoundService(settings, playerFactory: () => player);
    addTearDown(service.dispose);
    for (final sound in CompletionSound.values) {
      await settings.setCompletionSound(sound);
      await service.playCompletion();
    }
    expect(paths, [
      'sounds/completion_arcade.wav',
      'sounds/completion_pizzicato.wav',
      'sounds/completion_steel_drum.wav',
      'sounds/completion_ensemble.wav',
    ]);
    await settings.setSoundEnabled(false);
    await service.playCompletion();
    expect(paths.length, 4);
    expect(await service.previewCompletion(CompletionSound.arcade), isTrue);
    expect(paths.last, 'sounds/completion_arcade.wav');
    expect(settings.soundEnabled, isFalse);
    expect(settings.completionSound, CompletionSound.ensemble);
  });

  test('播放异常不阻断结算，试听返回失败以便提示', () async {
    final player = _MockAudioPlayer();
    when(() => player.play(any())).thenThrow(StateError('平台播放失败'));
    when(player.dispose).thenAnswer((_) async {});
    final service =
        SoundService(SettingsRepository(), playerFactory: () => player);
    addTearDown(service.dispose);
    await service.playCompletion();
    expect(await service.previewCompletion(CompletionSound.arcade), isFalse);
  });

  test('四个选择对应已打包的 PCM WAV', () async {
    for (final sound in CompletionSound.values) {
      final data = await rootBundle.load('assets/${sound.assetPath}');
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
      expect(String.fromCharCodes(bytes.skip(8).take(4)), 'WAVE');
      expect(data.getUint16(20, Endian.little), 1); // PCM
    }
  });
}
