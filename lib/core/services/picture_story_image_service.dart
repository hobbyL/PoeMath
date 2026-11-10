import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:poemath/core/services/cache_activity.dart';
import 'package:poemath/core/services/cache_file_storage.dart';

import 'package:poemath/data/models/picture_story_prompt.dart';

class PictureStoryImageException implements Exception {
  const PictureStoryImageException(this.message);
  final String message;

  @override
  String toString() => message;
}

typedef PictureStoryImageNormalizer = Future<Uint8List> Function(
  Uint8List bytes,
);
typedef PictureStoryImageDecoder = Future<void> Function(Uint8List bytes);

/// 用户题图是持久数据，路径仅由内容 SHA 派生；页面不持有来源缓存路径。
class PictureStoryImageService {
  PictureStoryImageService({
    Future<Directory> Function()? directoryProvider,
    PictureStoryImageNormalizer? normalizer,
    PictureStoryImageDecoder? decoder,
    PictureStoryImageNormalizer? uploadNormalizer,
  })  : _directoryProvider =
            directoryProvider ?? getApplicationSupportDirectory,
        _normalizer = normalizer ?? _normalize,
        _decoder = decoder ?? _decodeStored,
        _uploadNormalizer = uploadNormalizer ?? _normalizeUpload;

  static final instance = PictureStoryImageService();
  static const maxSourceBytes = 20 * 1024 * 1024;
  static const maxStoredBytes = 2 * 1024 * 1024;
  static const maxDimension = 1600;
  static const maxUploadBytes = 512 * 1024;
  static const _maxSourcePixels = 40 * 1000 * 1000;
  static const _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
  static final _ownedFileName =
      RegExp(r'^[a-f0-9]{64}\.png(?:\.\d+-\d+\.pending)?$');

  final Future<Directory> Function() _directoryProvider;
  final PictureStoryImageNormalizer _normalizer;
  final PictureStoryImageDecoder _decoder;
  final PictureStoryImageNormalizer _uploadNormalizer;

  /// 只统计本服务拥有的正式题图和未发布副本，不创建目录或解码图片。
  Future<CacheUsage> storageUsage() async =>
      CacheFileStorage.usage(await _storedFiles());

  /// 调用方须持有题图导入屏障和仓储队列，并传入全部持久引用。
  Future<void> removeUnreferenced(
    Set<String> retainedIds, {
    required void Function() authorize,
  }) async {
    authorize();
    if (retainedIds.any((id) => !PictureStoryImage.isValidSha(id))) {
      throw const FormatException('题图引用无效');
    }
    final files = await _storedFiles();
    authorize();
    await CacheFileStorage.clear(
      files.where(
        (file) => !retainedIds.contains(_fileName(file).substring(0, 64)),
      ),
      authorize: authorize,
    );
    authorize();
  }

  static String _fileName(FileSystemEntity file) =>
      file.path.split(Platform.pathSeparator).last;

  Future<List<File>> _storedFiles() async {
    final base = await _directoryProvider();
    final directory = Directory('${base.path}/picture_story/images');
    for (final parent in [
      base,
      Directory('${base.path}/picture_story'),
      directory,
    ]) {
      final type = await FileSystemEntity.type(parent.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) return const [];
      if (type != FileSystemEntityType.directory) {
        throw const FileSystemException('题图目录无法读取');
      }
    }
    return directory
        .list(followLinks: false)
        .where(
          (entry) => entry is File && _ownedFileName.hasMatch(_fileName(entry)),
        )
        .cast<File>()
        .toList();
  }

  Future<File> _file(String id) async {
    if (!PictureStoryImage.isValidSha(id)) {
      throw const PictureStoryImageException('图片标识无效');
    }
    final base = await _directoryProvider();
    return File('${base.path}/picture_story/images/$id.png');
  }

  Future<String?> imagePath(String id) async {
    final file = await _file(id);
    if (!await file.exists() || await file.length() > maxStoredBytes) {
      return null;
    }
    return file.path;
  }

  Future<PictureStoryImage> importPath(String path) => CacheActivity.use(
        TemporaryCacheKind.pickers,
        () => _importPath(path),
      );

  Future<PictureStoryImage> _importPath(String path) async {
    try {
      final source = File(path);
      final size = await source.length();
      if (size < 1 || size > maxSourceBytes) {
        throw const PictureStoryImageException('请选择不超过 20 MiB 的图片');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in source.openRead(0, maxSourceBytes + 1)) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (bytes.length != size || bytes.length > maxSourceBytes) {
        throw const PictureStoryImageException('图片读取不完整，请重新选择');
      }
      return await importBytes(bytes);
    } on PictureStoryImageException {
      rethrow;
    } on Exception {
      throw const PictureStoryImageException('图片无法读取或保存，请重新选择并检查存储空间');
    }
  }

  Future<PictureStoryImage> importBytes(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxSourceBytes) {
      throw const PictureStoryImageException('图片为空或超过 20 MiB');
    }
    try {
      final normalized = await _normalizer(bytes);
      final id = sha256.convert(normalized).toString();
      final prepared = await prepareImages({id: normalized});
      try {
        await prepared.publish();
      } finally {
        await prepared.discard();
      }
      return PictureStoryImage.local(id);
    } on PictureStoryImageException {
      rethrow;
    } on Object {
      throw const PictureStoryImageException('图片无法读取或保存，请重新选择并检查存储空间');
    }
  }

  /// 校验并压缩连接测试的预览图，复用视觉上传约束，不写入正式题图目录。
  static Future<Uint8List> normalizePreview(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxSourceBytes) {
      throw const PictureStoryImageException('图片为空或超过 20 MiB');
    }
    try {
      return await _normalizeUpload(bytes);
    } on PictureStoryImageException {
      rethrow;
    } on Object {
      throw const PictureStoryImageException('服务没有返回可以读取的图片');
    }
  }

  /// 保留完整画面，只压缩上传副本；正式题图与内容 SHA 不变。
  Future<Uint8List> readForVision(String id) async {
    final bytes = await readImage(id);
    await _decoder(bytes);
    final compact = await _uploadNormalizer(bytes);
    if (compact.isEmpty || compact.length > maxUploadBytes) {
      throw const PictureStoryImageException('图片无法压缩到可上传大小');
    }
    return compact;
  }

  Future<void> ensureStored(PictureStoryImage image) async {
    image.validate();
    if (!image.isLocal) return;
    final bytes = await readImage(image.value);
    await _decoder(bytes);
  }

  Future<Uint8List> readImage(String id) async {
    final file = await _file(id);
    final size = await _storedSize(file);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, maxStoredBytes + 1)) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.length != size || bytes.length > maxStoredBytes) {
      throw const PictureStoryImageException('题目图片读取不完整，请重试');
    }
    validateStoredBytes(id, bytes);
    return bytes;
  }

  Future<int> _storedSize(File file) async {
    if (!await file.exists()) {
      throw const PictureStoryImageException('题目图片缺失，请在编辑页面重新选择图片');
    }
    final size = await file.length();
    if (size > maxStoredBytes) {
      throw const PictureStoryImageException('题目图片超过允许大小');
    }
    return size;
  }

  Future<void> validateImageBytes(String id, Uint8List bytes) async {
    validateStoredBytes(id, bytes);
    await _decoder(bytes);
  }

  /// 同步校验用于备份结构检查；原生完整解码在发布任何文件或目录前完成。
  static void validateStoredBytes(String id, Uint8List bytes) {
    if (!PictureStoryImage.isValidSha(id) ||
        bytes.length < 33 ||
        bytes.length > maxStoredBytes ||
        sha256.convert(bytes).toString() != id) {
      throw const FormatException('题目图片大小或校验信息无效');
    }
    for (var index = 0; index < _pngSignature.length; index++) {
      if (bytes[index] != _pngSignature[index]) {
        throw const FormatException('题目图片必须是有效 PNG');
      }
    }
    final data = ByteData.sublistView(bytes);
    final width = data.getUint32(16);
    final height = data.getUint32(20);
    if (String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR' ||
        width < 1 ||
        height < 1 ||
        width > maxDimension ||
        height > maxDimension) {
      throw const FormatException('题目图片尺寸无效或超过上限');
    }
  }

  Future<PreparedPictureStoryImages> prepareImages(
    Map<String, Uint8List> images,
  ) async {
    final pending = <File, File>{};
    try {
      // 全部图像先完整验证，坏图不能导致前面的图片提前发布。
      for (final entry in images.entries) {
        await validateImageBytes(entry.key, entry.value);
      }
      for (final entry in images.entries) {
        final target = await _file(entry.key);
        if (await target.exists()) {
          try {
            await readImage(entry.key);
            continue;
          } on FormatException {
            // 只有已验证的同 SHA 图片才能修复损坏副本。
          } on PictureStoryImageException {
            // 缺失、超限或不完整副本也只能用已验证的相同内容修复。
          }
        }
        await target.parent.create(recursive: true);
        final file = File(
          '${target.path}.${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 32)}.pending',
        );
        pending[file] = target;
        await file.writeAsBytes(entry.value, flush: true);
      }
      return PreparedPictureStoryImages._(pending);
    } on Object {
      await PreparedPictureStoryImages._(pending).discard();
      rethrow;
    }
  }

  static Future<void> _decodeStored(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      if (codec.frameCount != 1) {
        throw const PictureStoryImageException('题目图片必须是静态图片');
      }
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
  }

  static Future<Uint8List> _normalize(Uint8List bytes) =>
      _normalizeWithin(bytes, maxDimension, maxStoredBytes);

  static Future<Uint8List> _normalizeUpload(Uint8List bytes) =>
      _normalizeWithin(bytes, 1024, maxUploadBytes);

  static Future<Uint8List> _normalizeWithin(
    Uint8List bytes,
    int dimensionLimit,
    int byteLimit,
  ) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width < 1 || height < 1 || width * height > _maxSourcePixels) {
        throw const PictureStoryImageException('图片尺寸过大，请选择较小的图片');
      }
      final longest = math.max(width, height);
      var edge = math.min(longest, dimensionLimit);
      while (edge >= math.min(longest, 256)) {
        final ratio = edge / longest;
        final codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (width * ratio).round()),
          targetHeight: math.max(1, (height * ratio).round()),
        );
        try {
          if (codec.frameCount != 1) {
            throw const PictureStoryImageException('请选择静态图片');
          }
          final frame = await codec.getNextFrame();
          try {
            final encoded =
                await frame.image.toByteData(format: ui.ImageByteFormat.png);
            if (encoded != null && encoded.lengthInBytes <= byteLimit) {
              return Uint8List.fromList(
                encoded.buffer.asUint8List(
                  encoded.offsetInBytes,
                  encoded.lengthInBytes,
                ),
              );
            }
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
        edge = (edge * .75).floor();
      }
      throw const PictureStoryImageException('图片压缩后仍过大，请选择较小的图片');
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}

class PreparedPictureStoryImages {
  PreparedPictureStoryImages._(this._pending);
  final Map<File, File> _pending;

  Future<void> publish() async {
    for (final entry in _pending.entries.toList()) {
      await entry.key.rename(entry.value.path);
      _pending.remove(entry.key);
    }
  }

  Future<void> discard() async {
    for (final file in _pending.keys.toList()) {
      if (await file.exists()) await file.delete();
      _pending.remove(file);
    }
  }
}
