// lib/core/services/tts/tts_models.dart
//
// 腾讯云语音合成模型：精选精品音色目录、错误类型与云端音频播放抽象。

import 'dart:async';

import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// 腾讯云 TTS 错误分类。
enum TencentTtsErrorKind {
  /// 密钥无效或无权限。
  authentication,

  /// 免费额度耗尽、资源包用尽或账户欠费。
  quota,

  /// 语音合成服务未开通。
  serviceNotEnabled,

  /// 请求参数不合法。
  request,

  /// 网络不可用或超时。
  network,

  /// 服务返回数据无效。
  response,
}

/// 腾讯云语音合成异常。
final class TencentTtsException implements Exception {
  const TencentTtsException(
    this.message, {
    required this.kind,
    this.code,
    this.statusCode,
  });

  final String message;
  final TencentTtsErrorKind kind;
  final String? code;
  final int? statusCode;

  @override
  String toString() => 'TencentTtsException: $message';
}

/// 精选腾讯云精品音色。
///
/// ID 来自腾讯云音色列表（基础/精品音色，免费额度 800 万字符）。
final class TencentTtsVoice {
  const TencentTtsVoice({
    required this.id,
    required this.name,
    required this.style,
  });

  /// 腾讯云 VoiceType 编号。
  final int id;

  /// 展示名。
  final String name;

  /// 风格描述。
  final String style;
}

/// 设置页可选的云端音色目录（硬编码精选，ID 稳定）。
const List<TencentTtsVoice> kTencentPremiumVoices = <TencentTtsVoice>[
  TencentTtsVoice(id: 101001, name: '智瑜', style: '温柔女声 · 适合诗词范读'),
  TencentTtsVoice(id: 101002, name: '智灵', style: '亲切女声 · 通用朗读'),
  TencentTtsVoice(id: 101004, name: '智芸', style: '温暖女声 · 讲故事'),
  TencentTtsVoice(id: 101018, name: '智靖', style: '沉稳男声 · 朗诵'),
  TencentTtsVoice(id: 101020, name: '智刚', style: '有力男声 · 朗读'),
];

/// 默认云端音色：智瑜。
const int kDefaultTencentVoiceType = 101001;

/// 云端合成音频播放抽象（便于测试替换）。
abstract interface class CloudAudioPlayer {
  /// 播放音频字节，完成即返回。
  Future<void> play(Uint8List bytes);

  Future<void> stop();

  Future<void> dispose();
}

/// 基于 audioplayers 的生产实现。
///
/// audioplayers 的 `play()` Future 在播放启动时完成，播放结束需组合
/// `onPlayerComplete` stream 等待。`stop()` 会放行挂起的 `play()`
/// （stop 中断不触发 onPlayerComplete）；超时兜底防止底层异常导致永久挂起。
final class AudioplayersCloudAudioPlayer implements CloudAudioPlayer {
  AudioplayersCloudAudioPlayer({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  static const _completionTimeout = Duration(seconds: 90);

  final AudioPlayer _player;
  Completer<void>? _session;

  void _completeSession() {
    final session = _session;
    if (session != null && !session.isCompleted) session.complete();
    _session = null;
  }

  @override
  Future<void> play(Uint8List bytes) async {
    await stop();
    final session = Completer<void>();
    _session = session;
    final subscription = _player.onPlayerComplete.listen((_) {
      if (!session.isCompleted) session.complete();
    });
    try {
      await _player.play(BytesSource(bytes));
      await session.future.timeout(_completionTimeout);
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<void> stop() async {
    _completeSession();
    await _player.stop();
  }

  @override
  Future<void> dispose() async {
    _completeSession();
    await _player.dispose();
  }
}
