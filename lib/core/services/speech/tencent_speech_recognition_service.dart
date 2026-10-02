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

  final List<int> _pcmBytes = <int>[];
  StreamSubscription<Uint8List>? _audioSubscription;
  Completer<void>? _audioDone;
  Object? _audioError;
  StackTrace? _audioErrorStackTrace;
  bool _isRecording = false;

  @override
  bool get isRecording => _isRecording;

  @override
  Future<void> initialize() async {
    // 无本地模型可初始化；保留空实现以兼容调用方生命周期。
  }

  @override
  Future<void> start() async {
    if (_isRecording) {
      throw const SpeechRecognitionException('语音识别正在录音');
    }
    if (!await _recorder.hasPermission()) {
      throw const SpeechPermissionDeniedException();
    }

    _pcmBytes.clear();
    _audioError = null;
    _audioErrorStackTrace = null;
    _audioDone = Completer<void>();
    _isRecording = true;

    try {
      final audioStream = await _recorder.startStream();
      _audioSubscription = audioStream.listen(
        _handleAudioChunk,
        onError: _handleAudioError,
        onDone: _handleAudioDone,
        cancelOnError: false,
      );
    } on Object {
      _isRecording = false;
      _clearSessionState();
      rethrow;
    }
  }

  void _handleAudioChunk(Uint8List bytes) {
    if (_pcmBytes.length + bytes.length > TencentAsrClient.maxRawBytes) {
      _audioError ??= const SpeechRecognitionException('录音不能超过 60 秒');
      return;
    }
    _pcmBytes.addAll(bytes);
  }

  void _handleAudioError(Object error, StackTrace stackTrace) {
    _audioError ??= error;
    _audioErrorStackTrace ??= stackTrace;
  }

  void _handleAudioDone() {
    final done = _audioDone;
    if (done != null && !done.isCompleted) done.complete();
  }

  @override
  Future<SpeechRecognitionResult> stop() async {
    if (!_isRecording) {
      throw const SpeechRecognitionException('当前没有正在进行的录音');
    }
    _isRecording = false;

    try {
      await _recorder.stop();
      await _audioDone?.future;
      final audioError = _audioError;
      if (audioError != null) {
        Error.throwWithStackTrace(
          const SpeechRecognitionException('录音失败'),
          _audioErrorStackTrace ?? StackTrace.current,
        );
      }

      final pcmLength =
          _pcmBytes.length.isEven ? _pcmBytes.length : _pcmBytes.length - 1;
      final pcmBytes = Uint8List(pcmLength)..setRange(0, pcmLength, _pcmBytes);

      final credentials = await _settingsRepository.readTencentAsrCredentials();
      if (credentials == null) {
        throw const TencentAsrException(
          '请先保存腾讯云密钥',
          kind: TencentAsrErrorKind.authentication,
        );
      }

      final cloudText = await _tencentClient.recognizePcm16(
        pcmBytes: pcmBytes,
        credentials: credentials,
      );
      return SpeechRecognitionResult(text: cloudText);
    } on Object {
      try {
        await _recorder.cancel();
      } on Exception {
        AppLogger.w('识别失败后取消录音失败', tag: 'Speech');
      }
      await _audioSubscription?.cancel();
      rethrow;
    } finally {
      await _audioSubscription?.cancel();
      _clearSessionState();
    }
  }

  @override
  Future<void> cancel() async {
    final wasRecording = _isRecording;
    _isRecording = false;
    if (wasRecording) {
      try {
        await _recorder.cancel();
      } on Exception {
        AppLogger.w('取消录音失败', tag: 'Speech');
      }
    }
    await _audioSubscription?.cancel();
    _clearSessionState();
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }

  void _clearSessionState() {
    _audioSubscription = null;
    _audioDone = null;
    _audioError = null;
    _audioErrorStackTrace = null;
    _pcmBytes.clear();
  }
}
