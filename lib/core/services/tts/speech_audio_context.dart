import 'package:audioplayers/audioplayers.dart';

/// 每次朗读重新声明媒体播放用途，恢复录音等操作可能改变的音频会话。
/// 不修改设备音量，也不强制把耳机切换到扬声器。
AudioContext speechAudioContext() => AudioContext(
  android: const AudioContextAndroid(
    contentType: AndroidContentType.speech,
    usageType: AndroidUsageType.media,
  ),
  iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
);
