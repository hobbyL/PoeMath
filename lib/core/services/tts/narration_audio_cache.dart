import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:poemath/core/services/tts/narration_audio_identity.dart';

export 'package:poemath/core/services/tts/narration_audio_identity.dart';

/// 一次播放持有的音频租约，防止容量清理删除正在使用的文件。
class NarrationAudio {
  NarrationAudio({
    this.path,
    this.bytes,
    required this.format,
    this.identity,
    void Function()? release,
  }) : _release = release;
  final String? path;
  final Uint8List? bytes;
  final String format;
  final NarrationAudioIdentity? identity;
  void Function()? _release;
  void release() {
    _release?.call();
    _release = null;
  }
}

/// 可重建的教材音频；只存私有 cache 目录，不进入学习备份。
class NarrationAudioCache {
  NarrationAudioCache({
    Future<Directory> Function()? directoryProvider,
    this.maxBytes = 100 * 1024 * 1024,
  }) : _directoryProvider = directoryProvider ?? getTemporaryDirectory;
  final Future<Directory> Function() _directoryProvider;
  final int maxBytes;
  final _revisions = <String, int>{};
  final _pins = <String, int>{};
  final _pending = <String, Future<Uint8List>>{};
  Future<void> _writes = Future<void>.value();

  static String key(Object identity) =>
      sha256.convert(utf8.encode(jsonEncode(identity))).toString();
  int revision(String book) => _revisions[book] ?? 0;
  bool _valid(String value) => RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
  Future<Directory> _root() async =>
      Directory('${(await _directoryProvider()).path}/textbook-audio');
  Future<File> _file(String book, String key, String format) async {
    if (!_valid(book) || !_valid(key) || !{'mp3', 'wav'}.contains(format)) {
      throw ArgumentError('无效的教材音频缓存身份');
    }
    return File('${(await _root()).path}/$book/$key.$format');
  }

  NarrationAudio _lease(
    File file,
    String format, {
    required String key,
    required String digest,
    NarrationBackend? backend,
  }) {
    _pins.update(file.path, (count) => count + 1, ifAbsent: () => 1);
    return NarrationAudio(
      path: file.path,
      format: format,
      identity: backend == null
          ? null
          : NarrationAudioIdentity(
              cacheKey: key,
              backend: backend,
              audioSha256: digest,
            ),
      release: () {
        final count = (_pins[file.path] ?? 1) - 1;
        if (count <= 0) {
          _pins.remove(file.path);
        } else {
          _pins[file.path] = count;
        }
        unawaited(_enqueue(_prune).catchError((Object _) {}));
      },
    );
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _writes.then((_) => operation());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<NarrationAudio> obtain(
    String book,
    String key,
    String format, {
    required int revision,
    required bool Function() isCurrent,
    required Future<Uint8List> Function() generate,
    NarrationBackend? backend,
  }) async {
    final cached = await read(book, key, format, backend: backend);
    if (cached != null) return cached;
    final pendingKey = '$book|$revision|$key';
    final future =
        _pending.putIfAbsent(pendingKey, () => Future.sync(generate));
    try {
      final bytes = await future;
      return await store(
        book,
        key,
        format,
        bytes,
        revision: revision,
        isCurrent: isCurrent,
        backend: backend,
      );
    } finally {
      if (identical(_pending[pendingKey], future)) _pending.remove(pendingKey);
    }
  }

  Future<NarrationAudio?> read(
    String book,
    String key,
    String format, {
    NarrationBackend? backend,
  }) async {
    final revision = this.revision(book);
    try {
      final file = await _file(book, key, format);
      final metadata = File('${file.path}.json');
      if (!await file.exists() || !await metadata.exists()) return null;
      final size = await file.length();
      if (size == 0 || size > maxBytes || await metadata.length() > 1024) {
        return null;
      }
      final value = jsonDecode(await metadata.readAsString());
      if (value is! Map<String, dynamic> ||
          value['size'] != size ||
          value['sha256'] !=
              (await sha256.bind(file.openRead()).first).toString()) {
        return null;
      }
      // 文件 mtime 表示最近使用，重启仍能按使用顺序淘汰。
      try {
        await file.setLastModified(DateTime.now());
      } on IOException {/* 仍可播放 */}
      if (revision != this.revision(book)) return null;
      return _lease(
        file,
        format,
        key: key,
        digest: value['sha256'] as String,
        backend: backend,
      );
    } on Exception {
      return null;
    }
  }

  Future<NarrationAudio> store(
    String book,
    String key,
    String format,
    Uint8List bytes, {
    required int revision,
    required bool Function() isCurrent,
    NarrationBackend? backend,
  }) async {
    final digest = sha256.convert(bytes).toString();
    NarrationAudio? result;
    await _enqueue(() async {
      if (!isCurrent() ||
          revision != this.revision(book) ||
          bytes.length > maxBytes) {
        return;
      }
      File? pending;
      try {
        final file = await _file(book, key, format);
        await file.parent.create(recursive: true);
        pending = File('${file.path}.pending');
        await pending.writeAsBytes(bytes, flush: true);
        if (!isCurrent() || revision != this.revision(book)) return;
        await pending.rename(file.path);
        pending = null;
        await File('${file.path}.json').writeAsString(
          jsonEncode({
            'size': bytes.length,
            'sha256': digest,
          }),
          flush: true,
        );
        result = _lease(
          file,
          format,
          key: key,
          digest: digest,
          backend: backend,
        );
        await _prune();
      } on Exception {/* 写入失败只损失缓存，音频仍可临时播放。 */} finally {
        if (pending != null) {
          try {
            if (await pending.exists()) await pending.delete();
          } on IOException {/* 下次可重建 */}
        }
      }
    });
    return result ??
        NarrationAudio(
          bytes: bytes,
          format: format,
          identity: backend == null
              ? null
              : NarrationAudioIdentity(
                  cacheKey: key,
                  backend: backend,
                  audioSha256: digest,
                ),
        );
  }

  Future<void> _prune() async {
    try {
      final root = await _root();
      if (!await root.exists()) return;
      final files = <({File file, FileStat stat})>[];
      var total = 0;
      await for (final entity
          in root.list(recursive: true, followLinks: false)) {
        if (entity is! File ||
            !(entity.path.endsWith('.mp3') || entity.path.endsWith('.wav'))) {
          continue;
        }
        final stat = await entity.stat();
        files.add((file: entity, stat: stat));
        total += stat.size;
      }
      files.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
      for (final entry in files) {
        if (total <= maxBytes) break;
        if (_pins.containsKey(entry.file.path)) continue;
        await entry.file.delete();
        final meta = File('${entry.file.path}.json');
        if (await meta.exists()) await meta.delete();
        total -= entry.stat.size;
      }
    } on IOException {/* 清理失败不影响播放 */}
  }

  /// 本书派生音频占用的字节数与文件数（不含 `.json` 元数据）。
  Future<({int bytes, int files})> bookUsage(String book) async {
    if (!_valid(book)) return (bytes: 0, files: 0);
    try {
      final folder = Directory('${(await _root()).path}/$book');
      if (!await folder.exists()) return (bytes: 0, files: 0);
      var bytes = 0;
      var files = 0;
      await for (final entity in folder.list(followLinks: false)) {
        if (entity is! File ||
            !(entity.path.endsWith('.mp3') || entity.path.endsWith('.wav'))) {
          continue;
        }
        bytes += await entity.length();
        files++;
      }
      return (bytes: bytes, files: files);
    } on IOException {
      return (bytes: 0, files: 0);
    }
  }

  /// 先失效在途写入，再删除本书派生音频。
  Future<void> clearBook(String book) {
    if (!_valid(book)) throw ArgumentError('无效的教材身份');
    _revisions[book] = revision(book) + 1;
    return _enqueue(() async {
      final folder = Directory('${(await _root()).path}/$book');
      if (await folder.exists()) await folder.delete(recursive: true);
    });
  }
}
