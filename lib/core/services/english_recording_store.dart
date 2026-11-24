import 'dart:io';
import 'dart:typed_data';

import 'package:poemath/data/models/textbook.dart';

import 'package:path_provider/path_provider.dart';
import 'package:poemath/data/models/textbook_course.dart'
    show textbookTextDigest;

/// 孩子主动保存的录音，不属于可清理的朗读缓存，不进入备份。
class EnglishRecordingStore {
  EnglishRecordingStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directory;
  static const maxPcmBytes = 16000 * 2 * 60;

  Future<File> _file(String profileId, String id, {String? bookId}) async {
    if (bookId != null && !Textbook.isValidId(bookId)) {
      throw const FormatException('原书身份无效');
    }
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,160}$').hasMatch(id)) {
      throw const FormatException('录音标识无效');
    }
    final root = await _directory();
    return File(
      '${root.path}/english-recordings/${textbookTextDigest(profileId)}/${bookId == null ? '' : '$bookId/'}$id.wav',
    );
  }

  Future<String> save(
    String profileId,
    String id,
    Uint8List pcm,
    void Function() check, {
    String? bookId,
  }) async {
    check();
    if (pcm.length < 1600 || pcm.length > maxPcmBytes || pcm.length.isOdd) {
      throw const FormatException('录音过短或超过一分钟，请重新录制');
    }
    final file = await _file(profileId, id, bookId: bookId);
    check();
    await file.parent.create(recursive: true);
    // id 是每段每次尝试的新随机标识，保存不会覆盖重录前的文件。
    if (await file.exists()) throw const FormatException('这段录音已保存');
    final pending = File('${file.path}.pending');
    try {
      final bytes = encodeWav(pcm);
      await pending.writeAsBytes(bytes, flush: true);
      check();
      await pending.rename(file.path);
      return id;
    } finally {
      if (await pending.exists()) await pending.delete();
    }
  }

  static Uint8List encodeWav(Uint8List pcm) {
    final bytes = Uint8List(44 + pcm.length), header = ByteData(44);
    void word(int at, String value) =>
        bytes.setRange(at, at + value.length, value.codeUnits);
    word(0, 'RIFF');
    word(8, 'WAVE');
    word(12, 'fmt ');
    word(36, 'data');
    header.setUint32(4, pcm.length + 36, Endian.little);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, 16000, Endian.little);
    header.setUint32(28, 32000, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint32(40, pcm.length, Endian.little);
    for (final range in [(4, 8), (16, 36), (40, 44)]) {
      bytes.setRange(
        range.$1,
        range.$2,
        header.buffer.asUint8List().sublist(range.$1, range.$2),
      );
    }
    bytes.setRange(44, bytes.length, pcm);
    return bytes;
  }

  Future<String?> path(String profileId, String id, {String? bookId}) async {
    final file = await _file(profileId, id, bookId: bookId);
    return await file.exists() ? file.path : null;
  }

  Future<void> deleteBook(String bookId, void Function() check) async {
    if (!Textbook.isValidId(bookId)) throw const FormatException('原书身份无效');
    check();
    final root = Directory('${(await _directory()).path}/english-recordings');
    if (!await root.exists()) return;
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory) continue;
      check();
      final book = Directory('${entry.path}/$bookId');
      if (await book.exists()) {
        check();
        await book.delete(recursive: true);
      }
    }
  }

  Future<int> usage() async {
    final root = Directory('${(await _directory()).path}/english-recordings');
    if (!await root.exists()) return 0;
    var bytes = 0;
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      if (entry is File) bytes += await entry.length();
    }
    return bytes;
  }
}
