// lib/data/repositories/picture_story_repository.dart

import 'dart:convert';

import 'package:hive/hive.dart';

import 'package:poemath/core/services/cache_activity.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/picture_story_editor_draft.dart';
import 'package:poemath/data/models/picture_story_generation_draft.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/models/picture_story_prompt.dart';

export 'package:poemath/data/models/picture_story_prompt.dart';

/// 目录删除已提交；文件清理失败不能回滚成一个可能缺图的活动题目。
class PictureStoryImageCleanupException implements Exception {
  const PictureStoryImageCleanupException(this.cause);
  final Object cause;

  @override
  String toString() => '题目已删除，题图清理未完成';
}

/// 旧版内置题仅用于还原练习历史，不再加入可选题库。
class PictureStoryCatalog {
  const PictureStoryCatalog._();

  static const prompts = <PictureStoryPrompt>[
    PictureStoryPrompt(
      id: 'kite-in-the-park',
      title: '公园里的风筝',
      level: PictureStoryLevel.starter,
      theme: '人物与动作',
      illustration: 'kite',
      sceneFacts: ['公园里有一个孩子和一只小狗', '孩子牵着线在放风筝', '天空中有白云和一只风筝'],
      questions: ['图里有哪些人和小动物？', '他们在哪里？', '孩子正在做什么？'],
      goals: ['说清人物、地点和动作', '用完整句子表达'],
      reference: '公园里，一个孩子带着小狗放风筝。风筝飞到了蓝蓝的天空中。',
    ),
    PictureStoryPrompt(
      id: 'rainy-day-umbrella',
      title: '雨天送伞',
      level: PictureStoryLevel.growing,
      theme: '细节与心情',
      illustration: 'umbrella',
      sceneFacts: ['天空正在下雨', '一个孩子撑着伞走向门口', '门口有人在等待'],
      questions: ['你从哪里看出正在下雨？', '孩子要去做什么？', '等待的人可能是什么心情？'],
      goals: ['补充画面细节', '表达人物的心情和原因'],
      reference: '下雨了，孩子撑着伞走到门口，把伞送给正在等待的家人。',
    ),
    PictureStoryPrompt(
      id: 'tidy-up-toys',
      title: '一起收拾玩具',
      level: PictureStoryLevel.growing,
      theme: '顺序与合作',
      illustration: 'toys',
      sceneFacts: ['房间里有很多玩具', '两个孩子一起把玩具放回箱子', '房间慢慢变整齐了'],
      questions: ['房间一开始是什么样子？', '两个孩子先做了什么？', '最后房间有什么变化？'],
      goals: ['按顺序讲清事情', '说出事情的结果'],
      reference: '房间里有许多玩具，两个孩子一起把玩具收进箱子，房间变得整整齐齐。',
    ),
  ];

  static PictureStoryPrompt? find(String id) =>
      prompts.where((prompt) => prompt.id == id).firstOrNull;
}

class PictureStoryRepository {
  PictureStoryRepository({
    Box<dynamic>? settings,
    Box<PictureStoryPracticeRecord>? records,
    PictureStoryImageService? images,
    void Function()? authorize,
  })  : _settings = settings ?? HiveBoxes.settings,
        _records = records ?? HiveBoxes.pictureStoryPractice,
        _images = images ?? PictureStoryImageService.instance,
        _authorize = authorize ?? ParentAccessService.instance.assertAllowed;

  static const catalogKey = 'picture_story_catalog_v1';
  static const enabledSuffix = '_picture_story_enabled_ids';
  static Future<void> _operations = Future<void>.value();

  final Box<dynamic> _settings;
  final Box<PictureStoryPracticeRecord> _records;
  final PictureStoryImageService _images;
  final void Function() _authorize;

  /// 所有仓储实例与备份共用队列，恢复期间不能插入题目发布或启用写入。
  static Future<T> exclusive<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static String enabledKeyFor(String profileId) => '$profileId$enabledSuffix';

  List<String>? _savedEnabledIds(String profileId) {
    final value = _settings.get(enabledKeyFor(profileId));
    if (value is! String) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return null;
      return decoded.whereType<String>().toList();
    } on Object {
      return null;
    }
  }

  bool isEnabled(String promptId) =>
      findPrompt(promptId) != null &&
      (_savedEnabledIds(ProfileScope.currentId) ?? const <String>[])
          .contains(promptId);

  Stream<BoxEvent> watchCatalog() => _settings.watch(key: catalogKey);

  Stream<BoxEvent> watchEnabled(String profileId) =>
      _settings.watch(key: enabledKeyFor(profileId));

  Stream<BoxEvent> watchRecords() => _records.watch();

  PictureStoryCatalogState catalogState() {
    final raw = _settings.get(catalogKey);
    if (raw == null && !_settings.containsKey(catalogKey)) {
      return const PictureStoryCatalogState.empty();
    }
    if (raw is! String) throw const FormatException('本地看图说话题库暂时无法读取');
    return PictureStoryCatalogState.fromJson(jsonDecode(raw));
  }

  PictureStoryPrompt? findPrompt(String id, {int? version}) {
    return _findPrompt(catalogState(), id, version: version);
  }

  PictureStoryPrompt? _findPrompt(
    PictureStoryCatalogState state,
    String id, {
    int? version,
  }) {
    if (version == null && state.deletedIds.contains(id)) return null;
    final local = state.versions.where((prompt) => prompt.id == id);
    if (version != null) {
      return local.where((prompt) => prompt.version == version).firstOrNull ??
          PictureStoryCatalog.prompts
              .where((prompt) => prompt.id == id && prompt.version == version)
              .firstOrNull;
    }
    if (local.isEmpty) return null;
    return local.reduce((a, b) => a.version > b.version ? a : b);
  }

  List<PictureStoryPrompt> listPrompts({bool enabledOnly = false}) {
    final state = catalogState();
    final enabledIds = enabledOnly
        ? (_savedEnabledIds(ProfileScope.currentId) ?? const <String>[]).toSet()
        : null;
    final ids = state.versions.map((prompt) => prompt.id).toSet();
    // 按首次入库的顺序倒序显示，题目的后续版本沿用原排序位置。
    return ids
        .toList()
        .reversed
        .where((id) => !state.deletedIds.contains(id))
        .map((id) => _findPrompt(state, id)!)
        .where((prompt) => enabledIds == null || enabledIds.contains(prompt.id))
        .toList();
  }

  Future<void> setEnabled(String promptId, bool enabled) {
    final profileId = ProfileScope.currentId;
    return exclusive(() async {
      _authorize();
      _checkProfile(profileId);
      if (findPrompt(promptId) == null) {
        throw ArgumentError.value(promptId, 'promptId', '看图说话题目不存在');
      }
      final ids = _savedEnabledIds(profileId) ?? <String>[];
      if (enabled) {
        if (!ids.contains(promptId)) ids.add(promptId);
      } else {
        ids.remove(promptId);
      }
      await _settings.put(enabledKeyFor(profileId), jsonEncode(ids));
    });
  }

  Future<PictureStoryPrompt> savePrompt({
    required PictureStoryPrompt prompt,
    required String profileId,
    PictureStoryPrompt? original,
    bool enableForProfile = true,
  }) =>
      exclusive(() async {
        _authorize();
        _checkProfile(profileId);
        final candidate = prompt.normalized();
        final state = catalogState();
        final current = _findPrompt(state, prompt.id);
        if (original == null) {
          if (current != null ||
              state.deletedIds.contains(prompt.id) ||
              !prompt.id.startsWith('local-')) {
            throw const FormatException('新题标识已存在，请重新打开新增页面');
          }
        } else if (current == null ||
            current.version != original.version ||
            !current.sameContent(original)) {
          throw const FormatException('题目已更新，请保留输入并重新打开编辑');
        }
        if (current != null && current.sameContent(candidate)) return current;

        final saved = candidate.copyWith(version: (current?.version ?? 0) + 1);
        final versions = [...state.versions];
        versions.add(saved);
        final merged = PictureStoryCatalogState(
          versions,
          deletedIds: state.deletedIds,
        );
        await _images.ensureStored(candidate.image);
        _authorize();
        _checkProfile(profileId);
        final values = <String, Object>{
          catalogKey: jsonEncode(merged.toJson()),
        };
        if (original == null && enableForProfile) {
          final ids = _savedEnabledIds(profileId) ?? <String>[];
          if (!ids.contains(saved.id)) ids.add(saved.id);
          values[enabledKeyFor(profileId)] = jsonEncode(ids);
        }
        await _writeSettingsWithRollback(values);
        return saved;
      });

  /// 移出所有孩子的题库；原题版本和图片继续供已开始的练习及历史使用。
  Future<void> deletePrompt({
    required PictureStoryPrompt prompt,
    required String profileId,
  }) =>
      CacheActivity.clear(
        TemporaryCacheKind.pictureStoryImages,
        () => exclusive(() async {
          void check() {
            _authorize();
            _checkProfile(profileId);
          }

          check();
          final state = catalogState();
          if (!state.deletedIds.contains(prompt.id)) {
            final current = _findPrompt(state, prompt.id);
            if (current == null ||
                current.version != prompt.version ||
                !current.sameContent(prompt)) {
              throw const FormatException('题目不存在或已更新，请重新打开题库后再删除');
            }
          }
          final deletedIds = {...state.deletedIds, prompt.id};
          // 包含所有孩子的已完成记录和未完成练习，不能只读取当前档案的历史。
          final practicedVersions = {
            for (final record in _records.values)
              (id: record.promptId, version: record.promptVersion),
          };
          final merged = PictureStoryCatalogState(
            state.versions.where(
              (version) =>
                  !deletedIds.contains(version.id) ||
                  !version.image.isLocal ||
                  practicedVersions.contains(
                    (id: version.id, version: version.version),
                  ),
            ),
            deletedIds: deletedIds,
          );
          final retainedImages = {
            ...merged.imageIds,
            ..._draftImageIds(),
          };
          await _writeSettingsWithRollback(
            {catalogKey: jsonEncode(merged.toJson())},
            operation: '删除',
            check: check,
          );
          // 旧内置题没有本地题图；本地题删除和重试才触发文件回收。
          if (!prompt.image.isLocal && state.imageIds.isEmpty) return;
          try {
            await _images.removeUnreferenced(
              retainedImages,
              authorize: check,
            );
          } on Object catch (error, stackTrace) {
            Error.throwWithStackTrace(
              PictureStoryImageCleanupException(error),
              stackTrace,
            );
          }
        }),
      );

  Set<String> _draftImageIds() {
    final ids = <String>{};
    void retain(PictureStoryEditorDraft draft) {
      for (final image in [draft.image, draft.original?.image]) {
        if (image?.isLocal == true) ids.add(image!.value);
      }
    }

    if (_settings.containsKey(PictureStoryEditorDraft.storageKey)) {
      final raw = _settings.get(PictureStoryEditorDraft.storageKey);
      if (raw is! String) throw const FormatException('编辑草稿暂时无法读取，题图已保留');
      retain(PictureStoryEditorDraft.fromJson(jsonDecode(raw)));
    }
    for (final key in _settings.keys.whereType<String>()) {
      if (!key.endsWith(PictureStoryGenerationDraft.storageSuffix)) continue;
      final draft = PictureStoryGenerationDraft.fromJson(_settings.get(key));
      for (final candidate in draft.candidates) {
        retain(candidate.edit);
      }
    }
    return ids;
  }

  /// AI 候选仅在家长确认后一次性发布；失败补偿目录及当前孩子启用选择。
  /// 固定的新题 id 允许暂存清理失败后的同内容重试，不生成重复题。
  Future<List<PictureStoryPrompt>> saveGeneratedPrompts({
    required List<PictureStoryPrompt> prompts,
    required String profileId,
    required void Function() check,
    required Future<void> Function(
      PictureStoryCatalogState catalog,
      Map<String, List<String>> enabled,
    ) beforeCommit,
  }) {
    final revision = ProfileScope.revision;
    void verify() {
      _authorize();
      _checkProfile(profileId);
      if (revision != ProfileScope.revision) {
        throw const FormatException('孩子档案已切换，请重新打开题库');
      }
      check();
    }

    return exclusive(() async {
      verify();
      if (prompts.isEmpty || prompts.length > 5) {
        throw const FormatException('每次请选择 1–5 道题');
      }
      final candidates = prompts.map((p) => p.normalized()).toList();
      if (candidates.map((p) => p.id).toSet().length != candidates.length) {
        throw const FormatException('生成题目标识重复，请重新生成');
      }
      final state = catalogState();
      final versions = [...state.versions];
      final saved = <PictureStoryPrompt>[];
      for (final candidate in candidates) {
        if (!candidate.id.startsWith('local-') ||
            candidate.version != 1 ||
            state.deletedIds.contains(candidate.id)) {
          throw const FormatException('生成题目标识已失效，请重新生成');
        }
        final existing = _findPrompt(state, candidate.id);
        if (existing != null &&
            (existing.version != 1 || !existing.sameContent(candidate))) {
          throw const FormatException('题目已更新，请重新打开题库');
        }
        if (existing == null) versions.add(candidate);
        saved.add(existing ?? candidate);
      }
      final merged = PictureStoryCatalogState(
        versions,
        deletedIds: state.deletedIds,
      );
      final ids = <String>{
        ...?_savedEnabledIds(profileId),
        ...saved.map((p) => p.id),
      }.toList();
      final enabled = {...enabledByProfile(), profileId: ids};
      for (final prompt in saved) {
        await _images.ensureStored(prompt.image);
        verify();
      }
      await beforeCommit(merged, enabled);
      verify();
      await _writeSettingsWithRollback(
        {
          catalogKey: jsonEncode(merged.toJson()),
          enabledKeyFor(profileId): jsonEncode(ids),
        },
        check: verify,
      );
      return saved;
    });
  }

  Future<void> _writeSettingsWithRollback(
    Map<String, Object> values, {
    String operation = '保存',
    void Function()? check,
  }) async {
    final before = <String, Object?>{
      for (final key in values.keys)
        if (_settings.containsKey(key)) key: _settings.get(key),
    };
    try {
      check?.call();
      await _settings.putAll(values);
      check?.call();
    } on Object catch (error, stackTrace) {
      try {
        for (final key in values.keys) {
          if (!before.containsKey(key)) await _settings.delete(key);
        }
        await _settings.putAll(before);
      } on Object catch (rollbackError) {
        AppLogger.e(
          '看图说话$operation补偿失败',
          tag: 'PictureStory',
          error: rollbackError,
          stackTrace: stackTrace,
        );
        throw FormatException(
          operation == '删除' ? '题目删除及恢复失败，请检查本地存储' : '题目保存及恢复失败，请保留输入并检查本地存储',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static void _checkProfile(String profileId) {
    if (ProfileScope.currentId != profileId) {
      throw const FormatException('孩子档案已切换，请重新打开题库');
    }
  }

  Map<String, List<String>> enabledByProfile() => {
        for (final key in _settings.keys.whereType<String>())
          if (key.endsWith(enabledSuffix))
            key.substring(0, key.length - enabledSuffix.length):
                _savedEnabledIds(
                      key.substring(0, key.length - enabledSuffix.length),
                    ) ??
                    <String>[],
      };

  Map<String, Object?> storageSnapshot() => {
        for (final key in _settings.keys.whereType<String>())
          if (key == catalogKey || key.endsWith(enabledSuffix))
            key: _settings.get(key),
      };

  /// 仅由持有 [exclusive] 的备份恢复/补偿路径调用，保留原始值与键缺失状态。
  Future<void> restoreStorageSnapshot(Map<String, Object?> snapshot) async {
    final currentKeys = storageSnapshot().keys.toList();
    await _settings
        .deleteAll(currentKeys.where((key) => !snapshot.containsKey(key)));
    await _settings.putAll(snapshot);
  }

  /// 图片已验证发布后，由持有 [exclusive] 的恢复路径提交可见目录。
  Future<void> replaceCatalogForRestore(
    PictureStoryCatalogState state,
    Map<String, List<String>> enabled,
  ) async {
    await restoreStorageSnapshot({
      if (state.versions.isNotEmpty || state.deletedIds.isNotEmpty)
        catalogKey: jsonEncode(state.toJson()),
      for (final entry in enabled.entries)
        enabledKeyFor(entry.key): jsonEncode(entry.value),
    });
  }

  List<PictureStoryPracticeRecord> records({String? promptId}) {
    return _records.values
        .where((record) => record.profileId == ProfileScope.currentId)
        .where((record) => promptId == null || record.promptId == promptId)
        .where((record) => record.status == 'completed')
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }

  PictureStoryPracticeRecord? find(String id) {
    final record = _records.get(ProfileScope.key('picture_story:$id'));
    return record?.profileId == ProfileScope.currentId ? record : null;
  }

  Future<void> save(
    PictureStoryPracticeRecord record, {
    void Function()? check,
  }) {
    final snapshot = record.copy();
    final profileId = ProfileScope.currentId;
    final key = ProfileScope.key('picture_story:${snapshot.id}');
    return exclusive(() async {
      check?.call();
      if (snapshot.profileId != profileId ||
          profileId != ProfileScope.currentId) {
        throw StateError('看图说话记录档案不匹配');
      }
      final state = catalogState();
      if (state.deletedIds.contains(snapshot.promptId) &&
          _findPrompt(
                state,
                snapshot.promptId,
                version: snapshot.promptVersion,
              ) ==
              null) {
        throw const FormatException('原题已经删除，无法新增这次练习');
      }
      // 工作中的可变草稿不能通过 Hive 的同实例缓存提前改变已保存记录。
      await _records.put(key, snapshot);
    });
  }

  Future<void> delete(String id) {
    final profileId = ProfileScope.currentId;
    final key = ProfileScope.key('picture_story:$id');
    return exclusive(() async {
      if (profileId != ProfileScope.currentId) return;
      final record = _records.get(key);
      if (record?.profileId == profileId) await _records.delete(key);
    });
  }
}
