// lib/data/models/assistant_message.dart
//
// 层级：data/models
// 职责：AI 助手消息模型（Message typeId 18 / MessageRole typeId 19）。
//       Profile-scoped，经 conversationId 外键归属某会话。
//       system 角色不持久化（系统提示运行时组装，见子任务 1），
//       故 MessageRole 不含 system。

import 'package:hive/hive.dart';

part 'assistant_message.g.dart';

/// 持久化消息角色。与子任务 1 的 ChatRole 在控制器层做映射，
/// 持久层不依赖 client DTO。
@HiveType(typeId: 19)
enum MessageRole {
  @HiveField(0)
  user,

  @HiveField(1)
  assistant,

  /// 工具调用结果（预留子任务 5）。
  @HiveField(2)
  tool,
}

@HiveType(typeId: 18)
class Message extends HiveObject {
  /// 唯一 ID（毫秒时间戳 + 序号）。
  @HiveField(0)
  final String id;

  /// 所属会话 ID（外键）。
  @HiveField(1)
  final String conversationId;

  /// 所属 profile ID。
  @HiveField(2)
  final String profileId;

  /// 消息角色。
  @HiveField(3)
  final MessageRole role;

  /// 消息内容。流式结束后固化；stop 可固化为部分内容。
  @HiveField(4)
  String content;

  /// 创建时间（会话内按此升序排列）。
  @HiveField(5)
  final DateTime createdAt;

  /// 工具名（预留子任务 5）。
  @HiveField(6)
  final String? toolName;

  /// 工具调用 ID（预留子任务 5）。
  @HiveField(7)
  final String? toolCallId;

  Message({
    required this.id,
    required this.conversationId,
    required this.profileId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.toolName,
    this.toolCallId,
  });
}
