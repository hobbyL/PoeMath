import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/speech/speech_model_manager.dart';

final class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this.assets);

  final Map<String, Uint8List> assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = assets[key];
    if (bytes == null) throw StateError('missing asset: $key');
    return ByteData.sublistView(bytes);
  }
}

void main() {
  test('将四个必需模型 asset 复制到应用私有目录并复用结果', () async {
    final directory = await Directory.systemTemp.createTemp('speech_model_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final assets = <String, Uint8List>{
      for (final entry in <String, List<int>>{
        SpeechModelManager.encoderFile: <int>[1, 2],
        SpeechModelManager.decoderFile: <int>[3, 4],
        SpeechModelManager.joinerFile: <int>[5, 6],
        SpeechModelManager.tokensFile: <int>[7, 8],
      }.entries)
        '${SpeechModelManager.assetDirectory}/${entry.key}':
            Uint8List.fromList(entry.value),
    };
    final manager = SpeechModelManager(
      assetBundle: _MemoryAssetBundle(assets),
      supportDirectoryProvider: () async => directory,
    );

    final first = await manager.prepare();
    final second = await manager.prepare();

    expect(first.encoder, second.encoder);
    expect(await File(first.encoder).readAsBytes(), <int>[1, 2]);
    expect(await File(first.decoder).readAsBytes(), <int>[3, 4]);
    expect(await File(first.joiner).readAsBytes(), <int>[5, 6]);
    expect(await File(first.tokens).readAsBytes(), <int>[7, 8]);
  });
}
