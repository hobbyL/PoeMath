import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';

import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/picture_story_editor_draft.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';

enum PictureStoryImageSource { gallery, file, camera }

typedef PictureStoryPickPath = Future<String?> Function(
  PictureStoryImageSource source,
);
typedef PictureStoryRecoverPath = Future<String?> Function();

/// 外部选择由服务持有，家长保护移除页面后仍能保存匹配请求的恢复结果。
class PictureStoryEditorService extends ChangeNotifier {
  PictureStoryEditorService({
    Box<dynamic>? settings,
    PictureStoryImageService? images,
    PictureStoryPickPath? pickPath,
    PictureStoryRecoverPath? recoverPath,
    bool? supportsLostData,
  })  : _settingsOverride = settings,
        _images = images ?? PictureStoryImageService.instance,
        _pickPath = pickPath ?? _pick,
        _recoverPath = recoverPath ?? _retrieveLostPath,
        _supportsLostData = supportsLostData ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static final instance = PictureStoryEditorService();
  static const draftKey = 'picture_story_editor_draft_v1';
  final Box<dynamic>? _settingsOverride;
  final PictureStoryImageService _images;
  final PictureStoryPickPath _pickPath;
  final PictureStoryRecoverPath _recoverPath;
  final bool _supportsLostData;
  bool _picking = false;
  bool _recovering = false;
  Future<void>? _recovery;

  Box<dynamic> get _settings => _settingsOverride ?? HiveBoxes.settings;
  bool get isPicking => _picking || _recovering;
  bool get supportsCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get supportsGallery => supportsCamera;

  static String _identifier(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}';

  PictureStoryEditorDraft? readDraft() {
    if (!_settings.containsKey(draftKey)) return null;
    final raw = _settings.get(draftKey);
    if (raw is! String) throw const FormatException('上次编辑内容暂时无法读取');
    return PictureStoryEditorDraft.fromJson(jsonDecode(raw));
  }

  PictureStoryEditorDraft openDraft({PictureStoryPrompt? original}) {
    final saved = readDraft();
    if (saved?.matches(ProfileScope.currentId, original?.id) == true) {
      return saved!;
    }
    return PictureStoryEditorDraft.create(
      id: _identifier('local'),
      profileId: ProfileScope.currentId,
      original: original,
    );
  }

  Future<void> discardDraft(PictureStoryEditorDraft draft) =>
      PictureStoryRepository.exclusive(() async {
        final saved = readDraft();
        if (saved?.id == draft.id && saved?.profileId == draft.profileId) {
          await _settings.delete(draftKey);
          notifyListeners();
        }
      });

  Future<void> chooseImage(
    PictureStoryEditorDraft draft,
    PictureStoryImageSource source,
  ) async {
    if (_picking) return;
    _picking = true;
    notifyListeners();
    try {
      await _recovery;
      if (draft.profileId != ProfileScope.currentId) {
        throw const FormatException('孩子档案已切换，请重新打开编辑');
      }
      final request = _identifier('pick');
      await PictureStoryRepository.exclusive(() async {
        await _settings.put(
          draftKey,
          draft.copyWith(pendingRequest: request, clearMessage: true).encode(),
        );
        notifyListeners();
      });
      if (!_matches(draft, request)) return;
      try {
        final path = await _pickPath(source);
        await _complete(draft, request, path);
      } on Object catch (error, stackTrace) {
        AppLogger.e(
          '题目选图失败，原表单保留',
          tag: 'PictureStory',
          error: error,
          stackTrace: stackTrace,
        );
        await _complete(draft, request, null, message: _imageError(error));
      }
    } finally {
      _picking = false;
      notifyListeners();
    }
  }

  bool _matches(PictureStoryEditorDraft draft, String request) {
    final current = readDraft();
    return current?.id == draft.id &&
        current?.profileId == draft.profileId &&
        current?.pendingRequest == request;
  }

  Future<void> _complete(
    PictureStoryEditorDraft draft,
    String request,
    String? path, {
    String? message,
  }) async {
    if (!_matches(draft, request)) return;
    PictureStoryImage? image;
    if (path != null) image = await _images.importPath(path);
    await PictureStoryRepository.exclusive(() async {
      if (!_matches(draft, request)) return;
      final current = readDraft()!;
      await _settings.put(
        draftKey,
        current
            .copyWith(
              image: image,
              clearPendingRequest: true,
              message: message,
              clearMessage: message == null,
            )
            .encode(),
      );
      notifyListeners();
    });
  }

  Future<void> recoverLostImage() => _recovery ??= _recoverLostImage();

  Future<void> _recoverLostImage() async {
    if (!_supportsLostData || _picking) return;
    _recovering = true;
    notifyListeners();
    PictureStoryEditorDraft? draft;
    try {
      draft = readDraft();
      final path = await _recoverPath();
      final request = draft?.pendingRequest;
      if (draft != null && request != null) {
        await _complete(draft, request, path);
      }
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '题目选图恢复失败，原表单保留',
        tag: 'PictureStory',
        error: error,
        stackTrace: stackTrace,
      );
      final request = draft?.pendingRequest;
      if (draft != null && request != null) {
        await _complete(draft, request, null, message: _imageError(error));
      }
    } finally {
      _recovering = false;
      notifyListeners();
    }
  }

  static String _imageError(Object error) => switch (error) {
        PictureStoryImageException(:final message) => message,
        PlatformException() => '无法获取图片，请检查相册或相机权限后重试',
        _ => '图片选择或保存失败，原有内容已保留，请重试',
      };

  static Future<String?> _pick(PictureStoryImageSource source) async {
    if (source == PictureStoryImageSource.file) {
      final result =
          await FilePicker.pickFiles(type: FileType.image, withData: false);
      if (result == null) return null;
      final path = result.files.single.path;
      if (path == null) {
        throw const PictureStoryImageException('无法读取所选图片，请重新选择');
      }
      return path;
    }
    final file = await ImagePicker().pickImage(
      source: source == PictureStoryImageSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      requestFullMetadata: false,
    );
    return file?.path;
  }

  static Future<String?> _retrieveLostPath() async {
    final response = await ImagePicker().retrieveLostData();
    if (response.exception != null) throw response.exception!;
    if (!response.isEmpty && response.type == RetrieveType.video) {
      throw const PictureStoryImageException('请选择静态图片');
    }
    return response.files?.firstOrNull?.path ?? response.file?.path;
  }
}
