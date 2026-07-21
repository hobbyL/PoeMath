// lib/core/services/speech/hybrid_speech_recognition_service.dart

import 'dart:async';
import 'dart:typed_data';

import 'package:poemath/core/services/speech/local_speech_recognizer.dart';
import 'package:poemath/core/services/speech/speech_audio_recorder.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_asr_client.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

abstract interface class SpeechRecognitionService {
  bool get isRecording;

  Future<void> initialize();

  Future<void> start({void Function(String text)? onPartialResult});

  Future<SpeechRecognitionResult> stop({bool requireTencentCloud = false});

  Future<void> cancel();

  Future<void> dispose();
}

/// Records PCM once, always decodes it locally, and optionally asks Tencent
/// Cloud to replace the final text.
final class HybridSpeechRecognitionService implements SpeechRecognitionService {
  HybridSpeechRecognitionService({
    required SpeechAudioRecorder recorder,
    required LocalSpeechRecognizer localRecognizer,
    required TencentAsrClient tencentClient,
    required SettingsRepository settingsRepository,
  })  : _recorder = recorder,
        _localRecognizer = localRecognizer,
        _tencentClient = tencentClient,
        _settingsRepository = settingsRepository;

  final SpeechAudioRecorder _recorder;
  final LocalSpeechRecognizer _localRecognizer;
  final TencentAsrClient _tencentClient;
  final SettingsRepository _settingsRepository;

  final List<int> _pcmBytes = <int>[];
  StreamSubscription<Uint8List>? _audioSubscription;
  Completer<void>? _audioDone;
  Future<void> _chunkProcessing = Future<void>.value();
  Object? _audioError;
  StackTrace? _audioErrorStackTrace;
  void Function(String text)? _onPartialResult;
  bool _isRecording = false;

  @override
  bool get isRecording => _isRecording;

  @override
  Future<void> initialize() => _localRecognizer.initialize();

  @override
  Future<void> start({void Function(String text)? onPartialResult}) async {
    if (_isRecording) {
      throw const SpeechRecognitionException('语音识别正在录音');
    }
    if (!await _recorder.hasPermission()) {
      throw const SpeechPermissionDeniedException();
    }

    await _localRecognizer.start();
    _pcmBytes.clear();
    _audioError = null;
    _audioErrorStackTrace = null;
    _onPartialResult = onPartialResult;
    _audioDone = Completer<void>();
    _chunkProcessing = Future<void>.value();
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
      await _localRecognizer.cancel();
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
    _chunkProcessing = _chunkProcessing.then((_) async {
      if (_audioError != null) return;
      try {
        final text = await _localRecognizer.acceptPcm(bytes);
        if (text.isNotEmpty) _onPartialResult?.call(text);
      } on Object catch (error, stackTrace) {
        _audioError ??= error;
        _audioErrorStackTrace ??= stackTrace;
      }
    });
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
  Future<SpeechRecognitionResult> stop({
    bool requireTencentCloud = false,
  }) async {
    if (!_isRecording) {
      throw const SpeechRecognitionException('当前没有正在进行的录音');
    }
    _isRecording = false;

    try {
      await _recorder.stop();
      await _audioDone?.future;
      await _chunkProcessing;
      final audioError = _audioError;
      if (audioError != null) {
        Error.throwWithStackTrace(
          const SpeechRecognitionException('录音或离线识别失败'),
          _audioErrorStackTrace ?? StackTrace.current,
        );
      }

      final localText = await _localRecognizer.finish();
      final pcmLength =
          _pcmBytes.length.isEven ? _pcmBytes.length : _pcmBytes.length - 1;
      final pcmBytes = Uint8List(pcmLength)..setRange(0, pcmLength, _pcmBytes);
      final settings =
          await _settingsRepository.loadSpeechRecognitionSettings();

      if (requireTencentCloud) {
        final credentials =
            await _settingsRepository.readTencentAsrCredentials();
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
        return SpeechRecognitionResult(
          text: cloudText,
          localText: localText,
          source: SpeechRecognitionSource.tencentCloud,
        );
      }

      if (!settings.highAccuracyEnabled) {
        return SpeechRecognitionResult(
          text: localText,
          localText: localText,
          source: SpeechRecognitionSource.local,
        );
      }

      final credentials = await _settingsRepository.readTencentAsrCredentials();
      if (credentials == null) {
        return SpeechRecognitionResult(
          text: localText,
          localText: localText,
          source: SpeechRecognitionSource.local,
          fellBackFromCloud: true,
        );
      }

      try {
        final cloudText = await _tencentClient.recognizePcm16(
          pcmBytes: pcmBytes,
          credentials: credentials,
        );
        return SpeechRecognitionResult(
          text: cloudText,
          localText: localText,
          source: SpeechRecognitionSource.tencentCloud,
        );
      } on Exception {
        AppLogger.w(
          '腾讯云识别失败，已回退离线结果',
          tag: 'Speech',
        );
        return SpeechRecognitionResult(
          text: localText,
          localText: localText,
          source: SpeechRecognitionSource.local,
          fellBackFromCloud: true,
        );
      }
    } on Object {
      try {
        await _recorder.cancel();
      } on Exception {
        AppLogger.w('识别失败后取消录音失败', tag: 'Speech');
      }
      await _audioSubscription?.cancel();
      await _chunkProcessing;
      await _localRecognizer.cancel();
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
    await _chunkProcessing;
    await _localRecognizer.cancel();
    _clearSessionState();
  }

  void _clearSessionState() {
    _audioSubscription = null;
    _audioDone = null;
    _audioError = null;
    _audioErrorStackTrace = null;
    _onPartialResult = null;
    _pcmBytes.clear();
    _chunkProcessing = Future<void>.value();
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
    await _localRecognizer.dispose();
  }
}
