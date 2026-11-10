import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:poemath/core/services/image_generation_client.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/picture_story_generation_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/picture_story_generation_draft.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

enum PictureStoryRunPhase {
  idle,
  preparing,
  generating,
  stopping,
  finished,
  paused,
  failed,
}

/// 只保存运行信息；候选内容始终从生成草稿读取。
class PictureStoryRunState {
  const PictureStoryRunState({
    this.phase = PictureStoryRunPhase.idle,
    this.options,
    this.progress = '正在读取生成配置…',
    this.message,
  });

  final PictureStoryRunPhase phase;
  final PictureStoryGenerationOptions? options;
  final String progress;
  final String? message;
  bool get isBusy => switch (phase) {
    PictureStoryRunPhase.preparing ||
    PictureStoryRunPhase.generating ||
    PictureStoryRunPhase.stopping => true,
    _ => false,
  };
}

class _Operation {
  _Operation(this.profileId, this.revision, this.options);
  final String profileId;
  final int revision;
  PictureStoryGenerationOptions options;
  final done = Completer<void>();
  void Function()? authorize;
  String? signature;
  String? stopReason;
  bool pipelineStarted = false;
}

/// 由应用 ProviderScope 持有。页面离开只取消 UI 订阅，不取消生成。
class PictureStoryGenerationController extends ChangeNotifier
    with WidgetsBindingObserver {
  PictureStoryGenerationController({
    required this.service,
    required this.settings,
    ParentAccessService? parent,
  }) : _parent = parent ?? ParentAccessService.instance {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _parent.addListener(_parentChanged);
    _profiles = ProfileScope.changes.listen((_) {
      _pauseAll('孩子档案已切换，生成已暂停');
    });
  }

  final PictureStoryGenerationService service;
  final SettingsRepository settings;
  final ParentAccessService _parent;
  final _operations = <String, _Operation>{};
  final _states = <String, PictureStoryRunState>{};
  late final StreamSubscription<String> _profiles;
  bool _foreground = true;
  bool _disposed = false;

  PictureStoryRunState stateFor(String profileId) =>
      _states[profileId] ?? const PictureStoryRunState();

  Future<void> start({
    required String profileId,
    required int profileRevision,
    required PictureStoryGenerationOptions options,
    String? candidateId,
    String? reuseImageId,
    bool regenerateImage = false,
  }) {
    if (_disposed) return Future<void>.value();
    final pending = _operations[profileId];
    if (pending != null) return pending.done.future;
    // 凭据读取前即占用任务槽，重进页面或重复点击也不能启动第二次。
    final operation = _Operation(profileId, profileRevision, options);
    _operations[profileId] = operation;
    _setState(operation, PictureStoryRunPhase.preparing);
    unawaited(
      _execute(
        operation,
        candidateId: candidateId,
        reuseImageId: reuseImageId,
        regenerateImage: regenerateImage,
      ),
    );
    return operation.done.future;
  }

  bool _active(_Operation operation) {
    if (_disposed ||
        operation.stopReason != null ||
        !_foreground ||
        !identical(_operations[operation.profileId], operation) ||
        ProfileScope.currentId != operation.profileId ||
        ProfileScope.revision != operation.revision) {
      return false;
    }
    operation.authorize?.call();
    return !settings.hasPendingLlmSave &&
        operation.signature == settings.pictureStoryGenerationSignature;
  }

  bool _allowed(_Operation operation) {
    try {
      return _active(operation);
    } on Object {
      return false;
    }
  }

  Future<void> _execute(
    _Operation operation, {
    String? candidateId,
    String? reuseImageId,
    required bool regenerateImage,
  }) async {
    var phase = PictureStoryRunPhase.finished;
    String? message;
    try {
      operation.authorize = _parent.captureAuthorization();
      if (settings.hasPendingLlmSave) {
        throw const FormatException('大模型设置正在保存，请稍后重试');
      }
      operation.signature = settings.pictureStoryGenerationSignature;
      if (!_allowed(operation)) throw const ImageGenerationCancelled();
      if (service.isRunning(operation.profileId)) {
        throw const FormatException('上一轮生成正在停止，请稍后重试');
      }
      var draft = service.readDraft(operation.profileId);
      operation.options = draft?.options ?? operation.options;
      _setState(operation, PictureStoryRunPhase.preparing);
      final imagePrompt = settings.pictureStoryImageGenerationPromptOverride;
      final questionPrompt =
          settings.pictureStoryQuestionGenerationPromptOverride;
      final images = await settings.readImageGenerationConfig();
      if (!_allowed(operation)) throw const ImageGenerationCancelled();
      if (images == null) throw const FormatException('请先配置图片生成服务');
      var imageSignature = images.selectionSignature;
      final llm = await settings.readLlmConfigForScenario(
        LlmScenario.pictureStory,
      );
      if (!_allowed(operation)) throw const ImageGenerationCancelled();
      if (llm == null) throw const FormatException('请先配置用于看图出题的大模型');
      draft ??= await service.createDraft(operation.options);
      if (!_allowed(operation)) throw const ImageGenerationCancelled();
      operation.pipelineStarted = true;
      _setState(operation, PictureStoryRunPhase.generating);
      await service.run(
        draft: draft,
        config: llm,
        imageConfig: images,
        isActive: () => _allowed(operation),
        onChanged: () => _changed(operation),
        onPlanningAttempt: (attempt) {
          if (_allowed(operation)) {
            _setState(
              operation,
              PictureStoryRunPhase.generating,
              progress: attempt == 1 ? '正在规划场景…' : '正在切换模型，重试场景规划…',
            );
          }
        },
        onLlmSelectionSaved: (signature) => operation.signature = signature,
        onImageAttempt: (index, attempt) {
          if (!_allowed(operation)) return;
          _setState(
            operation,
            PictureStoryRunPhase.generating,
            progress: attempt == 1
                ? '正在生成第 ${index + 1} 道题的图片…'
                : '第 ${index + 1} 道题正在切换生图模型重试（第 $attempt 次）…',
          );
        },
        onImageSuccess: (successful) async {
          final saved = await settings.promoteSuccessfulImageSelection(
            images,
            successful,
            expectedSignature: imageSignature,
            isActive: () => _allowed(operation),
            onSelectionSaved: (signature) => operation.signature = signature,
          );
          if (saved != null) imageSignature = saved;
        },
        onCaptionAttempt: (index, attempt) {
          if (!_allowed(operation)) return;
          _setState(
            operation,
            PictureStoryRunPhase.generating,
            progress: attempt == 1
                ? '正在根据第 ${index + 1} 张图片出题…'
                : '第 ${index + 1} 道题正在重试看图出题（第 $attempt 次）…',
          );
        },
        candidateId: candidateId,
        reuseImageId: reuseImageId,
        regenerateImage: regenerateImage,
        imagePromptOverride: imagePrompt,
        questionPromptOverride: questionPrompt,
      );
      if (!_allowed(operation)) throw const ImageGenerationCancelled();
    } on Object catch (error) {
      if (error is ImageGenerationCancelled ||
          error is LlmGenerationCancelled ||
          operation.stopReason != null) {
        phase = PictureStoryRunPhase.paused;
        message = operation.stopReason ?? '生成已暂停，可重试未完成的步骤';
      } else {
        phase = PictureStoryRunPhase.failed;
        message = switch (error) {
          FormatException() => error.message,
          LlmException() => error.message,
          ParentAccessDenied() => error.toString(),
          _ => '生成未完成，已保存内容会保留，请稍后重试',
        };
      }
    } finally {
      // 回调、停止和终态都属于本次操作，不能覆盖后续任务。
      _setState(operation, phase, message: message);
      if (identical(_operations[operation.profileId], operation)) {
        _operations.remove(operation.profileId);
      }
      operation.done.complete();
    }
  }

  void _changed(_Operation operation) {
    if (!_disposed && identical(_operations[operation.profileId], operation)) {
      notifyListeners();
    }
  }

  void _setState(
    _Operation operation,
    PictureStoryRunPhase phase, {
    String progress = '正在读取生成配置…',
    String? message,
  }) {
    if (_disposed || !identical(_operations[operation.profileId], operation)) {
      return;
    }
    _states[operation.profileId] = PictureStoryRunState(
      phase: phase,
      options: operation.options,
      progress: progress,
      message: message,
    );
    notifyListeners();
  }

  void pause(String profileId, {String reason = '生成已暂停，可重试未完成的步骤'}) {
    final operation = _operations[profileId];
    if (operation == null || operation.stopReason != null) return;
    operation.stopReason = reason;
    if (operation.pipelineStarted) service.pause(profileId);
    _setState(
      operation,
      PictureStoryRunPhase.stopping,
      progress: '正在暂停生成…',
      message: reason,
    );
  }

  void clearStatus(String profileId) {
    if (_disposed || _operations.containsKey(profileId)) return;
    _states.remove(profileId);
    notifyListeners();
  }

  void _pauseAll(String reason) {
    for (final profile in _operations.keys.toList()) {
      pause(profile, reason: reason);
    }
  }

  void _parentChanged() {
    if (!_parent.isUnlocked) _pauseAll('家长授权已结束，生成已暂停');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _pauseAll('应用已离开前台，生成已暂停');
  }

  @override
  void dispose() {
    _disposed = true;
    _pauseAll('生成已暂停，可重试未完成的步骤');
    WidgetsBinding.instance.removeObserver(this);
    _parent.removeListener(_parentChanged);
    unawaited(_profiles.cancel());
    super.dispose();
  }
}
