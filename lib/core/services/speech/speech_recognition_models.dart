// lib/core/services/speech/speech_recognition_models.dart
//
// Shared contracts for Tencent Cloud speech recognition.

import 'dart:async';

/// Tencent Cloud API credentials.
///
/// The values must never be persisted outside platform secure storage or
/// included in logs and exception messages.
final class TencentAsrCredentials {
  const TencentAsrCredentials({
    required this.secretId,
    required this.secretKey,
    this.appId = '',
  });

  final String secretId;
  final String secretKey;
  final String appId;

  bool get isComplete => secretId.isNotEmpty && secretKey.isNotEmpty;

  bool get hasRealtimeCredentials => isComplete && appId.trim().isNotEmpty;

  @override
  String toString() => 'TencentAsrCredentials(<redacted>)';
}

/// Effective speech-recognition settings after secure-storage validation.
///
/// [isVerified] is the single gate for read-along: credentials exist, the
/// stored fingerprint matches them, and a real-recording test has passed.
final class SpeechRecognitionSettingsState {
  const SpeechRecognitionSettingsState({
    required this.hasCredentials,
    required this.isVerified,
    this.verifiedAt,
  });

  final bool hasCredentials;
  final bool isVerified;
  final DateTime? verifiedAt;
}

/// Credentials and their effective gate state loaded from one secure read.
final class SpeechRecognitionSettingsSnapshot {
  const SpeechRecognitionSettingsSnapshot({
    required this.credentials,
    required this.settings,
  });

  final TencentAsrCredentials? credentials;
  final SpeechRecognitionSettingsState settings;
}

/// Final result for one recorded utterance.
final class SpeechRecognitionResult {
  const SpeechRecognitionResult({
    required this.text,
    this.mode = 'sentence',
    this.usedFallback = false,
  });

  final String text;
  final String mode;
  final bool usedFallback;
}

class SpeechRecognitionException implements Exception {
  const SpeechRecognitionException(this.message);

  final String message;

  @override
  String toString() => 'SpeechRecognitionException: $message';
}

final class SpeechPermissionDeniedException extends SpeechRecognitionException {
  const SpeechPermissionDeniedException() : super('未获得麦克风权限');
}

final class SpeechRecognitionCancelled extends SpeechRecognitionException {
  const SpeechRecognitionCancelled() : super('录音已取消');
}

/// 一次录音的取消状态，同时用于等待中断和单请求 HTTP abort。
final class SpeechRecognitionCancelToken {
  final _aborted = Completer<void>();
  bool _cancelled = false;

  bool get isCancelled => _cancelled;
  Future<void> get abortTrigger => _aborted.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _aborted.complete();
  }

  void check() {
    if (_cancelled) throw const SpeechRecognitionCancelled();
  }

  Future<T> wait<T>(Future<T> operation) async {
    final result = await Future.any<T>([
      operation,
      abortTrigger.then<T>((_) => throw const SpeechRecognitionCancelled()),
    ]);
    check();
    return result;
  }
}
