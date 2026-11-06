// lib/data/models/picture_story_practice_record.dart
//
// 看图说话的练习历史与草稿。录音片段使用 JSON 保存，是为了让题目版本、
// 原始转写和孩子修改后的答案在一次练习中保持同一份可迁移快照。

import 'dart:convert';

import 'package:hive/hive.dart';

class PictureStorySegment {
  const PictureStorySegment({
    required this.id,
    required this.position,
    required this.audioPath,
    required this.durationSeconds,
    this.transcript = '',
    this.editedText,
    this.recognitionMode = 'pending',
    this.recognitionError,
  });

  final String id;
  final int position;
  final String audioPath;
  final int durationSeconds;
  final String transcript;

  /// null 表示未编辑，空串表示孩子主动清空。
  final String? editedText;
  final String recognitionMode;
  final String? recognitionError;

  String get answerText => editedText ?? transcript;

  PictureStorySegment copyWith({
    int? position,
    String? audioPath,
    int? durationSeconds,
    String? transcript,
    String? editedText,
    String? recognitionMode,
    String? recognitionError,
    bool clearRecognitionError = false,
  }) => PictureStorySegment(
    id: id,
    position: position ?? this.position,
    audioPath: audioPath ?? this.audioPath,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    transcript: transcript ?? this.transcript,
    editedText: editedText ?? this.editedText,
    recognitionMode: recognitionMode ?? this.recognitionMode,
    recognitionError: clearRecognitionError
        ? null
        : recognitionError ?? this.recognitionError,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'answerVersion': 2,
    'id': id,
    'position': position,
    'audioPath': audioPath,
    'durationSeconds': durationSeconds,
    'transcript': transcript,
    'editedText': editedText,
    'recognitionMode': recognitionMode,
    if (recognitionError != null) 'recognitionError': recognitionError,
  };

  factory PictureStorySegment.fromJson(Map<String, dynamic> json) {
    return PictureStorySegment(
      id: json['id'] as String,
      position: (json['position'] as num?)?.toInt() ?? 0,
      audioPath: json['audioPath'] as String,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      transcript: json['transcript'] as String? ?? '',
      editedText: json['answerVersion'] == 2
          ? json['editedText'] as String?
          : ((json['editedText'] as String?)?.trim().isNotEmpty == true
                ? json['editedText'] as String
                : null),
      recognitionMode: json['recognitionMode'] as String? ?? 'pending',
      recognitionError: json['recognitionError'] as String?,
    );
  }
}

class PictureStoryPracticeRecord extends HiveObject {
  PictureStoryPracticeRecord({
    required this.id,
    required this.profileId,
    required this.promptId,
    required this.promptVersion,
    required this.startedAt,
    required this.status,
    required this.segmentsJson,
    this.completedAt,
    this.answerText = '',
    this.feedbackJson = '',
    this.totalDurationSeconds = 0,
    this.usedHints = false,
    this.revisionsJson = '[]',
    this.revisionDraft,
    this.feedbackRevision = 0,
  });

  String id;
  final String profileId;
  final String promptId;
  final int promptVersion;
  final DateTime startedAt;
  DateTime? completedAt;
  String status;
  String segmentsJson;
  String answerText;
  String feedbackJson;
  int totalDurationSeconds;
  bool usedHints;
  String revisionsJson;
  String? revisionDraft;
  int feedbackRevision;

  List<PictureStoryAnswerRevision> get revisions {
    final raw = jsonDecode(revisionsJson);
    if (raw is! List) throw const FormatException('表达历史暂时无法读取');
    return List.unmodifiable(
      raw.map((value) => PictureStoryAnswerRevision.fromJson(value)),
    );
  }

  PictureStoryPracticeRecord copy() => PictureStoryPracticeRecord(
    id: id,
    profileId: profileId,
    promptId: promptId,
    promptVersion: promptVersion,
    startedAt: startedAt,
    completedAt: completedAt,
    status: status,
    segmentsJson: segmentsJson,
    answerText: answerText,
    feedbackJson: feedbackJson,
    totalDurationSeconds: totalDurationSeconds,
    usedHints: usedHints,
    revisionsJson: revisionsJson,
    revisionDraft: revisionDraft,
    feedbackRevision: feedbackRevision,
  );

  List<PictureStorySegment> get segments {
    try {
      final raw = jsonDecode(segmentsJson);
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(PictureStorySegment.fromJson)
          .toList()
        ..sort((a, b) => a.position.compareTo(b.position));
    } on Object {
      return const [];
    }
  }

  void setSegments(Iterable<PictureStorySegment> value) {
    final ordered = value.toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    segmentsJson = jsonEncode(
      ordered.map((segment) => segment.toJson()).toList(),
    );
    answerText = ordered
        .map((segment) => segment.answerText.trim())
        .where((text) => text.isNotEmpty)
        .join('\n');
    totalDurationSeconds = ordered.fold<int>(
      0,
      (total, segment) => total + segment.durationSeconds,
    );
  }
}

final class PictureStoryPracticeRecordAdapter
    extends TypeAdapter<PictureStoryPracticeRecord> {
  @override
  final int typeId = 21;

  @override
  PictureStoryPracticeRecord read(BinaryReader reader) {
    final fieldCount = reader.readByte();
    final fields = <int, Object?>{
      for (var i = 0; i < fieldCount; i++) reader.readByte(): reader.read(),
    };
    return PictureStoryPracticeRecord(
      id: fields[0] as String,
      profileId: fields[1] as String,
      promptId: fields[2] as String,
      promptVersion: fields[3] as int,
      startedAt: fields[4] as DateTime,
      completedAt: fields[5] as DateTime?,
      status: fields[6] as String,
      segmentsJson: fields[7] as String,
      answerText: fields[8] as String? ?? '',
      feedbackJson: fields[9] as String? ?? '',
      totalDurationSeconds: fields[10] as int? ?? 0,
      usedHints: fields[11] as bool? ?? false,
      revisionsJson: fields[12] as String? ?? '[]',
      revisionDraft: fields[13] as String?,
      feedbackRevision: fields[14] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, PictureStoryPracticeRecord obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.profileId)
      ..writeByte(2)
      ..write(obj.promptId)
      ..writeByte(3)
      ..write(obj.promptVersion)
      ..writeByte(4)
      ..write(obj.startedAt)
      ..writeByte(5)
      ..write(obj.completedAt)
      ..writeByte(6)
      ..write(obj.status)
      ..writeByte(7)
      ..write(obj.segmentsJson)
      ..writeByte(8)
      ..write(obj.answerText)
      ..writeByte(9)
      ..write(obj.feedbackJson)
      ..writeByte(10)
      ..write(obj.totalDurationSeconds)
      ..writeByte(11)
      ..write(obj.usedHints)
      ..writeByte(12)
      ..write(obj.revisionsJson)
      ..writeByte(13)
      ..write(obj.revisionDraft)
      ..writeByte(14)
      ..write(obj.feedbackRevision);
  }
}

class PictureStoryAnswerRevision {
  const PictureStoryAnswerRevision({
    required this.answer,
    required this.feedbackJson,
    required this.createdAt,
  });
  final String answer;
  final String feedbackJson;
  final DateTime createdAt;
  Map<String, String> toJson() => {
    'answer': answer,
    'feedbackJson': feedbackJson,
    'createdAt': createdAt.toIso8601String(),
  };
  factory PictureStoryAnswerRevision.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['answer'] is! String ||
        value['feedbackJson'] is! String ||
        value['createdAt'] is! String) {
      throw const FormatException('表达历史暂时无法读取');
    }
    return PictureStoryAnswerRevision(
      answer: value['answer'] as String,
      feedbackJson: value['feedbackJson'] as String,
      createdAt: DateTime.parse(value['createdAt'] as String),
    );
  }
}
