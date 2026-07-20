// lib/core/services/tts_service.dart
//
// TTS 朗读服务：封装 flutter_tts，提供中文全文/逐句朗读。

import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'package:poemath/data/repositories/settings_repository.dart';

/// TTS 朗读服务。
///
/// 使用 flutter_tts 实现中文语音合成。
/// 支持全文朗读和逐句朗读，以及音色选择。
class TtsService {
  final FlutterTts _tts;
  final SettingsRepository _settings;

  bool _initialized = false;
  bool _isSpeaking = false;
  String? _engineErrorMessage;

  /// 用户主动停止标志，仅 [stop] 方法设置，
  /// 避免 completionHandler 干扰 [speakLines] 循环。
  bool _stopRequested = false;

  TtsService(this._settings, {FlutterTts? flutterTts})
      : _tts = flutterTts ?? FlutterTts();

  /// 当前是否正在朗读。
  bool get isSpeaking => _isSpeaking;

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

  /// 设置音色并保存到设置。传 null 恢复系统默认。
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

  /// 试听当前音色：朗读一段示例文本。
  Future<void> preview(String text) => speak(text);

  /// 朗读文本（全文一次性读完）。
  Future<void> speak(String text) async {
    await _ensureInitialized();
    _isSpeaking = true;
    _stopRequested = false;
    _engineErrorMessage = null;

    try {
      await _runEngineOperation('朗读失败', () async {
        await _tts.setSpeechRate(_settings.ttsSpeed);
        await _tts.speak(text);
        _throwIfEngineReportedError();
      });
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
      await _runEngineOperation(
        '逐句朗读失败',
        () => _tts.setSpeechRate(_settings.ttsSpeed),
      );
      for (var i = 0; i < sentences.length; i++) {
        if (_stopRequested) break;
        onSentenceStart?.call(i);
        await _runEngineOperation(
          '逐句朗读失败',
          () => _tts.speak(sentences[i]),
        );
        _throwIfEngineReportedError();
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
    _stopRequested = false;
    _engineErrorMessage = null;

    var completed = false;
    _isSpeaking = true;
    try {
      await _runEngineOperation(
        '逐行朗读失败',
        () => _tts.setSpeechRate(_settings.ttsSpeed),
      );
      for (var i = 0; i < lines.length; i++) {
        if (_stopRequested) break;
        onLineStart?.call(i);
        await _runEngineOperation(
          '逐行朗读失败',
          () => _tts.speak(lines[i]),
        );
        _throwIfEngineReportedError();
      }
      completed = !_stopRequested;
    } finally {
      _isSpeaking = false;
    }

    if (completed) onComplete?.call();
  }

  /// 停止朗读。
  Future<void> stop() async {
    _stopRequested = true;
    _isSpeaking = false;
    await _runEngineOperation('停止朗读失败', _tts.stop);
  }

  /// 释放资源。
  void dispose() {
    _stopRequested = true;
    _isSpeaking = false;
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
