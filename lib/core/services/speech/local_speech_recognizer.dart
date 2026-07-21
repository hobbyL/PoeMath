// lib/core/services/speech/local_speech_recognizer.dart

import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'package:poemath/core/services/speech/speech_model_manager.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';

abstract interface class LocalSpeechRecognizer {
  Future<void> initialize();

  Future<void> start();

  Future<String> acceptPcm(Uint8List bytes);

  Future<String> finish();

  Future<void> cancel();

  Future<void> dispose();
}

final class SherpaLocalSpeechRecognizer implements LocalSpeechRecognizer {
  SherpaLocalSpeechRecognizer({SpeechModelManager? modelManager})
      : _modelManager = modelManager ?? SpeechModelManager();

  static const int sampleRate = 16000;
  static bool _bindingsInitialized = false;

  final SpeechModelManager _modelManager;
  sherpa_onnx.OnlineRecognizer? _recognizer;
  sherpa_onnx.OnlineStream? _stream;
  Future<void>? _initializeFuture;
  final Pcm16ChunkDecoder _pcmDecoder = Pcm16ChunkDecoder();

  @override
  Future<void> initialize() {
    return _initializeFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      final paths = await _modelManager.prepare();
      if (!_bindingsInitialized) {
        sherpa_onnx.initBindings();
        _bindingsInitialized = true;
      }

      final model = sherpa_onnx.OnlineModelConfig(
        transducer: sherpa_onnx.OnlineTransducerModelConfig(
          encoder: paths.encoder,
          decoder: paths.decoder,
          joiner: paths.joiner,
        ),
        tokens: paths.tokens,
        numThreads: 1,
        provider: 'cpu',
        debug: false,
      );
      _recognizer = sherpa_onnx.OnlineRecognizer(
        sherpa_onnx.OnlineRecognizerConfig(
          model: model,
          enableEndpoint: false,
        ),
      );
    } on SpeechRecognitionException {
      rethrow;
    } on Object {
      _initializeFuture = null;
      throw const SpeechRecognitionException('离线语音模型初始化失败');
    }
  }

  @override
  Future<void> start() async {
    await initialize();
    await cancel();
    final recognizer = _recognizer;
    if (recognizer == null) {
      throw const SpeechRecognitionException('离线语音模型尚未就绪');
    }
    _stream = recognizer.createStream();
    _pcmDecoder.reset();
  }

  @override
  Future<String> acceptPcm(Uint8List bytes) async {
    final recognizer = _recognizer;
    final stream = _stream;
    if (recognizer == null || stream == null) {
      throw const SpeechRecognitionException('离线语音识别尚未开始');
    }

    final samples = _pcmDecoder.decode(bytes);
    if (samples.isNotEmpty) {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      _decodeReady(recognizer, stream);
    }
    return recognizer.getResult(stream).text.trim();
  }

  static void _decodeReady(
    sherpa_onnx.OnlineRecognizer recognizer,
    sherpa_onnx.OnlineStream stream,
  ) {
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }
  }

  @override
  Future<String> finish() async {
    final recognizer = _recognizer;
    final stream = _stream;
    if (recognizer == null || stream == null) {
      throw const SpeechRecognitionException('离线语音识别尚未开始');
    }

    _pcmDecoder.reset();
    stream.inputFinished();
    _decodeReady(recognizer, stream);
    final text = recognizer.getResult(stream).text.trim();
    stream.free();
    _stream = null;
    return text;
  }

  @override
  Future<void> cancel() async {
    _pcmDecoder.reset();
    _stream?.free();
    _stream = null;
  }

  @override
  Future<void> dispose() async {
    await cancel();
    _recognizer?.free();
    _recognizer = null;
    _initializeFuture = null;
  }
}

/// Converts chunked little-endian PCM16 data to normalized mono Float32.
///
/// A recorder stream is allowed to split a sample across two chunks, so the
/// decoder retains one trailing byte until the next call. An incomplete final
/// byte is intentionally discarded.
final class Pcm16ChunkDecoder {
  int? _pendingByte;

  Float32List decode(Uint8List bytes) {
    if (bytes.isEmpty && _pendingByte == null) return Float32List(0);

    final leading = _pendingByte;
    final combinedLength = bytes.length + (leading == null ? 0 : 1);
    final combined = Uint8List(combinedLength);
    var offset = 0;
    if (leading != null) {
      combined[0] = leading;
      offset = 1;
    }
    combined.setRange(offset, combined.length, bytes);

    final evenLength = combined.length - (combined.length.isOdd ? 1 : 0);
    _pendingByte = combined.length.isOdd ? combined.last : null;
    if (evenLength == 0) return Float32List(0);

    final data = ByteData.sublistView(combined, 0, evenLength);
    final samples = Float32List(evenLength ~/ 2);
    for (var index = 0; index < samples.length; index++) {
      samples[index] = data.getInt16(index * 2, Endian.little) / 32768.0;
    }
    return samples;
  }

  void reset() {
    _pendingByte = null;
  }
}
