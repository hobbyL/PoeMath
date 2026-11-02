import 'dart:io';

/// 磁盘文件或可释放内存的实际占用；文件侧计入元数据和未发布副本。
class CacheUsage {
  const CacheUsage({this.bytes = 0, this.entries = 0});

  final int bytes;
  final int entries;

  CacheUsage operator +(CacheUsage other) => CacheUsage(
        bytes: bytes + other.bytes,
        entries: entries + other.entries,
      );
}

/// 缓存目录扫描不创建目录、不读取内容、不跟随符号链接。
class CacheFileStorage {
  const CacheFileStorage._();

  static Future<List<File>> files(Directory directory) async {
    final type =
        await FileSystemEntity.type(directory.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return const [];
    if (type != FileSystemEntityType.directory) {
      throw const FileSystemException('缓存目录无法读取');
    }
    return directory
        .list(recursive: true, followLinks: false)
        .where((entry) => entry is File)
        .cast<File>()
        .toList();
  }

  static Future<CacheUsage> usage(Iterable<File> files) async {
    var bytes = 0;
    var entries = 0;
    for (final file in files) {
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.notFound) continue;
      if (stat.type != FileSystemEntityType.file) {
        throw const FileSystemException('缓存文件无法读取');
      }
      bytes += stat.size;
      entries++;
    }
    return CacheUsage(bytes: bytes, entries: entries);
  }

  /// 逐个删除扫描到的文件，每次 IO 之后再次验证授权；不扩大删除范围。
  static Future<void> clear(
    Iterable<File> files, {
    required void Function() authorize,
  }) async {
    for (final file in files) {
      authorize();
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      authorize();
      try {
        await file.delete();
      } on FileSystemException catch (error) {
        if (error.osError?.errorCode != 2) rethrow;
        // 同时发生的系统缓存淘汰不构成清理失败。
      }
    }
  }
}
