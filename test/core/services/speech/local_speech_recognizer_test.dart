import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/speech/local_speech_recognizer.dart';

void main() {
  group('Pcm16ChunkDecoder', () {
    test('按 little-endian 转换并归一化到 [-1, 1]', () {
      final decoder = Pcm16ChunkDecoder();

      final samples = decoder.decode(
        Uint8List.fromList(<int>[0x00, 0x80, 0x00, 0x00, 0xff, 0x7f]),
      );

      expect(samples, hasLength(3));
      expect(samples[0], -1.0);
      expect(samples[1], 0.0);
      expect(samples[2], closeTo(32767 / 32768, 0.000001));
    });

    test('保留跨 chunk 的奇数尾字节', () {
      final decoder = Pcm16ChunkDecoder();

      expect(decoder.decode(Uint8List.fromList(<int>[0x00])), isEmpty);
      final samples = decoder.decode(
        Uint8List.fromList(<int>[0x80, 0xff, 0x7f]),
      );

      expect(samples, hasLength(2));
      expect(samples[0], -1.0);
      expect(samples[1], closeTo(32767 / 32768, 0.000001));
    });

    test('reset 丢弃无法组成样本的尾字节', () {
      final decoder = Pcm16ChunkDecoder();
      decoder.decode(Uint8List.fromList(<int>[0x00]));

      decoder.reset();
      final samples = decoder.decode(Uint8List.fromList(<int>[0x00, 0x00]));

      expect(samples, <double>[0.0]);
    });
  });
}
