// lib/core/services/speech/tencent_speech_recognition_service.dart
//
// 纯腾讯云语音识别服务：录音（PCM 16k/mono）→ 停止 → 整段上传
// 腾讯云一句话识别（SentenceRecognition）。
//
// 无本地模型依赖；凭据缺失或云端失败均上抛异常，由调用方处理。

import 'dart:async';
import 'dart:typed_data';

import 'package:poemath/core/services/speech/speech_audio_recorder.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_asr_client.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

abstract interface class SpeechRecognitionService {
  bool get isRecording;

  Future<void> initialize();

  Future<void> start();

  Future<SpeechRecognitionResult> stop();

  Future<void> cancel();

  Future<void> dispose();
}

/// Records PCM once and asks Tencent Cloud for the final transcript.
final class TencentSpeechRecognitionService
    implements SpeechRecognitionService {
  TencentSpeechRecognitionService({
    required SpeechAudioRecorder recorder,
    required TencentAsrClient tencentClient,
    required SettingsRepository settingsRepository,
  })  : _recorder = recorder,
        _tencentClient = tencentClient,
        _settingsRepository = settingsRepository;

  final SpeechAudioRecorder _recorder;
  final TencentAsrClient _tencentClient;
  final SettingsRepository _settingsRepository;

  _RecordingSession? _session;
  int _generation = 0;
  bool _isRecording = false;
  bool _starting = false;
  Future<void> _recorderQueue = Future<void>.value();

  // Only microphone operations are serialized. Cloud recognition may finish
  // after a new recording starts, but must never stop that new recording.
  Future<T> _withRecorder<T>(Future<T> Function() operation) {
    final result = _recorderQueue.then((_) => operation());
    _recorderQueue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  bool get isRecording => _isRecording;

  @override
  Future<void> initialize() async {
    // 无本地模型可初始化；保留空实现以兼容调用方生命周期。
  }

  @override
  Future<void> start() async {
    if (_isRecording || _starting) {
      throw const SpeechRecognitionException('语音识别正在录音');
    }
    _starting = true;
    final generation = ++_generation;
    final session = _RecordingSession();
    try {
      await _withRecorder(() async {
        if (!await _recorder.hasPermission()) {
          throw const SpeechPermissionDeniedException();
        }
        if (generation != _generation) return;
        _session = session;
        _isRecording = true;
        final audioStream = await _recorder.startStream();
        if (generation != _generation) {
          await audioStream.listen((_) {}).cancel();
          await _recorder.cancel();
          return;
        }
        session.subscription = audioStream.listen(
          session.add,
          onError: (Object error, StackTrace stack) {
            session.error ??= error;
            session.stack ??= stack;
          },
          onDone: session.finish,
        );
      });
    } on Object {
      if (identical(_session, session)) {
        _session = null;
        _isRecording = false;
      }
      rethrow;
    } finally {
      _starting = false;
    }
  }

  @override
  Future<SpeechRecognitionResult> stop() async {
    final session = _session;
    if (!_isRecording || session == null) {
      throw const SpeechRecognitionException('当前没有正在进行的录音');
    }
    final generation = _generation;
    _isRecording = false;
    try {
      final pcm = await _withRecorder(() async {
        if (generation != _generation) {
          throw const SpeechRecognitionException('录音已取消');
        }
        await _recorder.stop();
        await session.done.future;
        if (generation != _generation) {
          throw const SpeechRecognitionException('录音已取消');
        }
        if (session.error != null) {
          Error.throwWithStackTrace(
            const SpeechRecognitionException('录音失败'),
            session.stack ?? StackTrace.current,
          );
        }
        final length = session.bytes.length - session.bytes.length % 2;
        return Uint8List(length)..setRange(0, length, session.bytes);
      });
      final credentials = await _settingsRepository.readTencentAsrCredentials();
      if (generation != _generation) {
        throw const SpeechRecognitionException('录音已取消');
      }
      if (credentials == null) {
        throw const TencentAsrException(
          '请先保存腾讯云密钥',
          kind: TencentAsrErrorKind.authentication,
        );
      }
      final text = await _tencentClient.recognizePcm16(
        pcmBytes: pcm,
        credentials: credentials,
      );
      if (generation != _generation) {
        throw const SpeechRecognitionException('录音已取消');
      }
      return SpeechRecognitionResult(text: text);
    } on Object {
      if (generation == _generation) {
        try {
          await _withRecorder(() async {
            if (generation == _generation) await _recorder.cancel();
          });
        } on Exception {
          AppLogger.w('识别失败后取消录音失败', tag: 'Speech');
        }
      }
      rethrow;
    } finally {
      await session.subscription?.cancel();
      session.bytes.clear();
      if (identical(_session, session)) _session = null;
    }
  }

  @override
  Future<void> cancel() async {
    ++_generation;
    final session = _session;
    _session = null;
    final wasRecording = _isRecording;
    _isRecording = false;
    session?.finish();
    if (wasRecording || _starting) {
      try {
        await _withRecorder(_recorder.cancel);
      } on Exception {
        AppLogger.w('取消录音失败', tag: 'Speech');
      }
    }
    await session?.subscription?.cancel();
    session?.finish();
    session?.bytes.clear();
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }
}

final class _RecordingSession {
  final bytes = <int>[];
  final done = Completer<void>();
  StreamSubscription<Uint8List>? subscription;
  Object? error;
  StackTrace? stack;

  void add(Uint8List chunk) {
    if (bytes.length + chunk.length > TencentAsrClient.maxRawBytes) {
      error ??= const SpeechRecognitionException('录音不能超过 60 秒');
      return;
    }
    bytes.addAll(chunk);
  }

  void finish() {
    if (!done.isCompleted) done.complete();
  }
}
