import 'dart:convert';
import 'dart:math';

import 'package:hive/hive.dart';
import 'package:poemath/core/prompts/generation_prompt_defaults.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/cache_activity.dart';
import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/services/image_generation_client.dart';
import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/image_generation_config.dart';
import 'package:poemath/data/models/picture_story_editor_draft.dart';
import 'package:poemath/data/models/picture_story_generation_draft.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';

class PictureStoryPublicationCleanupException implements Exception {
  const PictureStoryPublicationCleanupException(this.count);
  final int count;
  @override
  String toString() => '已入库 $count 道题，草稿暂未清理；再次确认不会重复添加';
}

/// 只有在家长授权时才能取得编辑会话；后续原始输入可保存在原草稿中。
class PictureStoryGenerationEditSession {
  const PictureStoryGenerationEditSession._(this.batchId, this.candidate);
  final String batchId;
  final PictureStoryGenerationCandidate candidate;
}

class _GenerationRun {
  _GenerationRun(this.llm, this.images);
  final LlmClient llm;
  final ImageGenerationClient? images;
  bool cancelled = false;
  void cancel() {
    cancelled = true;
    llm.close();
    images?.close();
  }
}

/// 每个孩子独立暂存。单题直接按要求生图；多题先规划不同场景。
/// 图片保存后再基于实际画面出题。
/// 候选与单次请求双重归属校验，迟到结果只能更新原草稿，不能自动发布。
class PictureStoryGenerationService {
  PictureStoryGenerationService({
    Box<dynamic>? settings,
    PictureStoryImageService? images,
    PictureStoryRepository? repository,
    BackupService? backup,
    LlmClient Function(bool Function() isActive)? llmFactory,
    ImageGenerationClient Function(bool Function() isActive)? imageFactory,
    void Function()? authorize,
  }) : _settingsOverride = settings,
       _images = images ?? PictureStoryImageService.instance,
       _repositoryOverride = repository,
       _backupOverride = backup,
       _llmFactory = llmFactory ?? ((active) => LlmClient(isActive: active)),
       _imageFactory =
           imageFactory ??
           ((active) => ImageGenerationClient(isActive: active)),
       _authorize = authorize ?? ParentAccessService.instance.assertAllowed;

  static const draftSuffix = PictureStoryGenerationDraft.storageSuffix;
  static Future<void> _operations = Future<void>.value();
  static final Map<String, _GenerationRun> _runs = {};
  final Box<dynamic>? _settingsOverride;
  final PictureStoryImageService _images;
  final PictureStoryRepository? _repositoryOverride;
  final BackupService? _backupOverride;
  final LlmClient Function(bool Function()) _llmFactory;
  final ImageGenerationClient Function(bool Function()) _imageFactory;
  final void Function() _authorize;
  Box<dynamic> get _settings => _settingsOverride ?? HiveBoxes.settings;
  PictureStoryRepository get _repository =>
      _repositoryOverride ?? PictureStoryRepository(images: _images);
  BackupService get _backup =>
      _backupOverride ?? BackupService(pictureStoryImages: _images);
  static String keyFor(String profileId) => '$profileId$draftSuffix';
  static String _id(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}';

  static Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  PictureStoryGenerationDraft? readDraft(String profileId) {
    final key = keyFor(profileId);
    if (!_settings.containsKey(key)) return null;
    final draft = PictureStoryGenerationDraft.fromJson(_settings.get(key));
    if (draft.profileId != profileId) {
      throw const FormatException('生成草稿的孩子档案不匹配');
    }
    return draft;
  }

  bool isRunning(String profileId) => _runs.containsKey(profileId);
  void pause(String profileId) => _runs[profileId]?.cancel();

  Future<PictureStoryGenerationDraft> createDraft(
    PictureStoryGenerationOptions options,
  ) {
    _authorize();
    options.validate();
    final profile = ProfileScope.currentId;
    final revision = ProfileScope.revision;
    return _serial(() async {
      _checkScope(profile, revision);
      if (readDraft(profile) != null || isRunning(profile)) {
        throw const FormatException('请先处理或放弃当前生成草稿');
      }
      final draft = PictureStoryGenerationDraft(
        id: _id('batch'),
        profileId: profile,
        options: options,
        candidates: [],
      );
      await _settings.put(keyFor(profile), draft.encode());
      return draft;
    });
  }

  Future<void> discardDraft(PictureStoryGenerationDraft draft) {
    _authorize();
    final revision = ProfileScope.revision;
    pause(draft.profileId);
    return _serial(() async {
      _checkScope(draft.profileId, revision);
      if (readDraft(draft.profileId)?.id == draft.id) {
        await _settings.delete(keyFor(draft.profileId));
      }
    });
  }

  void _checkScope(String profile, int revision) {
    _authorize();
    if (profile != ProfileScope.currentId ||
        revision != ProfileScope.revision) {
      throw const FormatException('孩子档案已切换，请重新打开题库');
    }
  }

  Future<bool> _update(
    PictureStoryGenerationDraft owner,
    PictureStoryGenerationCandidate candidate, {
    required String expectedRequest,
    void Function()? check,
  }) => _serial(() async {
    check?.call();
    final saved = readDraft(owner.profileId);
    if (saved == null || saved.id != owner.id) return false;
    final index = saved.candidates.indexWhere((c) => c.id == candidate.id);
    if (index < 0 ||
        saved.candidates[index].requestId != expectedRequest ||
        saved.candidates[index].stage ==
            PictureStoryGenerationStage.published) {
      return false;
    }
    final items = [...saved.candidates];
    // 保留独立的家长勾选，异步结果不把选择恢复成请求开始时的值。
    items[index] = candidate.copyWith(selected: items[index].selected);
    await _settings.put(
      keyFor(owner.profileId),
      saved.copyWith(items).encode(),
    );
    return true;
  });

  Future<void> run({
    required PictureStoryGenerationDraft draft,
    required LlmConfig config,
    required ImageGenerationConfig imageConfig,
    required bool Function() isActive,
    void Function()? onChanged,
    void Function(int attempt)? onPlanningAttempt,
    void Function(String signature)? onLlmSelectionSaved,
    String? candidateId,
    String? reuseImageId,
    bool regenerateImage = false,
    String? imagePromptOverride,
    String? questionPromptOverride,
  }) async {
    final profile = draft.profileId;
    final revision = ProfileScope.revision;
    _checkScope(profile, revision);
    if (!isActive()) throw const ImageGenerationCancelled();
    if (isRunning(profile)) throw const FormatException('上一轮生成正在停止，请稍后重试');
    if (reuseImageId != null && (candidateId == null || regenerateImage)) {
      throw const FormatException('重试出题必须指定已有题图');
    }
    if (![config, ...config.fallbacks].any((c) => c.supportsVision)) {
      throw const FormatException('请为看图说话出题配置支持看图的大模型');
    }
    if (reuseImageId == null &&
        (imagePromptOverride?.trim().runes.length ?? 0) >
            kPictureStoryImagePromptMaxLength) {
      throw const ImageGenerationException('生图提示词过长，请缩短后重试');
    }
    if ((questionPromptOverride?.trim().runes.length ?? 0) >
        kPictureStoryQuestionPromptMaxLength) {
      throw const FormatException('看图出题提示词过长，请缩短后重试');
    }
    final planningPrompt = buildPictureStoryPlanningPrompt(imagePromptOverride);
    final questionPrompt = buildPictureStoryQuestionPrompt(
      questionPromptOverride,
    );
    late final _GenerationRun run;
    String? currentCandidate;
    String? currentRequest;
    bool active() {
      if (run.cancelled ||
          !isActive() ||
          ProfileScope.currentId != profile ||
          ProfileScope.revision != revision) {
        return false;
      }
      try {
        _authorize();
      } on Object {
        return false;
      }
      final saved = readDraft(profile);
      return saved?.id == draft.id &&
          (currentCandidate == null ||
              saved!.candidates.any(
                (c) =>
                    c.id == currentCandidate && c.requestId == currentRequest,
              ));
    }

    run = _GenerationRun(
      _llmFactory(active),
      reuseImageId == null ? _imageFactory(active) : null,
    );
    _runs[profile] = run;
    void check() {
      if (!active()) throw const ImageGenerationCancelled();
    }

    void changed() {
      if (isActive()) onChanged?.call();
    }

    try {
      check();
      var saved = readDraft(profile)!;
      if (reuseImageId != null) {
        final target = saved.candidates
            .where((candidate) => candidate.id == candidateId)
            .firstOrNull;
        if (target?.edit.image?.value != reuseImageId) {
          throw const FormatException('题图已变化，请重新打开草稿后重试出题');
        }
      }
      if (saved.candidates.isEmpty) {
        final items = await _plan(
          saved,
          config,
          run.llm,
          planningPrompt,
          onAttempt: onPlanningAttempt,
          onSelectionSaved: onLlmSelectionSaved,
        );
        check();
        await _serial(() async {
          final current = readDraft(profile);
          check();
          if (current?.id == saved.id && current!.candidates.isEmpty) {
            await _settings.put(
              keyFor(profile),
              current.copyWith(items).encode(),
            );
          }
        });
        saved = readDraft(profile)!;
        changed();
      }
      for (final original in saved.candidates) {
        if (candidateId != null && original.id != candidateId) continue;
        if (original.stage == PictureStoryGenerationStage.published ||
            (original.stage == PictureStoryGenerationStage.needsEditing &&
                !regenerateImage) ||
            (original.isReady && !regenerateImage)) {
          continue;
        }
        check();
        var item = original.copyWith(
          requestId: _id('request'),
          clearError: true,
        );
        if (regenerateImage) {
          item = item.copyWith(
            edit: PictureStoryEditorDraft.create(
              id: item.id,
              profileId: profile,
            ).copyWith(level: saved.options.level),
            stage: PictureStoryGenerationStage.planned,
          );
        }
        if (!await _update(saved, item, expectedRequest: original.requestId)) {
          throw const ImageGenerationCancelled();
        }
        currentCandidate = item.id;
        currentRequest = item.requestId;
        try {
          if (item.edit.image == null) {
            item = item.copyWith(
              stage: PictureStoryGenerationStage.generatingImage,
            );
            await _update(saved, item, expectedRequest: item.requestId);
            changed();
            check();
            final bytes = await run.images!.generate(
              config: imageConfig,
              prompt: buildPictureStoryImagePrompt(
                item.imagePrompt,
                promptOverride: imagePromptOverride,
              ),
            );
            await CacheActivity.use(
              TemporaryCacheKind.pictureStoryImages,
              () async {
                final image = await _images.importBytes(bytes);
                item = item.copyWith(
                  edit: item.edit.copyWith(image: image),
                  stage: PictureStoryGenerationStage.imageReady,
                );
                // 租约持续到引用落盘，清理不能插入图片发布与草稿保存之间。
                if (!await _update(
                  saved,
                  item,
                  expectedRequest: item.requestId,
                )) {
                  throw const ImageGenerationCancelled();
                }
              },
            );
            changed();
          }
          check();
          item = item.copyWith(
            stage: PictureStoryGenerationStage.generatingText,
          );
          await _update(saved, item, expectedRequest: item.requestId);
          changed();
          final edit = await _describe(
            item,
            saved.options.level,
            config,
            run.llm,
            questionPrompt,
            onSelectionSaved: onLlmSelectionSaved,
          );
          check();
          item = item.copyWith(
            edit: edit,
            stage: PictureStoryGenerationStage.ready,
            clearError: true,
          );
          if (!await _update(saved, item, expectedRequest: item.requestId)) {
            throw const ImageGenerationCancelled();
          }
          changed();
        } on Object catch (error) {
          final stopped = !active();
          if (!stopped) {
            AppLogger.w(
              '生成未完成：${item.stage.name}，${error.runtimeType}',
              tag: 'PictureStory',
            );
          }
          item = item.copyWith(
            stage: stopped
                ? (item.edit.image == null
                      ? PictureStoryGenerationStage.planned
                      : PictureStoryGenerationStage.imageReady)
                : PictureStoryGenerationStage.failed,
            error: stopped ? '生成已暂停，可继续未完成的步骤' : _message(error),
          );
          await _update(saved, item, expectedRequest: item.requestId);
          changed();
          if (stopped) break;
          // 本机额度和服务限流不应继续消耗其余题的请求。
          if (error is CloudQuotaExceededException ||
              error is ImageGenerationException ||
              error is LlmRateLimitError ||
              error is LlmAuthError) {
            break;
          }
        }
      }
    } finally {
      run.cancel();
      if (identical(_runs[profile], run)) _runs.remove(profile);
      changed();
    }
  }

  static Object? _json(String? content) {
    var text = content?.trim() ?? '';
    if (text.startsWith('```') && text.endsWith('```')) {
      final firstLine = text.indexOf('\n');
      if (firstLine >= 0) {
        text = text.substring(firstLine + 1, text.length - 3).trim();
      }
    }
    return jsonDecode(text);
  }

  Future<List<PictureStoryGenerationCandidate>> _plan(
    PictureStoryGenerationDraft draft,
    LlmConfig config,
    LlmClient client,
    String systemPrompt, {
    void Function(int attempt)? onAttempt,
    void Function(String signature)? onSelectionSaved,
  }) async {
    // 单题无需跨题去重，生图模型可以直接理解主题和补充要求。
    // 保存同样的候选检查点，后续暂停、重试、看图和家长确认保持一致。
    if (draft.options.count == 1) {
      return [
        _candidateFor(
          draft,
          '请构思并绘制一个符合以下要求的儿童单图场景。\n'
          '难度：${draft.options.level.label}\n'
          '主题：${draft.options.themes.join('、')}\n'
          '补充要求：${draft.options.requirements}',
        ),
      ];
    }
    final timer = Stopwatch()..start();
    final items = <PictureStoryGenerationCandidate>[];
    var attempt = 0;
    // 多题回复可能缺项或包裹在 scenes 中；仅允许一次有界补全，不重复生图。
    for (var round = 0; round < 2; round++) {
      String? problem;
      Never invalidPlan(String message) {
        problem = message;
        throw FormatException(message);
      }

      final remaining = draft.options.count - items.length;
      late List<PictureStoryGenerationCandidate> planned;
      try {
        final response = await client.chatComplete(
          config: config,
          systemPrompt: systemPrompt,
          stream: true,
          messages: [
            ChatMessage(
              role: ChatRole.user,
              content:
                  '难度：${draft.options.level.label}\n'
                  '主题：${draft.options.themes.join('、')}\n'
                  '补充要求：${draft.options.requirements}\n'
                  '严格生成 $remaining 个不同的单图场景。\n'
                  '${items.isEmpty ? '' : '已规划的场景（请勿重复）：${jsonEncode(items.map((item) => item.imagePrompt).toList())}\n'}'
                  '${round == 0 ? '' : '请补全上一次规划，确保数量、JSON 格式与字段符合要求。\n'}'
                  '示例格式：[{"imagePrompt":"具体场景描述"}]，不要添加解释。',
            ),
          ],
          maxTokens: min(8192, 512 + remaining * 2200),
          onAttempt: (_) => onAttempt?.call(++attempt),
          validate: (response) {
            final Object? decoded;
            try {
              decoded = _json(response.content);
            } on FormatException {
              invalidPlan('场景规划未返回完整 JSON');
            }
            final data = decoded is Map ? decoded['scenes'] : decoded;
            if (data is! List || data.isEmpty || data.length > remaining) {
              invalidPlan('场景规划数量不完整，需要 $remaining 个场景');
            }
            try {
              planned = [
                for (final value in data) _plannedCandidate(value, draft),
              ];
            } on FormatException {
              invalidPlan('场景描述缺失或过长');
            }
            final descriptions = <String>{
              for (final item in items) item.imagePrompt.trim(),
            };
            for (final item in planned) {
              if (!descriptions.add(item.imagePrompt.trim())) {
                invalidPlan('场景规划存在重复，请生成不同场景');
              }
            }
          },
        );
        items.addAll(planned);
        if (items.length != draft.options.count) continue;
        await client.acceptCompletion(
          response,
          onSelectionSaved: onSelectionSaved,
        );
        break;
      } on LlmResponseFormatError catch (error) {
        // 传输层已完成模型回退；保留截断或请求限制的明确错误。
        if (problem == null || !error.retryable) rethrow;
        if (round == 1) {
          throw LlmResponseFormatError('$problem，请重试或切换模型');
        }
      }
    }
    if (items.length != draft.options.count) {
      throw LlmResponseFormatError(
        '场景规划只完成 ${items.length}/${draft.options.count} 题，请重试',
      );
    }
    AppLogger.d(
      '场景规划完成：${timer.elapsedMilliseconds}ms，${items.length} 道',
      tag: 'PictureStory',
    );
    return items;
  }

  static PictureStoryGenerationCandidate _plannedCandidate(
    Object? value,
    PictureStoryGenerationDraft draft,
  ) {
    if (value is! Map ||
        value['imagePrompt'] is! String ||
        (value['imagePrompt'] as String).trim().isEmpty ||
        (value['imagePrompt'] as String).runes.length >
            kPictureStorySceneDescriptionMaxLength) {
      throw const FormatException('场景规划内容无效，请重新生成');
    }
    return _candidateFor(draft, (value['imagePrompt'] as String).trim());
  }

  static PictureStoryGenerationCandidate _candidateFor(
    PictureStoryGenerationDraft draft,
    String imagePrompt,
  ) => PictureStoryGenerationCandidate(
    edit: PictureStoryEditorDraft.create(
      id: _id('local'),
      profileId: draft.profileId,
    ).copyWith(level: draft.options.level),
    imagePrompt: imagePrompt,
    requestId: _id('request'),
  );

  Future<PictureStoryEditorDraft> _describe(
    PictureStoryGenerationCandidate item,
    PictureStoryLevel level,
    LlmConfig config,
    LlmClient client,
    String systemPrompt, {
    void Function(String signature)? onSelectionSaved,
  }) async {
    final timer = Stopwatch()..start();
    final bytes = await _images.readForVision(item.edit.image!.value);
    AppLogger.d(
      '看图上传准备：${timer.elapsedMilliseconds}ms，${bytes.length} bytes',
      tag: 'PictureStory',
    );
    timer.reset();
    final text =
        '观察这张实际图片，为${level.label}难度编写看图说话练习。'
        '不要以原始生图描述作为画面事实。';
    late PictureStoryEditorDraft edit;
    final response = await client.chatComplete(
      config: config,
      requiresVision: true,
      systemPrompt: systemPrompt,
      stream: true,
      messages: [
        ChatMessage(
          role: ChatRole.user,
          content: text,
          contentParts: [
            {'type': 'text', 'text': text},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/png;base64,${base64Encode(bytes)}',
              },
            },
          ],
        ),
      ],
      maxTokens: 3000,
      validate: (response) {
        edit = _parseDescription(item, level, response.content);
      },
    );
    AppLogger.d('看图出题响应：${timer.elapsedMilliseconds}ms', tag: 'PictureStory');
    await client.acceptCompletion(response, onSelectionSaved: onSelectionSaved);
    return edit;
  }

  static PictureStoryEditorDraft _parseDescription(
    PictureStoryGenerationCandidate item,
    PictureStoryLevel level,
    String? content,
  ) {
    final value = _json(content);
    if (value is! Map) throw const FormatException('看图出题内容无效');
    String string(String key, {bool optional = false}) {
      final raw = value[key];
      if (optional && raw == null) return '';
      if (raw is! String) throw const FormatException('看图出题字段无效');
      return raw;
    }

    List<String> lines(String key, {bool optional = false}) {
      final raw = value[key];
      if (optional && raw == null) return [];
      if (raw is! List || raw.any((v) => v is! String)) {
        throw const FormatException('看图出题字段无效');
      }
      return raw.cast<String>();
    }

    final prompt = PictureStoryPrompt(
      id: item.id,
      title: string('title'),
      level: level,
      theme: string('theme', optional: true),
      sceneFacts: lines('sceneFacts', optional: true),
      questions: lines('questions'),
      goals: lines('goals', optional: true),
      reference: string('reference', optional: true),
      illustration: '',
      imageId: item.edit.image!.value,
    ).normalized();
    final populated = PictureStoryEditorDraft.create(
      id: item.id,
      profileId: item.edit.profileId,
      original: prompt,
    );
    final edit = PictureStoryEditorDraft(
      id: item.id,
      profileId: item.edit.profileId,
      level: prompt.level,
      image: prompt.image,
      fields: populated.fields,
    );
    // 编辑器按换行保存列表，连同最终落盘结构一起校验后才接受模型。
    edit.toPrompt();
    return edit;
  }

  Future<void> setSelected(
    PictureStoryGenerationDraft draft,
    String id,
    bool selected,
  ) {
    _authorize();
    final revision = ProfileScope.revision;
    return _serial(() async {
      _checkScope(draft.profileId, revision);
      final saved = readDraft(draft.profileId);
      if (saved?.id != draft.id) throw const FormatException('生成草稿已变化');
      final items = [
        for (final c in saved!.candidates)
          c.id == id ? c.copyWith(selected: selected) : c,
      ];
      await _settings.put(
        keyFor(draft.profileId),
        saved.copyWith(items).encode(),
      );
    });
  }

  Future<PictureStoryGenerationEditSession> beginEdit(
    PictureStoryGenerationDraft draft,
    String id,
  ) async {
    _authorize();
    final revision = ProfileScope.revision;
    _checkScope(draft.profileId, revision);
    if (isRunning(draft.profileId)) throw const FormatException('请先暂停生成再编辑');
    final item = readDraft(draft.profileId)?.candidates
        .where((c) => c.id == id)
        .firstOrNull;
    if (item == null ||
        item.edit.image == null ||
        item.stage == PictureStoryGenerationStage.published) {
      throw const FormatException('请先生成图片');
    }
    final next = item.copyWith(requestId: _id('edit'));
    if (!await _update(
      draft,
      next,
      expectedRequest: item.requestId,
      check: () => _checkScope(draft.profileId, revision),
    )) {
      throw const FormatException('草稿已变化，请重新打开');
    }
    return PictureStoryGenerationEditSession._(draft.id, next);
  }

  PictureStoryEditorDraft? readEdit(PictureStoryGenerationEditSession session) {
    final saved = readDraft(session.candidate.edit.profileId);
    if (saved?.id != session.batchId) return null;
    return saved!.candidates
        .where(
          (c) =>
              c.id == session.candidate.id &&
              c.requestId == session.candidate.requestId &&
              c.stage != PictureStoryGenerationStage.published,
        )
        .firstOrNull
        ?.edit;
  }

  Future<void> saveEdit(
    PictureStoryGenerationEditSession session,
    PictureStoryEditorDraft edit,
  ) async {
    final owner = session.candidate;
    if (edit.id != owner.id ||
        edit.profileId != owner.edit.profileId ||
        edit.image != owner.edit.image ||
        edit.original != null) {
      throw const FormatException('编辑内容归属不匹配');
    }
    var stage = PictureStoryGenerationStage.ready;
    try {
      edit.toPrompt();
    } on FormatException {
      stage = PictureStoryGenerationStage.needsEditing;
    }
    final draft = readDraft(edit.profileId);
    if (draft == null ||
        draft.id != session.batchId ||
        !await _update(
          draft,
          owner.copyWith(edit: edit, stage: stage, clearError: true),
          expectedRequest: owner.requestId,
        )) {
      throw const FormatException('生成草稿已变化，修改未保存');
    }
  }

  Future<int> publish(
    PictureStoryGenerationDraft draft, {
    required void Function() check,
  }) async {
    _authorize();
    if (isRunning(draft.profileId)) throw const FormatException('请先暂停生成再确认入库');
    final saved = readDraft(draft.profileId);
    if (saved == null || saved.id != draft.id) {
      throw const FormatException('生成草稿已变化');
    }
    final prompts = saved.selectedPrompts;
    final snapshot = saved.encode();
    void verify() {
      check();
      if (readDraft(draft.profileId)?.encode() != snapshot ||
          isRunning(draft.profileId)) {
        throw const FormatException('生成草稿已变化，请重新确认入库内容');
      }
    }

    final result = await _repository.saveGeneratedPrompts(
      prompts: prompts,
      profileId: draft.profileId,
      check: verify,
      beforeCommit: _backup.validatePictureStoryPublication,
    );
    try {
      await _serial(() async {
        final current = readDraft(draft.profileId);
        if (current?.id != draft.id) return;
        final ids = result.map((p) => p.id).toSet();
        final items = [
          for (final c in current!.candidates)
            ids.contains(c.id)
                ? c.copyWith(
                    stage: PictureStoryGenerationStage.published,
                    selected: false,
                  )
                : c,
        ];
        if (items.every(
          (c) => c.stage == PictureStoryGenerationStage.published,
        )) {
          await _settings.delete(keyFor(draft.profileId));
        } else {
          await _settings.put(
            keyFor(draft.profileId),
            current.copyWith(items).encode(),
          );
        }
      });
    } on Object {
      throw PictureStoryPublicationCleanupException(result.length);
    }
    return result.length;
  }

  static String _message(Object error) => switch (error) {
    ImageGenerationException() => error.message,
    CloudQuotaExceededException() => error.message,
    PictureStoryImageException() => error.message,
    LlmAuthError() => '大模型访问失败，请检查密钥和模型权限',
    LlmNetworkError() => '看图出题请求超时或网络不可用，可保留图片重试',
    LlmRateLimitError() => '看图模型额度已用尽或请求受限，请切换模型或稍后保留图片重试',
    LlmServerError() => '看图模型服务请求失败，请检查服务或稍后重试',
    LlmResponseFormatError(retryable: false) => '看图出题内容超出上传限制，请调整图片或补充要求后重试',
    LlmResponseFormatError() || FormatException() => '看图出题内容不完整或格式不正确，可保留图片重试',
    _ => '看图出题未完成，可重试或编辑已生成的图片',
  };
}
