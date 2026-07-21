// lib/core/services/speech/speech_audio_recorder.dart

import 'dart:typed_data';

import 'package:record/record.dart';

abstract interface class SpeechAudioRecorder {
  Future<bool> hasPermission();

  Future<Stream<Uint8List>> startStream();

  Future<void> stop();

  Future<void> cancel();

  Future<void> dispose();
}

/// PCM16/16 kHz/mono recorder shared by local and cloud recognition.
final class RecordSpeechAudioRecorder implements SpeechAudioRecorder {
  RecordSpeechAudioRecorder({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> startStream() {
    return _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
  }

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}
