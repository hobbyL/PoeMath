// lib/core/services/tts/tts_models.dart
//
// 自建 Worker 语音合成模型：音色目录、错误类型、映射函数与云端音频播放抽象。

import 'dart:async';

import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// 自建 Worker TTS 错误分类。
enum WorkerTtsErrorKind {
  /// API Key 无效或未提供（401）。
  authentication,

  /// 请求参数不合法（400，服务端 message 透传）。
  request,

  /// 网络不可用或超时。
  network,

  /// 服务返回数据无效（5xx / 非 audio 响应）。
  response,
}

/// 自建 Worker 语音合成异常。
///
/// `toString()` 与 message 均不得包含 API Key。
final class WorkerTtsException implements Exception {
  const WorkerTtsException(
    this.message, {
    required this.kind,
    this.statusCode,
  });

  final String message;
  final WorkerTtsErrorKind kind;
  final int? statusCode;

  @override
  String toString() => 'WorkerTtsException: $message';
}

/// Worker 音色（`/api/v1/voices` 响应条目）。
final class WorkerTtsVoice {
  const WorkerTtsVoice({
    required this.shortName,
    required this.localName,
    required this.gender,
    required this.styleList,
    this.presetStyle,
  });

  /// 音色标识（如 `zh-CN-XiaoxiaoNeural`）。
  final String shortName;

  /// 展示名（如「晓晓」；DragonHD 音色可能为英文描述）。
  final String localName;

  /// `Female` / `Male`。
  final String gender;

  /// 支持的风格列表。
  final List<String> styleList;

  /// 内置精选目录的预设风格（动态列表为 null，选中时计算）。
  final String? presetStyle;

  /// shortName 含 `DragonHD` 即为新一代高清音色。
  bool get isDragonHd => shortName.contains('DragonHD');

  /// 该音色的最佳朗读风格：预设优先，否则按优先级从 styleList 匹配。
  String get bestStyle =>
      presetStyle ?? bestStyleFor(styleList, fallback: 'general');
}

/// 自建 Worker 服务配置（地址 + API Key）。
final class WorkerTtsConfig {
  const WorkerTtsConfig({required this.base, required this.apiKey});

  /// 服务根地址（已规范化，无尾斜杠）。
  final Uri base;

  /// API Key（仅存安全存储，不入 Hive / 备份 / 日志）。
  final String apiKey;

  bool get isComplete => base.host.isNotEmpty && apiKey.isNotEmpty;
}

/// 默认服务地址（家长自建 Worker，可修改）。
const String kDefaultWorkerBaseUrl = 'https://tts.cloudm.cc';

/// 默认云端音色：晓晓。
const String kDefaultWorkerVoice = 'zh-CN-XiaoxiaoNeural';

/// 音频格式：服务端格式表内、含 mp3 满足长文本分段合并、优于默认 48kbps。
const String kWorkerAudioFormat = 'audio-24khz-96kbitrate-mono-mp3';

/// 在线音色拉取失败时的内置精选目录（含预设风格）。
const List<WorkerTtsVoice> kWorkerFallbackVoices = <WorkerTtsVoice>[
  WorkerTtsVoice(
    shortName: 'zh-CN-XiaoxiaoNeural',
    localName: '晓晓',
    gender: 'Female',
    styleList: ['poetry-reading'],
    presetStyle: 'poetry-reading',
  ),
  WorkerTtsVoice(
    shortName: 'zh-CN-XiaoyiNeural',
    localName: '晓伊',
    gender: 'Female',
    styleList: ['gentle'],
    presetStyle: 'gentle',
  ),
  WorkerTtsVoice(
    shortName: 'zh-CN-YunxiNeural',
    localName: '云希',
    gender: 'Male',
    styleList: ['narration-relaxed'],
    presetStyle: 'narration-relaxed',
  ),
  WorkerTtsVoice(
    shortName: 'zh-CN-YunjianNeural',
    localName: '云健',
    gender: 'Male',
    styleList: ['narration-relaxed'],
    presetStyle: 'narration-relaxed',
  ),
  WorkerTtsVoice(
    shortName: 'zh-CN-YunyangNeural',
    localName: '云扬',
    gender: 'Male',
    styleList: ['narration-professional'],
    presetStyle: 'narration-professional',
  ),
];

/// 应用内语速 [0.1, 1.0]（0.5 = 正常）映射为 Worker 百分比 rate 字符串。
///
/// 分段线性：0.1 → `"-50"`、0.5 → `"0"`、1.0 → `"+100"`。
/// 服务端 normalizePercent 接受 `+n` / `-n` / `n` 带符号整数字符串。
String workerRateFor(double speed) {
  final clamped = speed.clamp(0.1, 1.0);
  final int percent;
  if (clamped <= 0.5) {
    // [0.1, 0.5] → [-50, 0]
    percent = (-50 + (clamped - 0.1) / 0.4 * 50).round();
  } else {
    // (0.5, 1.0] → (0, 100]
    percent = ((clamped - 0.5) / 0.5 * 100).round();
  }
  if (percent == 0) return '0';
  final sign = percent > 0 ? '+' : '-';
  return '$sign${percent.abs()}';
}

/// 从风格列表按优先级匹配最佳朗读风格：
/// poetry-reading → gentle → narration-relaxed → narration-professional → chat。
/// 全部缺失时返回 [fallback]（默认 `general`）。
String bestStyleFor(
  List<String> styleList, {
  String fallback = 'general',
}) {
  const priority = <String>[
    'poetry-reading',
    'gentle',
    'narration-relaxed',
    'narration-professional',
    'chat',
  ];
  for (final style in priority) {
    if (styleList.contains(style)) return style;
  }
  return fallback;
}

/// 风格中文标签（设置页展示用）。
String workerStyleLabel(String style) {
  return switch (style) {
    'poetry-reading' => '诗词范读',
    'gentle' => '温柔',
    'narration-relaxed' => '轻松讲述',
    'narration-professional' => '专业播报',
    'chat' => '对话',
    'general' => '通用',
    _ => style,
  };
}

/// gender → 中文标签。
String workerGenderLabel(String gender) {
  if (gender.toLowerCase().startsWith('f')) return '女声';
  if (gender.toLowerCase().startsWith('m')) return '男声';
  return gender;
}

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

  /// 全文合成时服务端按句分段、并发合成并合并 MP3，产生的长音频
  /// 播放时长可超过 90 秒，因此超时上限取 300 秒。
  static const _completionTimeout = Duration(seconds: 300);

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
