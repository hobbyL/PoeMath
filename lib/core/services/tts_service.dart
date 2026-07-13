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

  /// 用户主动停止标志，仅 [stop] 方法设置，
  /// 避免 completionHandler 干扰 [speakLines] 循环。
  bool _stopRequested = false;

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

    // 注意：completionHandler 在每次 speak() 完成后触发，
    // 但在 speakLines/speakSentences 场景下不应中断循环，
    // 所以这里不再设置 _isSpeaking = false，改由各方法自行管理。

    _tts.setCancelHandler(() {
      _isSpeaking = false;
      _stopRequested = true;
    });

    _tts.setErrorHandler((msg) {
      _isSpeaking = false;
      _stopRequested = true;
    });

    _initialized = true;
  }

  /// 朗读文本（全文一次性读完）。
  Future<void> speak(String text) async {
    await _ensureInitialized();
    await _tts.setSpeechRate(_settings.ttsSpeed);
    _isSpeaking = true;
    _stopRequested = false;
    await _tts.speak(text);
    await _tts.awaitSpeakCompletion(true);
    _isSpeaking = false;
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
    _stopRequested = false;

    // 分割句子（按中文标点和换行）
    final sentences = text
        .split(RegExp(r'[。！？\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    _isSpeaking = true;
    for (var i = 0; i < sentences.length; i++) {
      if (_stopRequested) break;
      onSentenceStart?.call(i);
      await _tts.speak(sentences[i]);
      await _tts.awaitSpeakCompletion(true);
    }

    _isSpeaking = false;
    onComplete?.call();
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
    await _tts.setSpeechRate(_settings.ttsSpeed);
    _stopRequested = false;

    _isSpeaking = true;
    for (var i = 0; i < lines.length; i++) {
      if (_stopRequested) break;
      onLineStart?.call(i);
      await _tts.speak(lines[i]);
      await _tts.awaitSpeakCompletion(true);
    }

    _isSpeaking = false;
    onComplete?.call();
  }

  /// 停止朗读。
  Future<void> stop() async {
    _stopRequested = true;
    _isSpeaking = false;
    await _tts.stop();
  }

  /// 释放资源。
  void dispose() {
    _stopRequested = true;
    _isSpeaking = false;
    _tts.stop();
  }
}
