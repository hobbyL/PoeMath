// lib/data/models/assistant_conversation.dart
//
// 层级：data/models
// 职责：AI 助手会话模型（typeId 17）。Profile-scoped。
//       会话与消息分 box 存储，消息经 conversationId 外键关联
//       （见 assistant_message.dart），避免大会话整体读写。

import 'package:hive/hive.dart';

part 'assistant_conversation.g.dart';

@HiveType(typeId: 17)
class Conversation extends HiveObject {
  /// 唯一 ID（毫秒时间戳 + 序号）。
  @HiveField(0)
  final String id;

  /// 所属 profile ID。
  @HiveField(1)
  final String profileId;

  /// 会话标题。首条 user 消息后本地自动生成，可被用户重命名。
  @HiveField(2)
  String title;

  /// 创建时间。
  @HiveField(3)
  final DateTime createdAt;

  /// 最近活跃时间（追加消息时刷新，用于会话列表倒序）。
  @HiveField(4)
  DateTime updatedAt;

  Conversation({
    required this.id,
    required this.profileId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });
}
