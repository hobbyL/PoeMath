import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class PictureStoryAudioService {
  Future<String> savePcm16({required String id, required Uint8List pcm}) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/picture_story_audio');
    await directory.create(recursive: true);
    final file = File('${directory.path}/$id.wav');
    await file.writeAsBytes(_wavBytes(pcm), flush: true);
    return file.path;
  }

  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Uint8List _wavBytes(Uint8List pcm) {
    final dataLength = pcm.length;
    final bytes = ByteData(44 + dataLength);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    bytes.setUint32(4, 36 + dataLength, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, 16000, Endian.little);
    bytes.setUint32(28, 32000, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, dataLength, Endian.little);
    for (var i = 0; i < pcm.length; i++) {
      bytes.setUint8(44 + i, pcm[i]);
    }
    return bytes.buffer.asUint8List();
  }
}
