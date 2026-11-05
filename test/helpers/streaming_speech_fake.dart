import 'dart:async';

import 'package:poemath/core/services/speech/preferred_speech_recognition_service.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_speech_recognition_service.dart';

/// Lets page tests deliver revisions while the final result is still pending.
class StreamingSpeechFake
    implements SpeechRecognitionService, StreamingSpeechRecognitionService {
  final transcripts = StreamController<String>.broadcast();
  Completer<SpeechRecognitionResult>? pendingResult;
  String finalText = '床前明月光';
  String? startText;
  int starts = 0;
  int stops = 0;
  int cancels = 0;
  int disposals = 0;

  @override
  bool isRecording = false;

  @override
  bool usedFallback = false;

  @override
  String get recognitionMode => usedFallback ? 'sentence' : 'realtime';

  @override
  Stream<String> get transcriptStream => transcripts.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> start() async {
    starts++;
    isRecording = true;
    if (startText case final text?) transcripts.add(text);
  }

  @override
  Future<SpeechRecognitionResult> stop() async {
    stops++;
    isRecording = false;
    return pendingResult?.future ??
        SpeechRecognitionResult(
          text: finalText,
          mode: recognitionMode,
          usedFallback: usedFallback,
        );
  }

  @override
  Future<void> cancel() async {
    cancels++;
    isRecording = false;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    await cancel();
    await transcripts.close();
  }
}
