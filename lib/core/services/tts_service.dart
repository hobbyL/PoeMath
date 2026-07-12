// lib/core/services/tts_service.dart
//
// TTS 朗读服务：封装 flutter_tts，提供中文全文/逐句朗读。

import 'package:flutter_tts/flutter_tts.dart';

import 'package:poemath/data/repositories/settings_repository.dart';

/// TTS 朗读服务。
///
/// 使用 flutter_tts 实现中文语音合成。
/// 支持全文朗读和逐句朗读。
class TtsService {
  final FlutterTts _tts = FlutterTts();
  final SettingsRepository _settings;

  bool _initialized = false;
  bool _isSpeaking = false;

  TtsService(this._settings);

  /// 当前是否正在朗读。
  bool get isSpeaking => _isSpeaking;

  /// 初始化 TTS 引擎。
  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(_settings.ttsSpeed);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });

    _tts.setCancelHandler(() {
      _isSpeaking = false;
    });

    _tts.setErrorHandler((msg) {
      _isSpeaking = false;
    });

    _initialized = true;
  }

  /// 朗读文本（全文一次性读完）。
  Future<void> speak(String text) async {
    await _ensureInitialized();
    await _tts.setSpeechRate(_settings.ttsSpeed);
    _isSpeaking = true;
    await _tts.speak(text);
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
    await _tts.setSpeechRate(_settings.ttsSpeed);

    // 分割句子（按中文标点和换行）
    final sentences = text
        .split(RegExp(r'[。！？\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    for (var i = 0; i < sentences.length; i++) {
      onSentenceStart?.call(i);
      _isSpeaking = true;
      await _tts.speak(sentences[i]);
      // 等待当前句子朗读完毕
      await _tts.awaitSpeakCompletion(true);
    }

    _isSpeaking = false;
    onComplete?.call();
  }

  /// 停止朗读。
  Future<void> stop() async {
    _isSpeaking = false;
    await _tts.stop();
  }

  /// 释放资源。
  void dispose() {
    _tts.stop();
    _isSpeaking = false;
  }
}
