import 'dart:convert';
import 'dart:typed_data';

import 'package:poemath/core/services/backup_payload_cipher.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';

/// 备份里的题库契约独立于普通 settings 白名单，图片只用内容 SHA 标识。
class PictureStoryCatalogBackup {
  PictureStoryCatalogBackup._({
    required this.catalog,
    required this.enabledByProfile,
    required this.images,
  });

  static const jsonKey = 'pictureStoryCatalog';
  final PictureStoryCatalogState catalog;
  final Map<String, List<String>> enabledByProfile;
  final Map<String, Uint8List> images;

  int get promptCount => catalog.versions
      .map((prompt) => prompt.id)
      .where((id) => !catalog.deletedIds.contains(id))
      .toSet()
      .length;

  factory PictureStoryCatalogBackup.fromJson(Object? value) {
    final catalog = PictureStoryCatalogState.fromJson(value);
    final data = value as Map<String, dynamic>;
    final enabled = _checkedEnabled(data['enabledByProfile']);
    final rawImages = data['images'];
    if (rawImages is! Map<String, dynamic>) {
      throw const FormatException('备份的题目图片必须是对象');
    }
    final requiredImages = catalog.imageIds;
    if (rawImages.length != requiredImages.length ||
        rawImages.keys.any((id) => !requiredImages.contains(id))) {
      throw const FormatException('备份题图缺失或与题目引用不一致');
    }
    final images = <String, Uint8List>{};
    for (final entry in rawImages.entries) {
      final encoded = entry.value;
      if (encoded is! String ||
          encoded.length >
              ((PictureStoryImageService.maxStoredBytes + 2) ~/ 3) * 4) {
        throw const FormatException('备份题图编码无效或超过 2 MiB');
      }
      final bytes = base64Decode(encoded);
      PictureStoryImageService.validateStoredBytes(entry.key, bytes);
      images[entry.key] = bytes.asUnmodifiableView();
    }
    return PictureStoryCatalogBackup._(
      catalog: catalog,
      enabledByProfile: enabled,
      images: Map.unmodifiable(images),
    );
  }

  static Map<String, List<String>> _checkedEnabled(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('备份的孩子启用选择必须是对象');
    }
    final result = <String, List<String>>{};
    for (final entry in value.entries) {
      final ids = entry.value;
      if (entry.key.trim().isEmpty ||
          entry.key.length > 128 ||
          ids is! List ||
          ids.length > 10000 ||
          ids.any((id) => id is! String || !PictureStoryPrompt.isValidId(id)) ||
          ids.toSet().length != ids.length) {
        throw const FormatException('备份的孩子档案或启用题目无效');
      }
      result[entry.key] = List.unmodifiable(ids.cast<String>());
    }
    return Map.unmodifiable(result);
  }

  /// 调用者持有仓储的 exclusive 队列，题目版本与启用选择来自同一快照。
  static Future<Map<String, Object>> export({
    required PictureStoryRepository repository,
    required PictureStoryImageService images,
    required Map<String, dynamic> parentPayload,
  }) async {
    final catalog = repository.catalogState();
    final encodedImages = <String, String>{};
    final result = <String, Object>{
      ...catalog.toJson(),
      'enabledByProfile': _checkedEnabled(repository.enabledByProfile()),
      'images': encodedImages,
    };
    const encoder = JsonEncoder.withIndent('  ');
    var estimated = utf8
        .encode(
          encoder.convert({
            ...parentPayload,
            jsonKey: result,
          }),
        )
        .length;
    if (estimated > maxBackupBytes) {
      throw const FormatException('备份超过 32 MiB，请减少题目图片或聊天历史后再导出');
    }
    // 在读取和 Base64 分配之前算完图片预算，每张预留键、缩进和标点空间。
    for (final id in catalog.imageIds) {
      final size = await images.storedImageSize(id);
      estimated += ((size + 2) ~/ 3) * 4 + id.length + 128;
      if (estimated > maxBackupBytes) {
        throw const FormatException('备份超过 32 MiB，请减少题目图片或聊天历史后再导出');
      }
    }
    for (final id in catalog.imageIds) {
      final bytes = await images.readImage(id);
      await images.validateImageBytes(id, bytes);
      encodedImages[id] = base64Encode(bytes);
    }
    return result;
  }
}
