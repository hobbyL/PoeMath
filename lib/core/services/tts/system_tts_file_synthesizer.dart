import 'dart:io';
import 'package:flutter/services.dart';

class NarrationException implements Exception {
  const NarrationException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class SystemTtsFileSynthesizer {
  Future<String> describeVoice(Map<String, String>? voice, double speed);
  Future<Uint8List> synthesize({
    required int sessionId,
    required String text,
    required Map<String, String>? voice,
    required double speed,
  });
  Future<void> cancelSession(int sessionId);
  Future<void> dispose();
}

class AndroidSystemTtsFileSynthesizer implements SystemTtsFileSynthesizer {
  AndroidSystemTtsFileSynthesizer({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel('com.poemath.app/textbook_tts');
  final MethodChannel _channel;
  int _request = 0;
  @override
  Future<String> describeVoice(Map<String, String>? voice, double speed) async {
    try {
      final identity = await _channel.invokeMethod<String>(
        'describeVoice',
        {'voice': voice, 'speed': speed},
      );
      if (identity == null || identity.isEmpty) {
        throw const NarrationException('系统音色不可用，请在声音设置中检查音色');
      }
      return identity;
    } on PlatformException {
      throw const NarrationException('系统音色不可用，请在声音设置中检查音色');
    } on MissingPluginException {
      throw const NarrationException('此设备暂不支持教材系统音频生成');
    }
  }

  @override
  Future<Uint8List> synthesize({
    required int sessionId,
    required String text,
    required Map<String, String>? voice,
    required double speed,
  }) async {
    File? file;
    try {
      final path = await _channel.invokeMethod<String>('synthesize', {
        'sessionId': sessionId,
        'requestId': ++_request,
        'text': text,
        'voice': voice,
        'speed': speed,
      });
      if (path == null) throw const NarrationException('系统音频生成失败');
      file = File(path);
      if (await file.length() > 32 * 1024 * 1024) {
        throw const NarrationException('系统音频过长，请核对课文内容');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length < 12 ||
          String.fromCharCodes(bytes.take(4)) != 'RIFF' ||
          String.fromCharCodes(bytes.skip(8).take(4)) != 'WAVE') {
        throw const NarrationException('系统返回了无效的音频');
      }
      return bytes;
    } on PlatformException catch (error) {
      if (error.code == 'INVALID_TEXT') {
        throw const NarrationException('正文超过语音引擎限制，请在内容审核中核对或调整段落');
      }
      throw const NarrationException('系统音频生成失败，请稍后重试');
    } on IOException {
      throw const NarrationException('系统音频读取失败，请稍后重试');
    } on MissingPluginException {
      throw const NarrationException('此设备暂不支持教材系统音频生成');
    } finally {
      if (file != null) {
        try {
          if (await file.exists()) await file.delete();
        } on IOException {/* 私有临时文件由系统清理 */}
      }
    }
  }

  @override
  Future<void> cancelSession(int sessionId) async {
    try {
      await _channel
          .invokeMethod<void>('cancelSession', {'sessionId': sessionId});
    } on PlatformException {
      /* 幂等取消，Dart 会话仍会丢弃晚到结果 */
    } on MissingPluginException {/* 尚未使用原生引擎 */}
  }

  @override
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod<void>('dispose');
    } on PlatformException {/* 引擎释放 */} on MissingPluginException {/* 未注册 */}
  }
}
