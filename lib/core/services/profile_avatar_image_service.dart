import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'package:poemath/core/services/cache_activity.dart';
import 'package:poemath/data/models/profile_avatar.dart';

enum ProfileAvatarSource { gallery, camera }

/// 系统选图 → 限量读取 → 居中裁剪；不保存来源路径或照片元数据。
class ProfileAvatarImageService {
  ProfileAvatarImageService({
    Future<String?> Function()? pickPath,
    Future<String?> Function()? capturePath,
  }) : _pickPath = pickPath ?? _pick,
       _capturePath = capturePath ?? _capture;

  static const maxSourceBytes = 20 * 1024 * 1024;
  static const _maxSourcePixels = 40 * 1000 * 1000;
  final Future<String?> Function() _pickPath;
  final Future<String?> Function() _capturePath;
  bool get supportsCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<ProfileAvatar?> pick({
    ProfileAvatarSource source = ProfileAvatarSource.gallery,
  }) => CacheActivity.use(TemporaryCacheKind.pickers, () async {
    final path = await (source == ProfileAvatarSource.camera
        ? _capturePath()
        : _pickPath());
    if (path == null) return null;
    return importPath(path);
  });

  Future<ProfileAvatar> importPath(String path) =>
      CacheActivity.use(TemporaryCacheKind.pickers, () async {
        final file = File(path);
        final size = await file.length();
        if (size == 0 || size > maxSourceBytes) {
          throw const FormatException('请选择不超过 20 MiB 的图片');
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in file.openRead(0, maxSourceBytes + 1)) {
          builder.add(chunk);
        }
        final bytes = builder.takeBytes();
        if (bytes.length != size || bytes.length > maxSourceBytes) {
          throw const FormatException('图片读取不完整，请重新选择');
        }
        return normalize(bytes);
      });

  static Future<String?> _capture() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 1600,
      maxHeight: 1600,
      requestFullMetadata: false,
    );
    return image?.path;
  }

  static Future<String?> _pick() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      dialogTitle: '选择头像图片',
    );
    if (result == null) return null;
    final path = result.files.single.path;
    if (path == null) throw const FormatException('无法读取这张图片，请重新选择');
    return path;
  }

  static Future<ProfileAvatar> normalize(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxSourceBytes) {
      throw const FormatException('请选择不超过 20 MiB 的图片');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width < 1 || height < 1 || width * height > _maxSourcePixels) {
        throw const FormatException('图片尺寸过大，请选择较小的图片');
      }
      // 解码边长有界，避免相机原图占用大量内存。
      final ratio = math.min(1.0, 1024 / math.max(width, height));
      final codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (width * ratio).round()),
        targetHeight: math.max(1, (height * ratio).round()),
      );
      try {
        if (codec.frameCount != 1) throw const FormatException('请选择静态图片');
        final frame = await codec.getNextFrame();
        try {
          final image = frame.image;
          final side = math.min(image.width, image.height).toDouble();
          const target = ProfileAvatar.dimension;
          final recorder = ui.PictureRecorder();
          ui.Canvas(recorder).drawImageRect(
            image,
            ui.Rect.fromLTWH(
              (image.width - side) / 2,
              (image.height - side) / 2,
              side,
              side,
            ),
            const ui.Rect.fromLTWH(0, 0, target * 1.0, target * 1.0),
            ui.Paint()..filterQuality = ui.FilterQuality.medium,
          );
          final picture = recorder.endRecording();
          try {
            final avatar = await picture.toImage(target, target);
            try {
              final png = await avatar.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (png == null) throw const FormatException('图片处理失败，请重新选择');
              return ProfileAvatar(
                png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
              );
            } finally {
              avatar.dispose();
            }
          } finally {
            picture.dispose();
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}
