import 'dart:convert';

import 'package:poemath/data/models/picture_story_editor_draft.dart';
import 'package:poemath/data/models/picture_story_prompt.dart';

class PictureStoryGenerationOptions {
  PictureStoryGenerationOptions({
    required this.level,
    required this.count,
    required List<String> themes,
    this.requirements = '',
  }) : themes = List.unmodifiable(themes);

  static const availableThemes = [
    '日常生活',
    '校园活动',
    '自然观察',
    '动物朋友',
    '家庭故事',
    '友爱互助',
  ];
  final PictureStoryLevel level;
  final int count;
  final List<String> themes;
  final String requirements;

  void validate() {
    if (count < 1 ||
        count > 5 ||
        themes.isEmpty ||
        themes.length > 6 ||
        themes.toSet().length != themes.length ||
        themes.any((t) => !availableThemes.contains(t)) ||
        requirements.runes.length > 1000) {
      throw const FormatException('请选择主题和 1–5 道题，补充要求不超过 1000 字');
    }
  }

  Map<String, Object> toJson() => {
        'level': level.name,
        'count': count,
        'themes': themes,
        'requirements': requirements,
      };
  factory PictureStoryGenerationOptions.fromJson(Object? value) {
    if (value is! Map ||
        value['count'] is! int ||
        value['themes'] is! List ||
        (value['themes'] as List).any((t) => t is! String) ||
        value['requirements'] is! String) {
      throw const FormatException('生成参数无效');
    }
    final level = PictureStoryLevel.values
        .where((l) => l.name == value['level'])
        .firstOrNull;
    if (level == null) throw const FormatException('生成难度无效');
    final result = PictureStoryGenerationOptions(
      level: level,
      count: value['count'] as int,
      themes: (value['themes'] as List).cast<String>(),
      requirements: value['requirements'] as String,
    );
    result.validate();
    return result;
  }
}

enum PictureStoryGenerationStage {
  planned('等待生成图片'),
  generatingImage('正在生成图片'),
  imageReady('图片已保存，等待出题'),
  generatingText('正在看图出题'),
  ready('待家长确认'),
  published('已入库'),
  needsEditing('内容待完善'),
  failed('生成未完成');

  const PictureStoryGenerationStage(this.label);
  final String label;
}

/// 与手动编辑草稿分开；原始表单允许未完成，永不自动成为正式题。
class PictureStoryGenerationCandidate {
  const PictureStoryGenerationCandidate({
    required this.edit,
    required this.imagePrompt,
    required this.requestId,
    this.stage = PictureStoryGenerationStage.planned,
    this.selected = true,
    this.error,
  });
  final PictureStoryEditorDraft edit;
  final String imagePrompt;
  final String requestId;
  final PictureStoryGenerationStage stage;
  final bool selected;
  final String? error;
  String get id => edit.id;
  bool get isReady => stage == PictureStoryGenerationStage.ready;

  PictureStoryGenerationCandidate copyWith({
    PictureStoryEditorDraft? edit,
    String? requestId,
    PictureStoryGenerationStage? stage,
    bool? selected,
    String? error,
    bool clearError = false,
  }) =>
      PictureStoryGenerationCandidate(
        edit: edit ?? this.edit,
        imagePrompt: imagePrompt,
        requestId: requestId ?? this.requestId,
        stage: stage ?? this.stage,
        selected: selected ?? this.selected,
        error: clearError ? null : error ?? this.error,
      );

  Map<String, Object?> toJson() => {
        'edit': edit.toJson(),
        'imagePrompt': imagePrompt,
        'requestId': requestId,
        'stage': stage.name,
        'selected': selected,
        'error': error,
      };
  factory PictureStoryGenerationCandidate.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) throw const FormatException('生成草稿无效');
    final edit = PictureStoryEditorDraft.fromJson(value['edit']);
    if (edit.image != null && !edit.image!.isLocal) {
      throw const FormatException('生成草稿必须使用已经保存的本地图片');
    }
    final stage = PictureStoryGenerationStage.values
        .where((s) => s.name == value['stage'])
        .firstOrNull;
    final imagePrompt = value['imagePrompt'];
    final requestId = value['requestId'];
    final error = value['error'];
    if (stage == null ||
        edit.original != null ||
        !edit.id.startsWith('local-') ||
        imagePrompt is! String ||
        imagePrompt.trim().isEmpty ||
        imagePrompt.runes.length > 3000 ||
        requestId is! String ||
        !PictureStoryPrompt.isValidId(requestId) ||
        value['selected'] is! bool ||
        (error != null && (error is! String || error.length > 512))) {
      throw const FormatException('生成草稿字段无效');
    }
    if (stage == PictureStoryGenerationStage.ready ||
        stage == PictureStoryGenerationStage.published) {
      edit.toPrompt();
    }
    if ((stage == PictureStoryGenerationStage.imageReady ||
            stage == PictureStoryGenerationStage.generatingText ||
            stage == PictureStoryGenerationStage.needsEditing) &&
        edit.image == null) {
      throw const FormatException('生成草稿缺少图片');
    }
    return PictureStoryGenerationCandidate(
      edit: edit,
      imagePrompt: imagePrompt,
      requestId: requestId,
      stage: stage,
      selected: value['selected'] as bool,
      error: error as String?,
    );
  }
}

class PictureStoryGenerationDraft {
  PictureStoryGenerationDraft({
    required this.id,
    required this.profileId,
    required this.options,
    required List<PictureStoryGenerationCandidate> candidates,
  }) : candidates = List.unmodifiable(candidates);

  final String id;
  final String profileId;
  final PictureStoryGenerationOptions options;
  final List<PictureStoryGenerationCandidate> candidates;
  int get readyCount => candidates.where((c) => c.isReady).length;
  List<PictureStoryPrompt> get selectedPrompts => [
        for (final c in candidates)
          if (c.isReady && c.selected) c.edit.toPrompt(),
      ];

  PictureStoryGenerationDraft copyWith(
    List<PictureStoryGenerationCandidate> items,
  ) =>
      PictureStoryGenerationDraft(
        id: id,
        profileId: profileId,
        options: options,
        candidates: items,
      );

  Map<String, Object> toJson() => {
        'schemaVersion': 1,
        'id': id,
        'profileId': profileId,
        'options': options.toJson(),
        'candidates': candidates.map((c) => c.toJson()).toList(),
      };
  String encode() {
    final data = toJson();
    PictureStoryGenerationDraft.fromJson(data);
    return jsonEncode(data);
  }

  factory PictureStoryGenerationDraft.fromJson(Object? value) {
    final data = value is String ? jsonDecode(value) : value;
    if (data is! Map<String, dynamic> ||
        data['schemaVersion'] != 1 ||
        data['id'] is! String ||
        !PictureStoryPrompt.isValidId(data['id'] as String) ||
        data['profileId'] is! String ||
        (data['profileId'] as String).isEmpty ||
        (data['profileId'] as String).length > 128 ||
        data['candidates'] is! List) {
      throw const FormatException('生成草稿格式不支持');
    }
    final options = PictureStoryGenerationOptions.fromJson(data['options']);
    final items = (data['candidates'] as List)
        .map(PictureStoryGenerationCandidate.fromJson)
        .toList();
    if ((items.isNotEmpty && items.length != options.count) ||
        items.any((c) => c.edit.profileId != data['profileId']) ||
        items.map((c) => c.id).toSet().length != items.length) {
      throw const FormatException('生成草稿归属或数量不一致');
    }
    return PictureStoryGenerationDraft(
      id: data['id'] as String,
      profileId: data['profileId'] as String,
      options: options,
      candidates: items,
    );
  }
}
