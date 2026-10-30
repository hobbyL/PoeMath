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
  TencentRealtimeAsrSession? _realtimeSession;
  TencentRealtimeAsrException? _realtimeStartFailure;
  int _generation = 0;
  bool _isRecording = false;
  bool _starting = false;
  bool _usedFallback = false;
  bool _realtimeAttempted = false;
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

  @override
  Future<void> start() async {
    if (_isRecording || _starting) {
      throw const SpeechRecognitionException('语音识别正在录音');
    }
    _starting = true;
    final generation = ++_generation;
    final session = _RecordingSession();
    _usedFallback = false;
    _lastAudio = null;
    _mode = 'sentence';
    _realtimeStartFailure = null;
    _realtimeSession = null;
    _realtimeAttempted = false;
    try {
      final credentials = await _settingsRepository.readTencentAsrCredentials();
      if (credentials == null) {
        throw const TencentAsrException(
          '请先保存腾讯云密钥',
          kind: TencentAsrErrorKind.authentication,
        );
      }
      await _withRecorder(() async {
        if (!await _recorder.hasPermission()) {
          throw const SpeechPermissionDeniedException();
        }
        if (generation != _generation) return;
        _session = session;
        _isRecording = true;
        if (credentials.hasRealtimeCredentials) {
          _realtimeAttempted = true;
          try {
            _realtimeSession = await _realtimeClient.connect(
              credentials: credentials,
              onText: (text, {required stable}) {
                if (generation != _generation || text.isEmpty) return;
                _mode = 'realtime';
                _transcriptController.add(text);
              },
            );
            _mode = 'realtime';
          } on TencentRealtimeAsrException catch (error) {
            // 本地保护额度不是腾讯云月度额度，不能通过回退绕过它。
            if (error.code == -1) rethrow;
            _realtimeStartFailure = error;
          }
        }
        final audioStream = await _recorder.startStream();
        if (generation != _generation) {
          await audioStream.listen((_) {}).cancel();
          await _recorder.cancel();
          return;
        }
        session.subscription = audioStream.listen(
          (chunk) {
            session.add(chunk);
            _realtimeSession?.add(chunk);
          },
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
      await _realtimeSession?.cancel();
      _realtimeSession = null;
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
      _lastAudio = Uint8List.fromList(pcm);

      if (_realtimeStartFailure != null) {
        if (_realtimeStartFailure!.kind != TencentRealtimeErrorKind.quota) {
          throw _realtimeStartFailure!;
        }
        return _recognizeSentence(
          pcm,
          credentialsGeneration: generation,
          usedFallback: true,
        );
      }

      // APPID 是实时接口新增的配置项。旧用户仍只有 SecretId/SecretKey
      // 时，继续走原有的一句话识别，避免升级后已有功能失效。
      if (!_realtimeAttempted) {
        return _recognizeSentence(
          pcm,
          credentialsGeneration: generation,
          usedFallback: false,
        );
      }

      final realtime = _realtimeSession;
      if (realtime != null) {
        try {
          final text = await realtime.end();
          if (text.isNotEmpty) {
            _mode = 'realtime';
            return SpeechRecognitionResult(text: text, mode: 'realtime');
          }
          throw const TencentRealtimeAsrException(
            '腾讯云实时识别未返回有效文字',
            kind: TencentRealtimeErrorKind.response,
          );
        } on TencentRealtimeAsrException catch (error) {
          if (error.kind != TencentRealtimeErrorKind.quota) rethrow;
          return _recognizeSentence(
            pcm,
            credentialsGeneration: generation,
            usedFallback: true,
          );
        }
      }
      throw const SpeechRecognitionException('腾讯云实时识别未建立连接');
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
      await _realtimeSession?.cancel();
      _realtimeSession = null;
      if (identical(_session, session)) _session = null;
    }
  }

  Future<SpeechRecognitionResult> _recognizeSentence(
    Uint8List pcm, {
    required int credentialsGeneration,
    required bool usedFallback,
  }) async {
    if (credentialsGeneration != _generation) {
      throw const SpeechRecognitionException('录音已取消');
    }
    final credentials = await _settingsRepository.readTencentAsrCredentials();
    if (credentials == null) {
      throw const TencentAsrException(
        '请先保存腾讯云密钥',
        kind: TencentAsrErrorKind.authentication,
      );
    }
    final result = await _sentenceClient.recognizePcm16(
      pcmBytes: pcm,
      credentials: credentials,
      reserveUsage: !_realtimeAttempted,
    );
    _mode = 'sentence';
    _usedFallback = usedFallback;
    return SpeechRecognitionResult(
      text: result,
      mode: 'sentence',
      usedFallback: usedFallback,
    );
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
    await _realtimeSession?.cancel();
    _realtimeSession = null;
    await session?.subscription?.cancel();
    session?.bytes.clear();
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
    await _transcriptController.close();
  }
}

final class _RecordingSession {
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
