import 'dart:convert';

import 'package:poemath/data/models/picture_story_prompt.dart';

enum PictureStoryEditorField {
  title,
  theme,
  sceneFacts,
  questions,
  goals,
  reference
}

/// 原始表单文字允许暂时不完整；发布时才使用题目的完整校验。
class PictureStoryEditorDraft {
  // 完整的 20 × 400 rune 多行内容即使全为代理对也能暂存，并留出换行空间。
  static const maxRawFieldLength = 20000;

  PictureStoryEditorDraft({
    required this.id,
    required this.profileId,
    required Map<PictureStoryEditorField, String> fields,
    this.original,
    this.level = PictureStoryLevel.starter,
    this.image,
    this.enableForProfile = true,
    this.pendingRequest,
    this.message,
  }) : fields = Map.unmodifiable(fields);

  factory PictureStoryEditorDraft.create({
    required String id,
    required String profileId,
    PictureStoryPrompt? original,
  }) =>
      PictureStoryEditorDraft(
        id: original?.id ?? id,
        profileId: profileId,
        original: original?.copyWith(),
        level: original?.level ?? PictureStoryLevel.starter,
        image: original?.image,
        fields: {
          PictureStoryEditorField.title: original?.title ?? '',
          PictureStoryEditorField.theme: original?.theme ?? '',
          PictureStoryEditorField.sceneFacts:
              original?.sceneFacts.join('\n') ?? '',
          PictureStoryEditorField.questions:
              original?.questions.join('\n') ?? '',
          PictureStoryEditorField.goals: original?.goals.join('\n') ?? '',
          PictureStoryEditorField.reference: original?.reference ?? '',
        },
      );

  final String id;
  final String profileId;
  final PictureStoryPrompt? original;
  final Map<PictureStoryEditorField, String> fields;
  final PictureStoryLevel level;
  final PictureStoryImage? image;
  final bool enableForProfile;
  final String? pendingRequest;
  final String? message;

  bool matches(String profile, String? promptId) =>
      profileId == profile && original?.id == promptId;

  bool get hasChanges {
    final original = this.original;
    if (original == null) {
      return fields.values.any((text) => text.trim().isNotEmpty) ||
          image != null ||
          level != PictureStoryLevel.starter ||
          !enableForProfile;
    }
    try {
      return !toPrompt().sameContent(original);
    } on FormatException {
      return true;
    }
  }

  PictureStoryEditorDraft copyWith({
    Map<PictureStoryEditorField, String>? fields,
    PictureStoryLevel? level,
    PictureStoryImage? image,
    bool? enableForProfile,
    String? pendingRequest,
    bool clearPendingRequest = false,
    String? message,
    bool clearMessage = false,
  }) =>
      PictureStoryEditorDraft(
        id: id,
        profileId: profileId,
        original: original,
        fields: fields ?? this.fields,
        level: level ?? this.level,
        image: image ?? this.image,
        enableForProfile: enableForProfile ?? this.enableForProfile,
        pendingRequest:
            clearPendingRequest ? null : pendingRequest ?? this.pendingRequest,
        message: clearMessage ? null : message ?? this.message,
      );

  PictureStoryPrompt toPrompt() {
    final image = this.image;
    if (image == null) throw const FormatException('请选择题目图片');
    return PictureStoryPrompt(
      id: id,
      version: original?.version ?? 1,
      title: fields[PictureStoryEditorField.title] ?? '',
      level: level,
      theme: fields[PictureStoryEditorField.theme] ?? '',
      sceneFacts:
          (fields[PictureStoryEditorField.sceneFacts] ?? '').split('\n'),
      questions: (fields[PictureStoryEditorField.questions] ?? '').split('\n'),
      goals: (fields[PictureStoryEditorField.goals] ?? '').split('\n'),
      reference: fields[PictureStoryEditorField.reference] ?? '',
      illustration: image.isLocal ? '' : image.value,
      imageId: image.isLocal ? image.value : null,
    ).normalized();
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'id': id,
        'profileId': profileId,
        'original': original?.toJson(),
        'level': level.name,
        'image': image?.toJson(),
        'enableForProfile': enableForProfile,
        'fields': {
          for (final entry in fields.entries) entry.key.name: entry.value,
        },
        'pendingRequest': pendingRequest,
        'message': message,
      };

  factory PictureStoryEditorDraft.fromJson(Object? value) {
    if (value is! Map<String, dynamic> || value['schemaVersion'] != 1) {
      throw const FormatException('上次编辑内容的格式不支持');
    }
    final id = value['id'];
    final profile = value['profileId'];
    final rawFields = value['fields'];
    final enabled = value['enableForProfile'];
    final pending = value['pendingRequest'];
    final message = value['message'];
    if (id is! String ||
        !PictureStoryPrompt.isValidId(id) ||
        profile is! String ||
        profile.isEmpty ||
        profile.length > 128 ||
        rawFields is! Map<String, dynamic> ||
        enabled is! bool ||
        (pending != null &&
            (pending is! String || !PictureStoryPrompt.isValidId(pending))) ||
        (message != null && (message is! String || message.length > 512))) {
      throw const FormatException('上次编辑内容暂时无法读取');
    }
    final fields = <PictureStoryEditorField, String>{};
    for (final field in PictureStoryEditorField.values) {
      final text = rawFields[field.name];
      if (text is! String || text.length > maxRawFieldLength) {
        throw const FormatException('上次编辑文字暂时无法读取');
      }
      fields[field] = text;
    }
    final level = PictureStoryLevel.values
        .where((item) => item.name == value['level'])
        .firstOrNull;
    if (level == null) throw const FormatException('上次编辑的难度无效');
    final original = value['original'] == null
        ? null
        : PictureStoryPrompt.fromJson(value['original']);
    if (original != null && original.id != id) {
      throw const FormatException('上次编辑的题目标识不匹配');
    }
    return PictureStoryEditorDraft(
      id: id,
      profileId: profile,
      original: original,
      fields: fields,
      level: level,
      image: value['image'] == null
          ? null
          : PictureStoryImage.fromJson(value['image']),
      enableForProfile: enabled,
      pendingRequest: pending as String?,
      message: message as String?,
    );
  }

  String encode() {
    final data = toJson();
    try {
      // 生产者必须使用同一读取契约，不能把无法恢复的快照写入 Hive。
      PictureStoryEditorDraft.fromJson(data);
    } on FormatException {
      throw const FormatException('编辑内容无法暂存，请精简文字后重试');
    }
    return jsonEncode(data);
  }
}
