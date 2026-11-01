// lib/core/services/speech/preferred_speech_recognition_service.dart

import 'dart:async';
import 'dart:typed_data';

import 'package:poemath/core/services/speech/speech_audio_recorder.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_asr_client.dart';
import 'package:poemath/core/services/speech/tencent_realtime_asr_client.dart';
import 'package:poemath/core/services/speech/tencent_speech_recognition_service.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

/// 能提供实时增量文字的可选能力。旧页面和测试只依赖
/// [SpeechRecognitionService]，因此这个能力以独立接口暴露，不破坏已有 fake。
abstract interface class StreamingSpeechRecognitionService {
  Stream<String> get transcriptStream;
  String get recognitionMode;
  bool get usedFallback;
}

abstract interface class RetainedAudioSpeechRecognitionService {
  Uint8List? takeLastAudio();
}

/// 所有页面共用的识别编排：实时识别优先，只有腾讯云明确返回实时额度耗尽
/// 时，才使用已经缓存在内存中的完整 PCM 回退到一句话识别。
final class PreferredSpeechRecognitionService
    implements
        SpeechRecognitionService,
        StreamingSpeechRecognitionService,
        RetainedAudioSpeechRecognitionService {
  PreferredSpeechRecognitionService({
    required SpeechAudioRecorder recorder,
    required TencentAsrClient sentenceClient,
    required TencentRealtimeAsrClient realtimeClient,
    required SettingsRepository settingsRepository,
  })  : _recorder = recorder,
        _sentenceClient = sentenceClient,
        _realtimeClient = realtimeClient,
        _settingsRepository = settingsRepository;

  final SpeechAudioRecorder _recorder;
  final TencentAsrClient _sentenceClient;
  final TencentRealtimeAsrClient _realtimeClient;
  final SettingsRepository _settingsRepository;

  final _transcriptController = StreamController<String>.broadcast();
  _RecordingSession? _session;
  int _generation = 0;
  bool _isRecording = false;
  bool _starting = false;
  bool _disposed = false;
  bool _usedFallback = false;
  Uint8List? _lastAudio;
  String _mode = 'sentence';
  Future<void> _recorderQueue = Future<void>.value();

  @override
  Stream<String> get transcriptStream => _transcriptController.stream;

  @override
  String get recognitionMode => _mode;

  @override
  bool get usedFallback => _usedFallback;

  @override
  Uint8List? takeLastAudio() {
    final bytes = _lastAudio;
    _lastAudio = null;
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  bool get isRecording => _isRecording;

  Future<T> _withRecorder<T>(Future<T> Function() operation) {
    final result = _recorderQueue.then((_) => operation());
    _recorderQueue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<void> initialize() async {}

  bool _current(_RecordingSession session) =>
      !_disposed &&
      identical(_session, session) &&
      session.generation == _generation &&
      !session.cancelToken.isCancelled;

  void _check(_RecordingSession session) {
    if (!_current(session)) throw const SpeechRecognitionCancelled();
  }

  Future<void> _release(_RecordingSession session) =>
      session.cleanup ??= () async {
        try {
          await session.subscription?.cancel();
        } on Exception {
          AppLogger.w('取消录音订阅失败', tag: 'Speech');
        }
        session.bytes.clear();
        try {
          await session.realtime?.cancel();
        } on Exception {
          AppLogger.w('取消实时识别失败', tag: 'Speech');
        }
      }();

  @override
  Future<void> start() async {
    if (_disposed) throw const SpeechRecognitionException('语音识别已关闭');
    if (_isRecording || _starting) {
      throw const SpeechRecognitionException('语音识别正在录音');
    }
    final previous = _session;
    if (previous != null) {
      previous.cancelToken.cancel();
      previous.finish();
      unawaited(_release(previous));
    }
    _starting = true;
    final session = _RecordingSession(++_generation);
    _session = session;
    _usedFallback = false;
    _lastAudio = null;
    _mode = 'realtime';
    try {
      final credentials = await session.cancelToken.wait(
        _settingsRepository.readTencentAsrCredentials(),
      );
      _check(session);
      if (credentials == null) {
        throw const TencentAsrException(
          '请先保存腾讯云密钥',
          kind: TencentAsrErrorKind.authentication,
        );
      }
      await _withRecorder(() async {
        _check(session);
        final permission =
            await session.cancelToken.wait(_recorder.hasPermission());
        _check(session);
        if (!permission) {
          throw const SpeechPermissionDeniedException();
        }
        try {
          session.realtime = await _realtimeClient.connect(
            credentials: credentials,
            cancelToken: session.cancelToken,
            onText: (text, {required stable}) {
              if (!_current(session) || text.isEmpty) return;
              _transcriptController.add(text);
            },
          );
          _check(session);
        } on TencentRealtimeAsrException catch (error) {
          _check(session);
          if (!_isRealtimeQuotaExhausted(error)) rethrow;
          session.realtimeStartFailure = error;
          _mode = 'sentence';
          _usedFallback = true;
        }
        _check(session);
        final audioStream = await _recorder.startStream();
        if (!_current(session)) {
          await audioStream.listen((_) {}).cancel();
          await _recorder.cancel();
          throw const SpeechRecognitionCancelled();
        }
        session.subscription = audioStream.listen(
          (chunk) {
            if (!_current(session)) return;
            session.add(chunk);
            session.realtime?.add(chunk);
          },
          onError: (Object error, StackTrace stack) {
            session.error ??= error;
            session.stack ??= stack;
          },
          onDone: session.finish,
        );
        _isRecording = true;
      });
      _check(session);
    } on Object {
      session.cancelToken.cancel();
      session.finish();
      if (identical(_session, session)) {
        _session = null;
        _isRecording = false;
      }
      await _release(session);
      rethrow;
    } finally {
      if (session.generation == _generation) _starting = false;
    }
  }

  @override
  Future<SpeechRecognitionResult> stop() async {
    final session = _session;
    if (!_isRecording || session == null) {
      throw const SpeechRecognitionException('当前没有正在进行的录音');
    }
    _isRecording = false;
    try {
      final pcm = await _withRecorder(() async {
        _check(session);
        await _recorder.stop();
        _check(session);
        await session.cancelToken.wait(session.done.future);
        _check(session);
        if (session.error != null) {
          Error.throwWithStackTrace(
            const SpeechRecognitionException('录音失败'),
            session.stack ?? StackTrace.current,
          );
        }
        final length = session.bytes.length - session.bytes.length % 2;
        return Uint8List(length)..setRange(0, length, session.bytes);
      });
      _check(session);
      _lastAudio = Uint8List.fromList(pcm);

      final startFailure = session.realtimeStartFailure;
      if (startFailure != null) {
        if (!_isRealtimeQuotaExhausted(startFailure)) {
          throw startFailure;
        }
        return await _recognizeSentence(
          pcm,
          session: session,
          usedFallback: true,
        );
      }

      final realtime = session.realtime;
      if (realtime != null) {
        try {
          final text = await session.cancelToken.wait(realtime.end());
          _check(session);
          if (text.isNotEmpty) {
            _mode = 'realtime';
            return SpeechRecognitionResult(text: text, mode: 'realtime');
          }
          throw const TencentRealtimeAsrException(
            '腾讯云实时识别未返回有效文字',
            kind: TencentRealtimeErrorKind.response,
          );
        } on TencentRealtimeAsrException catch (error) {
          _check(session);
          if (!_isRealtimeQuotaExhausted(error)) rethrow;
          return await _recognizeSentence(
            pcm,
            session: session,
            usedFallback: true,
          );
        }
      }
      throw const SpeechRecognitionException('腾讯云实时识别未建立连接');
    } on Object {
      if (_current(session)) {
        try {
          await _withRecorder(() async {
            if (_current(session)) await _recorder.cancel();
          });
        } on Exception {
          AppLogger.w('识别失败后取消录音失败', tag: 'Speech');
        }
      }
      rethrow;
    } finally {
      session.cancelToken.cancel();
      if (identical(_session, session)) _session = null;
      await _release(session);
    }
  }

  Future<SpeechRecognitionResult> _recognizeSentence(
    Uint8List pcm, {
    required _RecordingSession session,
    required bool usedFallback,
  }) async {
    _check(session);
    final credentials = await session.cancelToken.wait(
      _settingsRepository.readTencentAsrCredentials(),
    );
    _check(session);
    if (credentials == null) {
      throw const TencentAsrException(
        '请先保存腾讯云密钥',
        kind: TencentAsrErrorKind.authentication,
      );
    }
    final result = await _sentenceClient.recognizePcm16(
      pcmBytes: pcm,
      credentials: credentials,
      reserveUsage: false,
      cancelToken: session.cancelToken,
    );
    _check(session);
    _mode = 'sentence';
    _usedFallback = usedFallback;
    return SpeechRecognitionResult(
      text: result,
      mode: 'sentence',
      usedFallback: usedFallback,
    );
  }

  static bool _isRealtimeQuotaExhausted(TencentRealtimeAsrException error) =>
      error.kind == TencentRealtimeErrorKind.quota && error.code == 4004;

  @override
  Future<void> cancel() async {
    ++_generation;
    final session = _session;
    _session = null;
    final wasRecording = _isRecording;
    final wasStarting = _starting;
    _isRecording = false;
    _starting = false;
    _lastAudio = null;
    session?.cancelToken.cancel();
    session?.finish();
    if (wasRecording || wasStarting) {
      try {
        await _withRecorder(_recorder.cancel);
      } on Exception {
        AppLogger.w('取消录音失败', tag: 'Speech');
      }
    }
    if (session != null) await _release(session);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await cancel();
    await _recorder.dispose();
    await _transcriptController.close();
  }
}

final class _RecordingSession {
  _RecordingSession(this.generation);
  final int generation;
  final cancelToken = SpeechRecognitionCancelToken();
  TencentRealtimeAsrSession? realtime;
  TencentRealtimeAsrException? realtimeStartFailure;
  Future<void>? cleanup;
  final bytes = <int>[];
  final done = Completer<void>();
  StreamSubscription<Uint8List>? subscription;
  Object? error;
  StackTrace? stack;

  void add(Uint8List chunk) {
    final remaining = TencentAsrClient.maxRawBytes - bytes.length;
    if (remaining <= 0) {
      error ??= const SpeechRecognitionException('录音不能超过 60 秒');
      return;
    }
    final length = chunk.length > remaining ? remaining : chunk.length;
    bytes.addAll(chunk.take(length));
    if (length < chunk.length) {
      error ??= const SpeechRecognitionException('录音不能超过 60 秒');
    }
  }

  void finish() {
    if (!done.isCompleted) done.complete();
  }
}
