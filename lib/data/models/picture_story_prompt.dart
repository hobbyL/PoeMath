import 'dart:convert';

enum PictureStoryLevel { starter, growing, storyteller }

enum PictureStoryImageKind { builtin, local }

class PictureStoryImage {
  const PictureStoryImage.builtin(this.value)
      : kind = PictureStoryImageKind.builtin;

  const PictureStoryImage.local(this.value)
      : kind = PictureStoryImageKind.local;

  static const builtinKinds = ['kite', 'umbrella', 'toys'];
  static final _shaPattern = RegExp(r'^[a-f0-9]{64}$');

  final PictureStoryImageKind kind;
  final String value;

  bool get isLocal => kind == PictureStoryImageKind.local;

  static bool isValidSha(String value) => _shaPattern.hasMatch(value);

  void validate() {
    if (isLocal ? !isValidSha(value) : !builtinKinds.contains(value)) {
      throw const FormatException('请选择有效的题目图片');
    }
  }

  Map<String, Object> toJson() => {'kind': kind.name, 'value': value};

  factory PictureStoryImage.fromJson(Object? value) {
    if (value is! Map<String, dynamic> || value['value'] is! String) {
      throw const FormatException('题目图片信息无效');
    }
    final image = switch (value['kind']) {
      'builtin' => PictureStoryImage.builtin(value['value'] as String),
      'local' => PictureStoryImage.local(value['value'] as String),
      _ => throw const FormatException('题目图片来源无效'),
    };
    image.validate();
    return image;
  }

  @override
  bool operator ==(Object other) =>
      other is PictureStoryImage && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

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
    this.imageId,
    this.version = 1,
  });

  static const maxTitleLength = 80;
  static const maxThemeLength = 60;
  static const maxLineLength = 400;
  static const maxLines = 20;
  static const maxReferenceLength = 4000;
  static final _idPattern = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$');

  final String id;
  final String title;
  final PictureStoryLevel level;
  final String theme;
  final List<String> sceneFacts;
  final List<String> questions;
  final List<String> goals;
  final String reference;

  /// 兼容原有内置题构造；本地题图的实际身份由 [imageId] 提供。
  final String illustration;
  final String? imageId;
  final int version;

  PictureStoryImage get image => imageId == null
      ? PictureStoryImage.builtin(illustration)
      : PictureStoryImage.local(imageId!);

  String get levelLabel => level.label;

  static bool isValidId(String value) => _idPattern.hasMatch(value);

  static String checkedText(
    String value, {
    required String label,
    required int maxLength,
    bool required = false,
  }) {
    final result = value.trim();
    if (required && result.isEmpty) throw FormatException('请填写$label');
    if (result.runes.length > maxLength) {
      throw FormatException('$label不能超过 $maxLength 字');
    }
    return result;
  }

  static List<String> checkedLines(
    Iterable<String> values, {
    required String label,
    bool required = false,
  }) {
    final result = values
        .map(
          (value) => checkedText(
            value,
            label: label,
            maxLength: maxLineLength,
          ),
        )
        .where((value) => value.isNotEmpty)
        .toList();
    if (required && result.isEmpty) throw FormatException('请至少填写一条$label');
    if (result.length > maxLines) {
      throw FormatException('$label最多填写 $maxLines 条');
    }
    return List.unmodifiable(result);
  }

  PictureStoryPrompt normalized() {
    if (!isValidId(id) || version < 1) {
      throw const FormatException('题目标识或版本无效');
    }
    image.validate();
    return PictureStoryPrompt(
      id: id,
      title: checkedText(
        title,
        label: '题目标题',
        maxLength: maxTitleLength,
        required: true,
      ),
      level: level,
      theme: checkedText(theme, label: '主题', maxLength: maxThemeLength),
      sceneFacts: checkedLines(sceneFacts, label: '观察提示'),
      questions: checkedLines(questions, label: '引导问题', required: true),
      goals: checkedLines(goals, label: '练习目标'),
      reference: checkedText(
        reference,
        label: '参考表达',
        maxLength: maxReferenceLength,
      ),
      illustration: image.isLocal ? '' : image.value,
      imageId: image.isLocal ? image.value : null,
      version: version,
    );
  }

  PictureStoryPrompt copyWith({
    String? title,
    PictureStoryLevel? level,
    String? theme,
    List<String>? sceneFacts,
    List<String>? questions,
    List<String>? goals,
    String? reference,
    PictureStoryImage? image,
    int? version,
  }) {
    final picture = image ?? this.image;
    return PictureStoryPrompt(
      id: id,
      title: title ?? this.title,
      level: level ?? this.level,
      theme: theme ?? this.theme,
      sceneFacts: List.unmodifiable(sceneFacts ?? this.sceneFacts),
      questions: List.unmodifiable(questions ?? this.questions),
      goals: List.unmodifiable(goals ?? this.goals),
      reference: reference ?? this.reference,
      illustration: picture.isLocal ? '' : picture.value,
      imageId: picture.isLocal ? picture.value : null,
      version: version ?? this.version,
    );
  }

  bool sameContent(PictureStoryPrompt other) =>
      jsonEncode({...toJson(), 'version': 1}) ==
      jsonEncode({...other.toJson(), 'version': 1});

  Map<String, Object> toJson() => {
        'id': id,
        'version': version,
        'title': title,
        'level': level.name,
        'theme': theme,
        'sceneFacts': sceneFacts,
        'questions': questions,
        'goals': goals,
        'reference': reference,
        'image': image.toJson(),
      };

  factory PictureStoryPrompt.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('题目内容必须是对象');
    }
    String text(String key, {bool optional = false}) {
      final result = value[key];
      if (optional && result == null) return '';
      if (result is! String) throw FormatException('题目字段 $key 无效');
      return result;
    }

    List<String> lines(String key) {
      final result = value[key];
      if (result == null && key != 'questions') return const [];
      if (result is! List || result.any((item) => item is! String)) {
        throw FormatException('题目字段 $key 必须是文字列表');
      }
      return result.cast<String>();
    }

    final version = value['version'];
    if (version is! int || version < 1) {
      throw const FormatException('题目版本无效');
    }
    final level = PictureStoryLevel.values
        .where((item) => item.name == value['level'])
        .firstOrNull;
    if (level == null) throw const FormatException('题目难度无效');
    final image = PictureStoryImage.fromJson(value['image']);
    return PictureStoryPrompt(
      id: text('id'),
      version: version,
      title: text('title'),
      level: level,
      theme: text('theme', optional: true),
      sceneFacts: lines('sceneFacts'),
      questions: lines('questions'),
      goals: lines('goals'),
      reference: text('reference', optional: true),
      illustration: image.isLocal ? '' : image.value,
      imageId: image.isLocal ? image.value : null,
    ).normalized();
  }
}

extension PictureStoryLevelLabel on PictureStoryLevel {
  String get label => switch (this) {
        PictureStoryLevel.starter => '入门',
        PictureStoryLevel.growing => '进阶',
        PictureStoryLevel.storyteller => '提高',
      };
}

class PictureStoryCatalogState {
  const PictureStoryCatalogState.empty() : versions = const [];

  PictureStoryCatalogState(Iterable<PictureStoryPrompt> versions)
      : versions = _checkedVersions(versions);

  static const schemaVersion = 1;
  static const maxVersions = 10000;
  final List<PictureStoryPrompt> versions;

  static void _checkCount(int count) {
    if (count > maxVersions) {
      throw const FormatException('题库最多保留 $maxVersions 个版本，请保留当前输入');
    }
  }

  static List<PictureStoryPrompt> _checkedVersions(
    Iterable<PictureStoryPrompt> versions,
  ) {
    final result = List<PictureStoryPrompt>.unmodifiable(versions);
    _checkCount(result.length);
    return result;
  }

  Set<String> get imageIds => {
        for (final prompt in versions)
          if (prompt.image.isLocal) prompt.image.value,
      };

  Map<String, Object> toJson() => {
        'schemaVersion': schemaVersion,
        'versions': versions.map((prompt) => prompt.toJson()).toList(),
      };

  factory PictureStoryCatalogState.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['schemaVersion'] != schemaVersion ||
        value['versions'] is! List) {
      throw const FormatException('看图说话题库格式或版本不支持');
    }
    final rawVersions = value['versions'] as List<dynamic>;
    _checkCount(rawVersions.length);
    final versions = rawVersions.map(PictureStoryPrompt.fromJson).toList();
    final seen = <String, Set<int>>{};
    for (final prompt in versions) {
      final numbers = seen.putIfAbsent(prompt.id, () => {});
      if (!numbers.add(prompt.version)) {
        throw const FormatException('题库包含重复的题目版本');
      }
    }
    for (final numbers in seen.values) {
      if (!numbers.contains(1) ||
          numbers.reduce((a, b) => a > b ? a : b) != numbers.length) {
        throw const FormatException('题库的题目版本不连续');
      }
    }
    return PictureStoryCatalogState(versions);
  }
}
