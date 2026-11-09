// 使用项目自有 MP3 和模拟云响应，通过真实平台播放器验收，不访问生产服务。
import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:poemath/core/services/tts/narration_audio_cache.dart';
import 'package:poemath/core/services/tts/narration_player.dart';
import 'package:poemath/core/services/tts/narration_session.dart';
import 'package:poemath/core/services/tts/tts_models.dart';
import 'package:poemath/core/services/tts_service.dart';

import '../test/helpers/narration_fakes.dart';

class _NoSystemEngine extends NarrationEngine {
  @override
  Future<dynamic> setLanguage(String language) async =>
      throw StateError('此验收仅允许使用云音频');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('诗词云 MP3 与教材缓存 MP3 均由真实播放器解码并推进播放', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('云朗读播放验收'))),
    );
    final bytes = (await rootBundle.load('assets/sounds/child_correct.mp3'))
        .buffer
        .asUint8List();
    final cloud = NarrationCloud()..generate = (_) async => bytes;
    final folder = await Directory.systemTemp.createTemp('cloud-playback-');
    final cache = NarrationAudioCache(directoryProvider: () async => folder);
    final nativePoem = AudioPlayer();
    final nativeBook = AudioPlayer();
    final positions = <String, int>{'poem': 0, 'book': 0};
    final subscriptions = <StreamSubscription<Duration>>[
      nativePoem.onPositionChanged.listen((position) {
        if (position.inMilliseconds > positions['poem']!) {
          positions['poem'] = position.inMilliseconds;
        }
      }),
      nativeBook.onPositionChanged.listen((position) {
        if (position.inMilliseconds > positions['book']!) {
          positions['book'] = position.inMilliseconds;
        }
      }),
    ];
    final service = TtsService(
      NarrationSettings()..enabled = true,
      flutterTts: _NoSystemEngine(),
      cloudClient: cloud.client,
      cloudPlayer: AudioplayersCloudAudioPlayer(player: nativePoem),
      narrationPlayerFactory: () =>
          AudioplayersNarrationPlayer(player: nativeBook),
    );
    try {
      Future<void> finish(Future<void> operation) async {
        var complete = false;
        Object? error;
        unawaited(
          operation.then<void>(
            (_) => complete = true,
            onError: (Object e) {
              error = e;
              complete = true;
            },
          ),
        );
        for (var i = 0; i < 400 && !complete; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(complete, isTrue, reason: '播放应在 20 秒内完成');
        expect(error, isNull);
      }

      await finish(service.speakLines(['项目自有语音样本']));
      expect(positions['poem'], greaterThan(0));
      final states = <NarrationStatus>[];
      Source? bookSource;
      final session = service.startNarration(
        ['教材云音频样本'],
        bookId: 'b' * 64,
        cache: cache,
        onState: (state, _) {
          states.add(state.status);
          if (state.status == NarrationStatus.playing) {
            bookSource = nativeBook.source;
          }
        },
      );
      await finish(session.completed);
      expect(
        states,
        containsAllInOrder([
          NarrationStatus.playing,
          NarrationStatus.completed,
        ]),
      );
      expect(positions['book'], greaterThan(0));
      expect(cloud.texts, ['项目自有语音样本', '教材云音频样本']);
      expect(bookSource, isA<DeviceFileSource>());
      expect(bookSource?.mimeType, 'audio/mpeg');
      debugPrint(
        'CLOUD_PLAYBACK_ACCEPTANCE poemMs=${positions['poem']} bookMs=${positions['book']}',
      );
    } finally {
      await service.stop();
      service.dispose();
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      cloud.client.close();
      await folder.delete(recursive: true);
    }
  });
}
