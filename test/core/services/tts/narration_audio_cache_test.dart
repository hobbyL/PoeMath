import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/tts/narration_audio_cache.dart';

void main() {
  late Directory directory;
  late NarrationAudioCache cache;
  final book = List.filled(64, 'a').join();
  final key = NarrationAudioCache.key(['voice', 'text']);
  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('poemath-narration-cache-');
    cache = NarrationAudioCache(
        directoryProvider: () async => directory, maxBytes: 20,);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  test('写入、重开命中和字节降级均保留实际来源/音频摘要', () async {
    final bytes = Uint8List.fromList([7, 8, 9]);
    final generated = await cache.obtain(book, key, 'wav', backend: NarrationBackend.system,
      revision: 0, isCurrent: () => true, generate: () async => bytes,);
    expect(generated.identity!.audioSha256, sha256.convert(bytes).toString());
    final expected = generated.identity!.signature; generated.release();
    final hit = await NarrationAudioCache(directoryProvider: () async => directory).read(book, key, 'wav', backend: NarrationBackend.system);
    expect(hit!.identity!.signature, expected); hit.release();
    final blocker = File('${directory.path}/blocked'); await blocker.writeAsString('blocked');
    final fallback = await NarrationAudioCache(directoryProvider: () async => Directory(blocker.path)).store(book, key, 'mp3', bytes,
      backend: NarrationBackend.cloud, revision: 0, isCurrent: () => true,);
    expect(fallback.path, isNull); expect(fallback.identity!.backend, NarrationBackend.cloud);
    expect(fallback.identity!.audioSha256, sha256.convert(bytes).toString());
  });
  test('完整文件跨实例命中，损坏缓存重新生成；不同身份不串用', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final first = await cache.store(book, key, 'mp3', bytes,
        revision: 0, isCurrent: () => true,);
    first.release();
    final restored = NarrationAudioCache(
        directoryProvider: () async => directory, maxBytes: 20,);
    final hit = await restored.read(book, key, 'mp3');
    expect(await File(hit!.path!).readAsBytes(), bytes);
    hit.release();
    expect(
        await restored.read(
            book, NarrationAudioCache.key(['otherVoice', 'text']), 'mp3',),
        isNull,);
    await File(first.path!).writeAsBytes([9, 9, 9, 9]);
    expect(await restored.read(book, key, 'mp3'), isNull);
  });
  test('容量淘汰旧文件，不删除活跃租约', () async {
    final first = await cache.store(book, key, 'mp3', Uint8List(12),
        revision: 0, isCurrent: () => true,);
    final key2 = NarrationAudioCache.key(['second']);
    final second = await cache.store(book, key2, 'wav', Uint8List(12),
        revision: 0, isCurrent: () => true,);
    expect(await File(first.path!).exists(), true);
    expect(await File(second.path!).exists(), true);
    first.release();
    await cache.clearBook(List.filled(64, 'b').join()); // 等待同一清理队列。
    expect(await File(first.path!).exists(), false);
    expect(await File(second.path!).exists(), true);
    second.release();
  });
  test('并发同键只生成一次，原书清理期间晚到音频不复活', () async {
    final gate = Completer<Uint8List>();
    var generated = 0;
    Future<NarrationAudio> obtain() => cache.obtain(
          book,
          key,
          'mp3',
          revision: 0,
          isCurrent: () => true,
          generate: () {
            generated++;
            return gate.future;
          },
        );
    final one = obtain();
    final two = obtain();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(generated, 1);
    await cache.clearBook(book);
    gate.complete(Uint8List.fromList([1, 2, 3]));
    final audio = await Future.wait([one, two]);
    expect(audio.map((a) => a.path), [null, null]);
    expect(await cache.read(book, key, 'mp3'), isNull);
    for (final a in audio) {
      a.release();
    }
  });
  test('写入不可用仍返回本次可播放的音频字节', () async {
    final blocker = File('${directory.path}/file');
    await blocker.writeAsString('occupied');
    final broken = NarrationAudioCache(
        directoryProvider: () async => Directory(blocker.path),);
    final bytes = Uint8List.fromList([3, 2, 1]);
    final result = await broken.store(book, key, 'wav', bytes,
        revision: 0, isCurrent: () => true,);
    expect(result.path, isNull);
    expect(result.bytes, bytes);
  });
}
