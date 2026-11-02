import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:poemath/core/services/cache_activity.dart';
import 'package:poemath/core/services/cache_file_storage.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/picture_story_editor_service.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/services/textbook_cover_cache.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/utils/logger.dart';

enum StorageCacheKind {
  textbookCovers,
  textbookContent,
  textbookAudio,
  cloudAudio,
  images,
  pictureStoryImages,
  updates,
  pickers,
  sharing,
  systemTts,
  legacySpeechModels;

  bool get isMemory => this == cloudAudio || this == images;
  bool get canClear => this != pictureStoryImages;
}

class StorageCacheEntry {
  const StorageCacheEntry({required this.kind, this.usage});

  final StorageCacheKind kind;

  /// null 表示统计失败，不能当作占用为零。
  final CacheUsage? usage;
}

class StorageCacheSnapshot {
  StorageCacheSnapshot(Iterable<StorageCacheEntry> entries)
      : entries = List.unmodifiable(entries);

  final List<StorageCacheEntry> entries;

  bool get hasErrors => entries.any((entry) => entry.usage == null);
  int get diskBytes => _bytes(memory: false);
  int get memoryBytes => _bytes(memory: true);

  int _bytes({required bool memory}) => entries
      .where((entry) => entry.kind.isMemory == memory)
      .fold(0, (bytes, entry) => bytes + (entry.usage?.bytes ?? 0));
}

/// 由实际文件所有者统计占用；正式题图只读，其他持久数据不在清理范围。
class StorageManagementService {
  StorageManagementService({
    required TextbookFileService textbooks,
    required TtsService tts,
    PictureStoryImageService? pictureStoryImages,
    Future<Directory> Function()? supportDirectoryProvider,
    Future<Directory> Function()? temporaryDirectoryProvider,
    ImageCache? imageCache,
    void Function()? authorize,
    Future<void> Function()? preparePickerCleanup,
  })  : _textbooks = textbooks,
        _tts = tts,
        _pictureStoryImages = pictureStoryImages ??
            PictureStoryImageService(
              directoryProvider: supportDirectoryProvider,
            ),
        _supportDirectory =
            supportDirectoryProvider ?? getApplicationSupportDirectory,
        _temporaryDirectory =
            temporaryDirectoryProvider ?? getTemporaryDirectory,
        _imageCache = imageCache ?? PaintingBinding.instance.imageCache,
        _authorize = authorize ?? ParentAccessService.instance.assertAllowed,
        _preparePickerCleanup = preparePickerCleanup ?? _recoverPendingImage;

  final TextbookFileService _textbooks;
  final TtsService _tts;
  final PictureStoryImageService _pictureStoryImages;
  final Future<Directory> Function() _supportDirectory;
  final Future<Directory> Function() _temporaryDirectory;
  final ImageCache _imageCache;
  final void Function() _authorize;
  final Future<void> Function() _preparePickerCleanup;

  static final _uuid = RegExp(
    r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
  );
  static final _cameraImage = RegExp(
    r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}.*\.(jpg|png|jpeg)$',
  );

  Future<StorageCacheSnapshot> scan() async {
    _authorize();
    ({CacheUsage covers, CacheUsage content})? textbookUsage;
    try {
      textbookUsage = await _textbooks.cacheUsage();
    } on Object catch (error, stackTrace) {
      _logScanFailure(error, stackTrace);
    }
    final entries = <StorageCacheEntry>[];
    for (final kind in StorageCacheKind.values) {
      _authorize();
      try {
        final CacheUsage? usage;
        switch (kind) {
          case StorageCacheKind.textbookCovers:
            usage = textbookUsage?.covers;
          case StorageCacheKind.textbookContent:
            usage = textbookUsage?.content;
          default:
            usage = await _usage(kind);
        }
        // 旧模型只在确实有遗留文件或无法读取时显示。
        if (kind == StorageCacheKind.legacySpeechModels &&
            usage?.entries == 0) {
          continue;
        }
        entries.add(StorageCacheEntry(kind: kind, usage: usage));
      } on Object catch (error, stackTrace) {
        _logScanFailure(error, stackTrace);
        entries.add(StorageCacheEntry(kind: kind));
      }
    }
    _authorize();
    return StorageCacheSnapshot(entries);
  }

  Future<CacheUsage> _usage(StorageCacheKind kind) async {
    switch (kind) {
      case StorageCacheKind.textbookAudio:
        return _textbooks.narrationCache.storageUsage();
      case StorageCacheKind.cloudAudio:
        return _tts.cloudCacheUsage;
      case StorageCacheKind.images:
        return TextbookCoverCache.memoryUsage +
            CacheUsage(
              bytes: _imageCache.currentSizeBytes,
              entries: _imageCache.currentSize,
            );
      case StorageCacheKind.pictureStoryImages:
        return _pictureStoryImages.storageUsage();
      case StorageCacheKind.legacySpeechModels:
        final files = await CacheFileStorage.files(
          Directory('${(await _supportDirectory()).path}/speech_models'),
        );
        return CacheFileStorage.usage(files);
      case StorageCacheKind.updates:
      case StorageCacheKind.pickers:
      case StorageCacheKind.sharing:
      case StorageCacheKind.systemTts:
        return CacheFileStorage.usage(await _temporaryFiles(kind));
      case StorageCacheKind.textbookCovers:
      case StorageCacheKind.textbookContent:
        throw StateError('教材缓存统一由文件服务统计');
    }
  }

  /// 清理必须在服务边界和异步删除前验证，页面保护失效后不能继续删文件。
  Future<void> clear(StorageCacheKind kind) async {
    _authorize();
    switch (kind) {
      case StorageCacheKind.textbookCovers:
        await _textbooks.clearAllCovers(authorize: _authorize);
      case StorageCacheKind.textbookContent:
        await _textbooks.clearAllExtractedContent(authorize: _authorize);
      case StorageCacheKind.textbookAudio:
        await _textbooks.narrationCache.clearAll(authorize: _authorize);
      case StorageCacheKind.cloudAudio:
        _tts.clearCloudCache();
      case StorageCacheKind.images:
        TextbookCoverCache.clearMemory();
        _imageCache.clear();
      case StorageCacheKind.pictureStoryImages:
        throw UnsupportedError('题图只能随题目删除，存储管理不提供清理');
      case StorageCacheKind.legacySpeechModels:
        final files = await CacheFileStorage.files(
          Directory('${(await _supportDirectory()).path}/speech_models'),
        );
        await CacheFileStorage.clear(files, authorize: _authorize);
      case StorageCacheKind.updates:
      case StorageCacheKind.pickers:
      case StorageCacheKind.sharing:
      case StorageCacheKind.systemTts:
        if (kind == StorageCacheKind.pickers) {
          await _preparePickerCleanup();
          _authorize();
        }
        final temporaryKind = switch (kind) {
          StorageCacheKind.updates => TemporaryCacheKind.updates,
          StorageCacheKind.pickers => TemporaryCacheKind.pickers,
          StorageCacheKind.sharing => TemporaryCacheKind.sharing,
          _ => TemporaryCacheKind.systemTts,
        };
        await CacheActivity.clear(temporaryKind, () async {
          _authorize();
          final files = await _temporaryFiles(kind);
          await CacheFileStorage.clear(files, authorize: _authorize);
        });
    }
    _authorize();
  }

  Future<List<File>> _temporaryFiles(StorageCacheKind kind) async {
    final root = await _temporaryDirectory();
    final type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return const [];
    if (type != FileSystemEntityType.directory) {
      throw const FileSystemException('临时缓存目录无法读取');
    }
    final files = <File>[];
    await for (final entity in root.list(followLinks: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      final matches = switch (kind) {
        StorageCacheKind.updates => name == 'poemath_update',
        StorageCacheKind.pickers => name == 'file_picker' ||
            entity is Directory && _uuid.hasMatch(name) ||
            entity is File &&
                (name.startsWith('scaled_') ||
                    name.startsWith('IMAGE_') ||
                    _cameraImage.hasMatch(name)),
        StorageCacheKind.sharing => name == 'share_plus' ||
            entity is File &&
                (RegExp(r'^poemath_backup_.+\.json$').hasMatch(name) ||
                    RegExp(r'^poemath_diagnostics_.+\.txt$').hasMatch(name)),
        StorageCacheKind.systemTts => name == 'textbook-tts-pending',
        _ => false,
      };
      if (!matches) continue;
      if (entity is File) {
        files.add(entity);
      } else if (entity is Directory) {
        files.addAll(await CacheFileStorage.files(entity));
      }
    }
    return files;
  }

  static void _logScanFailure(Object error, StackTrace stackTrace) {
    AppLogger.e(
      '缓存占用统计失败',
      tag: 'StorageManagement',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static Future<void> _recoverPendingImage() async {
    final editor = PictureStoryEditorService.instance;
    await editor.recoverLostImage();
    if (editor.readDraft()?.pendingRequest != null) {
      throw const CacheInUseException();
    }
  }
}
