part of 'picture_story_practice_record.dart';

/// 一遍已完成口述的快照。文字重评与该遍录音一同归档。
class PictureStoryTake {
  PictureStoryTake({
    required this.id,
    required this.startedAt,
    required this.completedAt,
    required Iterable<PictureStorySegment> segments,
    required this.answerText,
    required this.feedbackJson,
    required this.totalDurationSeconds,
    required this.usedHints,
    this.revisionsJson = '[]',
    this.revisionDraft,
  }) : segments = List.unmodifiable(segments);

  final String id;
  final DateTime startedAt;
  final DateTime completedAt;
  final List<PictureStorySegment> segments;
  final String answerText;
  final String feedbackJson;
  final int totalDurationSeconds;
  final bool usedHints;
  final String revisionsJson;
  final String? revisionDraft;

  Map<String, Object?> toJson({bool portable = false}) => {
    'id': id,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'segments': [
      for (final segment in segments)
        if (portable)
          pictureStoryPortableSegment(segment)
        else
          segment.toJson(),
    ],
    'answerText': answerText,
    'feedbackJson': feedbackJson,
    'totalDurationSeconds': totalDurationSeconds,
    'usedHints': usedHints,
    'revisionsJson': revisionsJson,
    'revisionDraft': revisionDraft,
  };

  factory PictureStoryTake.fromJson(Object? value, {bool portable = false}) {
    final map = _retellingMap(value);
    final revisions = _retellingText(map, 'revisionsJson');
    final rawRevisions = jsonDecode(revisions);
    if (rawRevisions is! List || rawRevisions.length > 2000) {
      throw const FormatException('表达修改记录无效');
    }
    for (final value in rawRevisions) {
      final revision = PictureStoryAnswerRevision.fromJson(value);
      _checkRetellingFeedback(revision.feedbackJson);
    }
    final feedback = _retellingText(map, 'feedbackJson');
    _checkRetellingFeedback(feedback);
    final draft = map['revisionDraft'];
    if (draft != null && draft is! String) {
      throw const FormatException('表达修改草稿无效');
    }
    return PictureStoryTake(
      id: _retellingText(map, 'id', nonempty: true),
      startedAt: _retellingDate(map, 'startedAt'),
      completedAt: _retellingDate(map, 'completedAt'),
      segments: _retellingSegments(map['segments'], portable: portable),
      answerText: _retellingText(map, 'answerText'),
      feedbackJson: feedback,
      totalDurationSeconds: _retellingInt(map, 'totalDurationSeconds'),
      usedHints: _retellingBool(map, 'usedHints'),
      revisionsJson: revisions,
      revisionDraft: draft as String?,
    );
  }

  PictureStoryTake withSegments(Iterable<PictureStorySegment> value) =>
      PictureStoryTake(
        id: id,
        startedAt: startedAt,
        completedAt: completedAt,
        segments: value,
        answerText: answerText,
        feedbackJson: feedbackJson,
        totalDurationSeconds: totalDurationSeconds,
        usedHints: usedHints,
        revisionsJson: revisionsJson,
        revisionDraft: revisionDraft,
      );
}

/// 当前正文仍由记录的原字段持有；此处只保存其身份和此前完成的口述。
class PictureStoryRetellingState {
  PictureStoryRetellingState({
    required Iterable<PictureStoryTake> archived,
    required this.currentId,
    required this.currentStartedAt,
    required this.currentCompletedAt,
  }) : archived = List.unmodifiable(archived) {
    final ids = {currentId};
    if (currentId.trim().isEmpty ||
        this.archived.length > 2000 ||
        this.archived.any((take) => !ids.add(take.id))) {
      throw const FormatException('口述版本标识重复或数量无效');
    }
  }

  final List<PictureStoryTake> archived;
  final String currentId;
  final DateTime currentStartedAt;
  final DateTime currentCompletedAt;

  Map<String, Object?> toJson({bool portable = false}) => {
    'version': 1,
    'archived': [for (final take in archived) take.toJson(portable: portable)],
    'currentId': currentId,
    'currentStartedAt': currentStartedAt.toIso8601String(),
    'currentCompletedAt': currentCompletedAt.toIso8601String(),
  };

  factory PictureStoryRetellingState.fromJson(
    Object? value, {
    bool portable = false,
  }) {
    final map = _retellingMap(value);
    final archived = map['archived'];
    if (map['version'] != 1 || archived is! List || archived.length > 2000) {
      throw const FormatException('口述版本格式不支持');
    }
    return PictureStoryRetellingState(
      archived: archived.map(
        (item) => PictureStoryTake.fromJson(item, portable: portable),
      ),
      currentId: _retellingText(map, 'currentId', nonempty: true),
      currentStartedAt: _retellingDate(map, 'currentStartedAt'),
      currentCompletedAt: _retellingDate(map, 'currentCompletedAt'),
    );
  }
}

/// 重讲期间父记录保持 completed，当前正文与历史均不修改。
class PictureStoryRetellingDraft {
  PictureStoryRetellingDraft({
    required this.id,
    required this.startedAt,
    Iterable<PictureStorySegment> segments = const [],
    this.usedHints = false,
    this.guided = true,
  }) : segments = List.unmodifiable(segments);

  final String id;
  final DateTime startedAt;
  final List<PictureStorySegment> segments;
  final bool usedHints;
  final bool guided;

  String get answerText => segments
      .map((segment) => segment.answerText.trim())
      .where((text) => text.isNotEmpty)
      .join('\n');

  PictureStoryRetellingDraft copyWith({
    Iterable<PictureStorySegment>? segments,
    bool? usedHints,
    bool? guided,
  }) => PictureStoryRetellingDraft(
    id: id,
    startedAt: startedAt,
    segments: segments ?? this.segments,
    usedHints: usedHints ?? this.usedHints,
    guided: guided ?? this.guided,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'startedAt': startedAt.toIso8601String(),
    'segments': [for (final segment in segments) segment.toJson()],
    'usedHints': usedHints,
    'guided': guided,
  };

  factory PictureStoryRetellingDraft.fromJson(Object? value) {
    final map = _retellingMap(value);
    if (map['version'] != 1) throw const FormatException('重讲草稿格式不支持');
    return PictureStoryRetellingDraft(
      id: _retellingText(map, 'id', nonempty: true),
      startedAt: _retellingDate(map, 'startedAt'),
      segments: _retellingSegments(map['segments']),
      usedHints: _retellingBool(map, 'usedHints'),
      guided: _retellingBool(map, 'guided'),
    );
  }
}

Map<String, Object?> pictureStoryPortableSegment(PictureStorySegment segment) =>
    segment.toJson()
      ..remove('audioPath')
      ..remove('recognitionError');

Map<String, dynamic> _retellingMap(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('口述内容必须是对象');
  }
  return value;
}

String _retellingText(
  Map<String, dynamic> map,
  String key, {
  bool nonempty = false,
}) {
  final value = map[key];
  if (value is! String || (nonempty && value.trim().isEmpty)) {
    throw FormatException('口述字段 $key 无效');
  }
  return value;
}

DateTime _retellingDate(Map<String, dynamic> map, String key) {
  final date = DateTime.tryParse(_retellingText(map, key));
  if (date == null) throw FormatException('口述日期 $key 无效');
  return date;
}

int _retellingInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! int || value < 0) throw FormatException('口述字段 $key 无效');
  return value;
}

bool _retellingBool(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! bool) throw FormatException('口述字段 $key 无效');
  return value;
}

void _checkRetellingFeedback(String value) {
  if (value.isNotEmpty && jsonDecode(value) is! Map) {
    throw const FormatException('口述点评格式无效');
  }
}

List<PictureStorySegment> _retellingSegments(
  Object? value, {
  bool portable = false,
}) {
  if (value is! List || value.length > 2000) {
    throw const FormatException('口述分段格式无效');
  }
  final ids = <String>{};
  return [
    for (final raw in value)
      () {
        final map = _retellingMap(raw);
        final id = _retellingText(map, 'id', nonempty: true);
        if (!ids.add(id)) throw const FormatException('口述分段标识重复');
        _retellingInt(map, 'position');
        _retellingInt(map, 'durationSeconds');
        if (portable &&
            ((map['audioPath'] != null && map['audioPath'] != '') ||
                map.containsKey('recognitionError'))) {
          throw const FormatException('备份不得包含录音路径或识别错误');
        }
        return PictureStorySegment.fromJson({
          ...map,
          if (portable) 'audioPath': '',
        });
      }(),
  ];
}
