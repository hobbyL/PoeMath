// lib/data/repositories/picture_story_repository.dart

import 'dart:convert';

import 'package:hive/hive.dart';

import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/models/picture_story_prompt.dart';

export 'package:poemath/data/models/picture_story_prompt.dart';

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
      (_savedEnabledIds(ProfileScope.currentId) ??
              PictureStoryCatalog.prompts.map((p) => p.id).toList())
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
    final local = state.versions.where((prompt) => prompt.id == id);
    if (version != null) {
      return local.where((prompt) => prompt.version == version).firstOrNull ??
          PictureStoryCatalog.prompts
              .where((prompt) => prompt.id == id && prompt.version == version)
              .firstOrNull;
    }
    if (local.isEmpty) return PictureStoryCatalog.find(id);
    return local.reduce((a, b) => a.version > b.version ? a : b);
  }

  List<PictureStoryPrompt> listPrompts({bool enabledOnly = false}) {
    final state = catalogState();
    final ids = <String>{
      ...PictureStoryCatalog.prompts.map((prompt) => prompt.id),
      ...state.versions.map((prompt) => prompt.id),
    };
    return ids
        .map((id) => _findPrompt(state, id)!)
        .where((prompt) => !enabledOnly || isEnabled(prompt.id))
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
      final ids = _savedEnabledIds(profileId) ??
          PictureStoryCatalog.prompts.map((prompt) => prompt.id).toList();
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
          if (current != null || !prompt.id.startsWith('local-')) {
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
        if (current != null && !versions.any((item) => item.id == current.id)) {
          versions.add(current.copyWith());
        }
        versions.add(saved);
        final merged = PictureStoryCatalogState(versions);
        await _images.ensureStored(candidate.image);
        _authorize();
        _checkProfile(profileId);
        final values = <String, Object>{
          catalogKey: jsonEncode(merged.toJson()),
        };
        if (original == null && enableForProfile) {
          final ids = _savedEnabledIds(profileId) ??
              PictureStoryCatalog.prompts.map((item) => item.id).toList();
          if (!ids.contains(saved.id)) ids.add(saved.id);
          values[enabledKeyFor(profileId)] = jsonEncode(ids);
        }
        final before = <String, Object?>{
          for (final key in values.keys)
            if (_settings.containsKey(key)) key: _settings.get(key),
        };
        try {
          await _settings.putAll(values);
        } on Object catch (error, stackTrace) {
          try {
            for (final key in values.keys) {
              if (!before.containsKey(key)) await _settings.delete(key);
            }
            await _settings.putAll(before);
          } on Object catch (rollbackError) {
            AppLogger.e(
              '看图说话保存补偿失败',
              tag: 'PictureStory',
              error: rollbackError,
              stackTrace: stackTrace,
            );
            throw const FormatException('题目保存及恢复失败，请保留输入并检查本地存储');
          }
          Error.throwWithStackTrace(error, stackTrace);
        }
        return saved;
      });

  static void _checkProfile(String profileId) {
    if (ProfileScope.currentId != profileId) {
      throw const FormatException('孩子档案已切换，请重新打开题目编辑');
    }
  }

  Map<String, List<String>> enabledByProfile() => {
        for (final key in _settings.keys.whereType<String>())
          if (key.endsWith(enabledSuffix))
            key.substring(0, key.length - enabledSuffix.length):
                _savedEnabledIds(
                      key.substring(0, key.length - enabledSuffix.length),
                    ) ??
                    PictureStoryCatalog.prompts.map((item) => item.id).toList(),
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
      if (state.versions.isNotEmpty) catalogKey: jsonEncode(state.toJson()),
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
  }) async {
    check?.call();
    if (record.profileId != ProfileScope.currentId) {
      throw StateError('看图说话记录档案不匹配');
    }
    // 工作中的可变草稿不能通过 Hive 的同实例缓存提前改变已保存记录。
    await _records.put(
      ProfileScope.key('picture_story:${record.id}'),
      record.copy(),
    );
  }

  Future<void> delete(String id) async {
    final key = ProfileScope.key('picture_story:$id');
    final record = _records.get(key);
    if (record?.profileId == ProfileScope.currentId) {
      await _records.delete(key);
    }
  }
}
