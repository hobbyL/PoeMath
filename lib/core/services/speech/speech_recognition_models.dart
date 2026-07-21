// lib/core/services/speech/speech_recognition_models.dart
//
// Shared contracts for local and Tencent Cloud speech recognition.

/// Tencent Cloud API credentials.
///
/// The values must never be persisted outside platform secure storage or
/// included in logs and exception messages.
final class TencentAsrCredentials {
  const TencentAsrCredentials({
    required this.secretId,
    required this.secretKey,
  });

  final String secretId;
  final String secretKey;

  bool get isComplete => secretId.isNotEmpty && secretKey.isNotEmpty;

  @override
  String toString() => 'TencentAsrCredentials(<redacted>)';
}

/// Effective speech-recognition settings after secure-storage validation.
final class SpeechRecognitionSettingsState {
  const SpeechRecognitionSettingsState({
    required this.hasCredentials,
    required this.isVerified,
    required this.highAccuracyEnabled,
    this.verifiedAt,
  });

  final bool hasCredentials;
  final bool isVerified;
  final bool highAccuracyEnabled;
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

enum SpeechRecognitionSource { local, tencentCloud }

/// Final result for one recorded utterance.
final class SpeechRecognitionResult {
  const SpeechRecognitionResult({
    required this.text,
    required this.localText,
    required this.source,
    this.fellBackFromCloud = false,
  });

  final String text;
  final String localText;
  final SpeechRecognitionSource source;
  final bool fellBackFromCloud;

  bool get usedTencentCloud => source == SpeechRecognitionSource.tencentCloud;
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
