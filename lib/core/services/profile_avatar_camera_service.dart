import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';

import 'package:poemath/core/services/cache_activity.dart';
import 'package:poemath/core/services/profile_avatar_image_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/profile_avatar_repository.dart';

/// 记录拍照归属，使 Android 回收页面后恢复的照片仍写回原档案。
class ProfileAvatarCameraService {
  ProfileAvatarCameraService({
    ProfileAvatarImageService? images,
    ProfileAvatarRepository? repository,
    Box<dynamic>? settings,
    Future<String?> Function()? recoverPath,
    bool? supportsLostData,
  }) : _images = images ?? ProfileAvatarImageService(),
       _repository = repository ?? ProfileAvatarRepository(),
       _settingsOverride = settings,
       _recoverPath = recoverPath ?? _retrieveLostPath,
       _supportsLostData =
           supportsLostData ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static final instance = ProfileAvatarCameraService();
  // 本机恢复标记，不进入备份白名单；头像 PNG 本身正常参与备份。
  static const pendingKey = 'profile_avatar_pending_camera';
  // 启动恢复与页面可以使用不同注入实例，但共享唯一的原生拍照请求。
  static Future<void>? _active;
  final ProfileAvatarImageService _images;
  final ProfileAvatarRepository _repository;
  final Box<dynamic>? _settingsOverride;
  final Future<String?> Function() _recoverPath;
  final bool _supportsLostData;
  Box<dynamic> get _settings => _settingsOverride ?? HiveBoxes.settings;

  Future<void> capture(String profileId) => _exclusive(() async {
    await _recoverPending();
    await _settings.put(pendingKey, profileId);
    try {
      final avatar = await _images.pick(source: ProfileAvatarSource.camera);
      if (avatar != null) await _repository.save(profileId, avatar);
    } finally {
      await _settings.delete(pendingKey);
    }
  });

  Future<void> recoverPending() => _exclusive(_recoverPending);

  /// 题图恢复/选图也使用同一闸门，避免消费另一个页面的原生缓存。
  Future<T> withRecovery<T>(Future<T> Function() action) =>
      _exclusive(() async {
        await _recoverPending();
        return action();
      });

  Future<void> _recoverPending() async {
    final profile = _settings.get(pendingKey);
    if (profile == null) return;
    // 即使标记损坏，也先消费对应的原生缓存，不能让题图接走头像照片。
    try {
      if (!_supportsLostData) return;
      final path = await _recoverPath();
      if (profile is String &&
          profile.isNotEmpty &&
          profile.length <= 128 &&
          path != null) {
        final avatar = await _images.importPath(path);
        await _repository.save(profile, avatar);
      }
    } finally {
      await _settings.delete(pendingKey);
    }
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    while (_active != null) {
      await _active;
    }
    final done = Completer<void>();
    _active = done.future;
    try {
      return await CacheActivity.use(TemporaryCacheKind.pickers, action);
    } finally {
      _active = null;
      done.complete();
    }
  }

  static Future<String?> _retrieveLostPath() async {
    final response = await ImagePicker().retrieveLostData();
    if (response.exception != null) throw response.exception!;
    if (response.type == RetrieveType.video) {
      throw const FormatException('请选择静态图片');
    }
    return response.files?.firstOrNull?.path ?? response.file?.path;
  }
}
