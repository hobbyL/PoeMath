// lib/data/repositories/picture_story_repository.dart

import 'dart:convert';

import 'package:hive/hive.dart';

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';

enum PictureStoryLevel { starter, growing, storyteller }

class PictureStoryPrompt {
  const PictureStoryPrompt({
    required this.id,
    required this.title,
    required this.level,
    required this.theme,
    required this.sceneFacts,
    required this.questions,
    required this.goals,
    required this.reference,
    required this.illustration,
    this.version = 1,
  });

  final String id;
  final String title;
  final PictureStoryLevel level;
  final String theme;
  final List<String> sceneFacts;
  final List<String> questions;
  final List<String> goals;
  final String reference;
  final String illustration;
  final int version;

  String get levelLabel => switch (level) {
        PictureStoryLevel.starter => '入门',
        PictureStoryLevel.growing => '进阶',
        PictureStoryLevel.storyteller => '提高',
      };
}

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
  })  : _settings = settings ?? HiveBoxes.settings,
        _records = records ?? HiveBoxes.pictureStoryPractice;

  final Box<dynamic> _settings;
  final Box<PictureStoryPracticeRecord> _records;

  String get _enabledKey => ProfileScope.key('picture_story_enabled_ids');

  List<String>? _savedEnabledIds() {
    final value = _settings.get(_enabledKey);
    if (value is! String) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return null;
      return decoded.whereType<String>().toList();
    } on Object {
      return null;
    }
  }

  bool isEnabled(String promptId) => (_savedEnabledIds() ??
          PictureStoryCatalog.prompts.map((p) => p.id).toList())
      .contains(promptId);

  List<PictureStoryPrompt> listPrompts({bool enabledOnly = false}) {
    return PictureStoryCatalog.prompts
        .where((prompt) => !enabledOnly || isEnabled(prompt.id))
        .toList();
  }

  Future<void> setEnabled(String promptId, bool enabled) async {
    if (PictureStoryCatalog.find(promptId) == null) {
      throw ArgumentError.value(promptId, 'promptId', '看图说话题目不存在');
    }
    final ids = _savedEnabledIds() ??
        PictureStoryCatalog.prompts.map((prompt) => prompt.id).toList();
    if (enabled) {
      if (!ids.contains(promptId)) ids.add(promptId);
    } else {
      ids.remove(promptId);
    }
    await _settings.put(_enabledKey, jsonEncode(ids));
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

  Future<void> save(PictureStoryPracticeRecord record) async {
    if (record.profileId != ProfileScope.currentId) {
      throw StateError('看图说话记录档案不匹配');
    }
    await _records.put(ProfileScope.key('picture_story:${record.id}'), record);
  }

  Future<void> delete(String id) async {
    final key = ProfileScope.key('picture_story:$id');
    final record = _records.get(key);
    if (record?.profileId == ProfileScope.currentId) {
      await _records.delete(key);
    }
  }
}
