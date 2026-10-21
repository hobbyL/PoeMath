import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:mocktail/mocktail.dart';
import 'package:crypto/crypto.dart';

import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/domain/completion_sound.dart';
import 'package:poemath/domain/answer_feedback_sound.dart';

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
    await service.play(SoundEffect.wrong);
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

  test('答题反馈读取最新选择，其他事件保留原声音，试听不写设置', () async {
    final player = _MockAudioPlayer();
    final completions = StreamController<void>.broadcast();
    addTearDown(completions.close);
    when(() => player.onPlayerComplete).thenAnswer((_) => completions.stream);
    final paths = <String>[];
    when(() => player.play(any())).thenAnswer((call) async {
      paths.add((call.positionalArguments.single as AssetSource).path);
      completions.add(null);
    });
    when(player.dispose).thenAnswer((_) async {});
    final settings = SettingsRepository();
    final service = SoundService(settings, playerFactory: () => player);
    addTearDown(service.dispose);
    await service.play(SoundEffect.correct);
    await service.play(SoundEffect.wrong);
    await settings.setAnswerFeedbackSound(AnswerFeedbackSound.childVoice);
    await service.play(SoundEffect.correct);
    await service.play(SoundEffect.wrong);
    await service.play(SoundEffect.achievement);
    expect(paths, [
      'sounds/correct.wav',
      'sounds/wrong.wav',
      'sounds/child_correct.mp3',
      'sounds/child_wrong.mp3',
      'sounds/achievement.wav',
    ]);
    await settings.setSoundEnabled(false);
    await service.play(SoundEffect.wrong);
    expect(paths.length, 5);
    expect(
      await service.previewAnswerFeedback(AnswerFeedbackSound.classic),
      isTrue,
    );
    expect(paths.skip(5), ['sounds/correct.wav', 'sounds/wrong.wav']);
    expect(settings.answerFeedbackSound, AnswerFeedbackSound.childVoice);
    expect(settings.soundEnabled, isFalse);
  });

  test('播放异常不阻断结算，试听返回失败以便提示', () async {
    final player = _MockAudioPlayer();
    when(() => player.onPlayerComplete)
        .thenAnswer((_) => const Stream<void>.empty());
    when(() => player.play(any())).thenThrow(StateError('平台播放失败'));
    when(player.dispose).thenAnswer((_) async {});
    final service =
        SoundService(SettingsRepository(), playerFactory: () => player);
    addTearDown(service.dispose);
    await service.playCompletion();
    await service.play(SoundEffect.correct);
    expect(await service.previewCompletion(CompletionSound.arcade), isFalse);
    expect(
      await service.previewAnswerFeedback(AnswerFeedbackSound.childVoice),
      isFalse,
    );
  });

  test('成对试听等待答对播放完成后再播放答错，释放后不续播', () async {
    final player = _MockAudioPlayer();
    final completions = StreamController<void>.broadcast();
    addTearDown(completions.close);
    when(() => player.onPlayerComplete).thenAnswer((_) => completions.stream);
    final paths = <String>[];
    when(() => player.play(any())).thenAnswer((call) async {
      expect(completions.hasListener, isTrue);
      paths.add((call.positionalArguments.single as AssetSource).path);
    });
    when(player.dispose).thenAnswer((_) async {});
    final service =
        SoundService(SettingsRepository(), playerFactory: () => player);
    addTearDown(service.dispose);

    final preview = service.previewAnswerFeedback(AnswerFeedbackSound.classic);
    await pumpEventQueue();
    expect(paths, ['sounds/correct.wav']);
    expect(
      await service.previewAnswerFeedback(AnswerFeedbackSound.childVoice),
      isFalse,
    );
    completions.add(null);
    await pumpEventQueue();
    expect(paths, ['sounds/correct.wav', 'sounds/wrong.wav']);
    completions.add(null);
    expect(await preview, isTrue);
    expect(completions.hasListener, isFalse);

    final cancelled =
        service.previewAnswerFeedback(AnswerFeedbackSound.childVoice);
    await pumpEventQueue();
    expect(paths.last, 'sounds/child_correct.mp3');
    service.dispose();
    expect(await cancelled, isFalse);
    expect(paths, [
      'sounds/correct.wav',
      'sounds/wrong.wav',
      'sounds/child_correct.mp3',
    ]);
    expect(completions.hasListener, isFalse);
  });

  test('成对试听首段播放或完成事件失败时不播放第二段，允许重试', () async {
    final player = _MockAudioPlayer();
    final completions = StreamController<void>.broadcast();
    addTearDown(completions.close);
    when(() => player.onPlayerComplete).thenAnswer((_) => completions.stream);
    when(() => player.play(any())).thenThrow(StateError('素材不可用'));
    when(player.dispose).thenAnswer((_) async {});
    final service =
        SoundService(SettingsRepository(), playerFactory: () => player);
    addTearDown(service.dispose);
    expect(
      await service.previewAnswerFeedback(AnswerFeedbackSound.childVoice),
      isFalse,
    );
    verify(() => player.play(any())).called(1);
    expect(completions.hasListener, isFalse);

    when(() => player.play(any())).thenAnswer((_) async {});
    final retry = service.previewAnswerFeedback(AnswerFeedbackSound.childVoice);
    await pumpEventQueue();
    completions.addError(StateError('播放过程失败'));
    expect(await retry, isFalse);
    verify(() => player.play(any())).called(1);
    expect(completions.hasListener, isFalse);
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

  test('经典反馈 WAV 已打包，童声保留用户提供的原始 MP3 字节', () async {
    for (final path in [
      AnswerFeedbackSound.classic.correctAssetPath,
      AnswerFeedbackSound.classic.wrongAssetPath,
    ]) {
      final data = await rootBundle.load('assets/$path');
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
      expect(String.fromCharCodes(bytes.skip(8).take(4)), 'WAVE');
      expect(data.getUint16(20, Endian.little), 1);
    }
    for (final (path, originalHash) in [
      (
        AnswerFeedbackSound.childVoice.correctAssetPath,
        '92662f5d5ce5f9dcd5ab41ea1b759400cbbc1161c3c888cb8da5687094f4f0a7',
      ),
      (
        AnswerFeedbackSound.childVoice.wrongAssetPath,
        '6a682758d22908c7a475d2484d05895eafdd3fd8f931db82da5a69249d4bbb55',
      ),
    ]) {
      final data = await rootBundle.load('assets/$path');
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      expect(sha256.convert(bytes).toString(), originalHash);
    }
  });
}
