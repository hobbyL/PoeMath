// lib/core/services/speech/speech_model_manager.dart

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

final class SpeechModelPaths {
  const SpeechModelPaths({
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
  });

  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;
}

/// Copies bundled ONNX assets into an application-private directory.
///
/// Sherpa-ONNX requires real filesystem paths and cannot load Flutter asset
/// keys directly.
final class SpeechModelManager {
  SpeechModelManager({
    AssetBundle? assetBundle,
    Future<Directory> Function()? supportDirectoryProvider,
  })  : _assetBundle = assetBundle ?? rootBundle,
        _supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory;

  static const String assetDirectory = 'assets/models/sherpa_onnx_zh14m';
  static const String encoderFile = 'encoder-epoch-99-avg-1.int8.onnx';
  static const String decoderFile = 'decoder-epoch-99-avg-1.onnx';
  static const String joinerFile = 'joiner-epoch-99-avg-1.int8.onnx';
  static const String tokensFile = 'tokens.txt';

  final AssetBundle _assetBundle;
  final Future<Directory> Function() _supportDirectoryProvider;
  Future<SpeechModelPaths>? _prepareFuture;

  Future<SpeechModelPaths> prepare() async {
    final existing = _prepareFuture;
    if (existing != null) return existing;

    final future = _prepareFiles();
    _prepareFuture = future;
    try {
      return await future;
    } on Object {
      if (identical(_prepareFuture, future)) {
        _prepareFuture = null;
      }
      rethrow;
    }
  }

  Future<SpeechModelPaths> _prepareFiles() async {
    final supportDirectory = await _supportDirectoryProvider();
    final modelDirectory = Directory(
      '${supportDirectory.path}/speech_models/sherpa_onnx_zh14m',
    );
    await modelDirectory.create(recursive: true);

    final encoder = await _copyAsset(modelDirectory, encoderFile);
    final decoder = await _copyAsset(modelDirectory, decoderFile);
    final joiner = await _copyAsset(modelDirectory, joinerFile);
    final tokens = await _copyAsset(modelDirectory, tokensFile);

    return SpeechModelPaths(
      encoder: encoder.path,
      decoder: decoder.path,
      joiner: joiner.path,
      tokens: tokens.path,
    );
  }

  Future<File> _copyAsset(Directory directory, String fileName) async {
    final data = await _assetBundle.load('$assetDirectory/$fileName');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final destination = File('${directory.path}/$fileName');

    if (await destination.exists() &&
        await destination.length() == bytes.length) {
      return destination;
    }

    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await destination.exists()) {
      await destination.delete();
    }
    await temporary.rename(destination.path);
    return destination;
  }
}
