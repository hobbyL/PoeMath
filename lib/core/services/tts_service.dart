// lib/core/services/tts_service.dart
//
// TTS 朗读服务：系统引擎（flutter_tts）+ 可选自建 Worker 云端合成。
// 云端开启且服务已验证时云优先，失败静默回退系统音色，朗读不中断。

import 'dart:async';

import 'dart:typed_data';

import 'package:flutter_tts/flutter_tts.dart';

import 'package:poemath/core/services/tts/tts_models.dart';
import 'package:poemath/core/services/tts/worker_tts_client.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

/// TTS 朗读服务。
///
/// 支持全文朗读、逐句/逐行朗读与音色选择；云端模式逐段合成、
/// 逐段播放，`onLineStart` / `onSentenceStart` 回调时序与系统模式一致。
class TtsService {
  static const String _logTag = 'Tts';

  /// 云端合成内存 LRU 容量（行级 mp3，< 2MB）。
  static const int _cloudCacheCapacity = 32;

  final FlutterTts _tts;
  final SettingsRepository _settings;
  final WorkerTtsClient? _cloudClient;

  CloudAudioPlayer? _cloudPlayer;
  final Map<String, Uint8List> _cloudCache = <String, Uint8List>{};

  WorkerTtsConfig? _cloudConfig;

  /// 鉴权类错误（401）后置位：本次朗读整段降级系统音色，
  /// 避免逐行重复撞错；下次朗读入口重置。
  bool _cloudSessionDisabled = false;

  bool _initialized = false;
  bool _isSpeaking = false;
  String? _engineErrorMessage;

  /// 用户主动停止标志，仅 [stop] 方法设置，
  /// 避免 completionHandler 干扰 [speakLines] 循环。
  bool _stopRequested = false;

  TtsService(
    this._settings, {
    FlutterTts? flutterTts,
    WorkerTtsClient? cloudClient,
    CloudAudioPlayer? cloudPlayer,
  })  : _tts = flutterTts ?? FlutterTts(),
        _cloudClient = cloudClient,
        _cloudPlayer = cloudPlayer;

  /// 当前是否正在朗读。
  bool get isSpeaking => _isSpeaking;

  /// 云端播放器（懒创建，未注入且从未走云路径时为 null，不触平台通道）。
  CloudAudioPlayer get _cloudPlayerResolved =>
      _cloudPlayer ??= AudioplayersCloudAudioPlayer();

  /// 初始化 TTS 引擎。
  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    await _runEngineOperation('语音引擎初始化失败', () async {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(_settings.ttsSpeed);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      final savedVoice = _settings.ttsVoice;
      if (savedVoice != null) {
        await _tts.setVoice(savedVoice);
      }

      // 该设置决定后续 speak() 的 Future 是否等待朗读完成，
      // 必须在第一次 speak() 之前启用。
      await _tts.awaitSpeakCompletion(true);

      _tts.setCancelHandler(() {
        _isSpeaking = false;
        _stopRequested = true;
      });

      _tts.setErrorHandler((message) {
        _engineErrorMessage = message.toString();
        _isSpeaking = false;
        _stopRequested = true;
      });
    });

    _initialized = true;
  }

  /// 朗读会话入口：刷新云端可用状态（开关 + 自建服务验证）。
  Future<void> _refreshCloudState() async {
    _cloudSessionDisabled = false;
    if (_cloudClient == null || !_settings.ttsCloudEnabled) {
      _cloudConfig = null;
      return;
    }
    try {
      final verified = await _settings.isWorkerTtsVerified();
      _cloudConfig = verified ? await _settings.readWorkerTtsConfig() : null;
    } on Object catch (error) {
      AppLogger.w('读取云端朗读配置失败，本次使用系统音色：$error', tag: _logTag);
      _cloudConfig = null;
    }
  }

  /// 本次会话是否走云端合成。
  bool get _cloudMode =>
      _cloudClient != null && _cloudConfig != null && !_cloudSessionDisabled;

  /// 严格合成：命中缓存或请求云端，异常上抛。
  Future<Uint8List> _synthesizeStrict(String text) async {
    final voice = _settings.ttsCloudVoice;
    final style = _settings.ttsCloudStyle;
    final rate = workerRateFor(_settings.ttsSpeed);
    final cacheKey = '$voice|$style|$rate|$text';
    final cached = _cloudCache.remove(cacheKey);
    if (cached != null) {
      _cloudCache[cacheKey] = cached;
      return cached;
    }

    final bytes = await _cloudClient!.synthesize(
      config: _cloudConfig!,
      text: text,
      voice: voice,
      style: style,
      rate: rate,
    );
    _storeCache(cacheKey, bytes);
    return bytes;
  }

  /// 宽松合成：失败返回 null（调用方回退系统音色）。
  ///
  /// 鉴权类错误（401，key 被换/撤销）将本次朗读整段降级。
  Future<Uint8List?> _synthesizeCloud(String text) async {
    if (!_cloudMode) return null;
    try {
      return await _synthesizeStrict(text);
    } on WorkerTtsException catch (error) {
      if (error.kind == WorkerTtsErrorKind.authentication) {
        _cloudSessionDisabled = true;
      }
      AppLogger.w('云端合成失败，回退系统音色：${error.message}', tag: _logTag);
      return null;
    } on Object catch (error) {
      AppLogger.w('云端合成异常，回退系统音色：$error', tag: _logTag);
      return null;
    }
  }

  void _storeCache(String key, Uint8List bytes) {
    _cloudCache
      ..remove(key)
      ..[key] = bytes;
    while (_cloudCache.length > _cloudCacheCapacity) {
      _cloudCache.remove(_cloudCache.keys.first);
    }
  }

  /// 单段朗读统一入口：云端优先，失败回退系统引擎完成当段。
  Future<void> _speakSegmentBestEffort(String text) async {
    if (_cloudMode) {
      final bytes = await _synthesizeCloud(text);
      if (bytes != null) {
        try {
          await _cloudPlayerResolved.play(bytes);
          return;
        } on Object catch (error) {
          // 播放失败不回退系统朗读，避免同一句双读。
          AppLogger.w('云端音频播放失败，跳过该句：$error', tag: _logTag);
          return;
        }
      }
    }
    await _runEngineOperation('朗读失败', () async {
      await _tts.setSpeechRate(_settings.ttsSpeed);
      await _tts.speak(text);
      _throwIfEngineReportedError();
    });
  }

  Future<T> _runEngineOperation<T>(
    String failureMessage,
    Future<T> Function() operation,
  ) async {
    try {
      return await operation();
    } on TtsException {
      rethrow;
    } on Exception catch (error) {
      throw TtsException(failureMessage, cause: error);
    }
  }

  void _throwIfEngineReportedError() {
    final message = _engineErrorMessage;
    if (message != null) {
      throw TtsException('语音引擎朗读失败：$message');
    }
  }

  /// 获取可用的中文音色列表（已去重）。
  ///
  /// 返回 `List<Map<String, String>>`，每个 Map 至少包含 name 和 locale。
  /// 仅返回 locale 以 "zh" 开头的音色（zh-CN, zh-TW, zh-HK 等）。
  /// 按 name+locale 去重，避免 Android 上返回多个完全相同的条目。
  Future<List<Map<String, String>>> getChineseVoices() async {
    await _ensureInitialized();
    final Object? voices = await _runEngineOperation<Object?>(
      '获取系统音色失败',
      () => _tts.getVoices,
    );
    if (voices is! List<Object?>) {
      throw const TtsException('系统返回了无效的音色数据');
    }

    final seen = <String>{};
    final chineseVoices = <Map<String, String>>[];

    for (final voice in voices) {
      if (voice is! Map<Object?, Object?>) continue;
      final locale = (voice['locale'] ?? '').toString();
      if (!locale.startsWith('zh')) continue;

      final name = (voice['name'] ?? '').toString();
      final key = '$name|$locale';
      if (seen.contains(key)) continue;
      seen.add(key);

      chineseVoices.add({
        'name': name,
        'locale': locale,
      });
    }

    // 按 locale → name 排序，zh-CN 优先
    chineseVoices.sort((a, b) {
      final localeCompare = a['locale']!.compareTo(b['locale']!);
      if (localeCompare != 0) return localeCompare;
      return a['name']!.compareTo(b['name']!);
    });

    return chineseVoices;
  }

  /// 设置系统音色并保存到设置。传 null 恢复系统默认。
  Future<void> setVoice(Map<String, String>? voice) async {
    await _ensureInitialized();
    await _runEngineOperation('设置系统音色失败', () async {
      if (voice != null) {
        await _tts.setVoice(voice);
      } else {
        // 恢复默认：重设语言让系统选择默认音色
        await _tts.setLanguage('zh-CN');
      }
    });
    await _settings.setTtsVoice(voice);
  }

  /// 试听当前音色：朗读一段示例文本（系统音色路径）。
  Future<void> preview(String text) => speak(text);

  /// 云端音色试听：强制走云合成，失败上抛具体原因（设置页展示）。
  Future<void> previewCloud(String text) async {
    await _refreshCloudState();
    if (_cloudClient == null || _cloudConfig == null) {
      throw const WorkerTtsException(
        '请先保存并验证自建语音服务',
        kind: WorkerTtsErrorKind.authentication,
      );
    }
    final bytes = await _synthesizeStrict(text);
    await _cloudPlayerResolved.play(bytes);
  }

  /// 验证自建服务配置（零成本空 text 探测，不产生真实合成）。
  ///
  /// 设置页专用入口：异常上抛由页面展示具体原因。
  Future<void> verifyCloud(WorkerTtsConfig config) async {
    final client = _cloudClient;
    if (client == null) {
      throw const WorkerTtsException(
        '语音服务客户端不可用',
        kind: WorkerTtsErrorKind.response,
      );
    }
    await client.verify(config);
  }

  /// 拉取云端音色目录（voices 端点无需认证）。
  ///
  /// 地址取自已保存的设置；失败上抛，调用方回退内置精选。
  Future<List<WorkerTtsVoice>> listCloudVoices() async {
    final client = _cloudClient;
    if (client == null) {
      throw const WorkerTtsException(
        '语音服务客户端不可用',
        kind: WorkerTtsErrorKind.response,
      );
    }
    return client.listVoices(
      WorkerTtsClient.normalizeBaseUrl(_settings.ttsCloudBaseUrl),
    );
  }

  /// 朗读文本（全文一次性读完）。
  Future<void> speak(String text) async {
    await _ensureInitialized();
    await _refreshCloudState();
    _isSpeaking = true;
    _stopRequested = false;
    _engineErrorMessage = null;

    try {
      await _speakSegmentBestEffort(text);
    } finally {
      _isSpeaking = false;
    }
  }

  /// 逐句朗读：按句号、问号、感叹号、逗号、换行分割，依次朗读。
  ///
  /// [onSentenceStart] 回调：传入当前朗读的句子索引。
  /// [onComplete] 在全部朗读完毕时调用。
  Future<void> speakSentences(
    String text, {
    void Function(int index)? onSentenceStart,
    void Function()? onComplete,
  }) async {
    await _ensureInitialized();
    await _refreshCloudState();
    _stopRequested = false;
    _engineErrorMessage = null;

    // 分割句子（按中文标点和换行）
    final sentences = text
        .split(RegExp(r'[。！？\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    var completed = false;
    _isSpeaking = true;
    try {
      for (var i = 0; i < sentences.length; i++) {
        if (_stopRequested) break;
        onSentenceStart?.call(i);
        await _speakSegmentBestEffort(sentences[i]);
      }
      completed = !_stopRequested;
    } finally {
      _isSpeaking = false;
    }

    if (completed) onComplete?.call();
  }

  /// 逐行朗读：调用方提供已拆分的行列表，确保索引与视觉行一一对应。
  ///
  /// [onLineStart] 回调：传入当前朗读的行索引。
  /// [onComplete] 在全部朗读完毕时调用。
  Future<void> speakLines(
    List<String> lines, {
    void Function(int index)? onLineStart,
    void Function()? onComplete,
  }) async {
    await _ensureInitialized();
    await _refreshCloudState();
    _stopRequested = false;
    _engineErrorMessage = null;

    var completed = false;
    _isSpeaking = true;
    try {
      for (var i = 0; i < lines.length; i++) {
        if (_stopRequested) break;
        onLineStart?.call(i);
        await _speakSegmentBestEffort(lines[i]);
      }
      completed = !_stopRequested;
    } finally {
      _isSpeaking = false;
    }

    if (completed) onComplete?.call();
  }

  /// 停止朗读（云端与系统引擎均停止）。
  Future<void> stop() async {
    _stopRequested = true;
    _isSpeaking = false;
    final player = _cloudPlayer;
    if (player != null) {
      try {
        await player.stop();
      } on Object catch (error) {
        AppLogger.w('停止云端播放失败（忽略）：$error', tag: _logTag);
      }
    }
    // 页面离开时可能从未启动过引擎；无需触发平台通道。
    if (!_initialized) return;
    await _runEngineOperation('停止朗读失败', _tts.stop);
  }

  /// 释放资源。
  void dispose() {
    _stopRequested = true;
    _isSpeaking = false;
    final player = _cloudPlayer;
    if (player != null) {
      unawaited(
        player.dispose().then<void>(
              (_) {},
              onError: (Object error, StackTrace stackTrace) {},
            ),
      );
    }
    unawaited(
      _tts.stop().then<void>(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {},
          ),
    );
  }
}

/// TTS 引擎初始化或调用失败。
class TtsException implements Exception {
  const TtsException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'TtsException: $message';
}
