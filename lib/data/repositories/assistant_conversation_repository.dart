// lib/data/repositories/assistant_conversation_repository.dart
//
// 层级：data/repositories
// 职责：AI 助手会话仓储。Profile-scoped。
//       会话（conversations box）与消息（messages box）分离存储：
//       追加消息 = 单条 put，读取会话消息 = 按 conversationId 过滤，
//       避免大会话整体序列化重写（见 design §1）。
//       删除会话时级联清理其 messages（见 design §4.2）。

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/assistant_conversation.dart';
import 'package:poemath/data/models/assistant_message.dart';

class ConversationRepository {
  /// 新会话默认标题（首条 user 消息后被 _titleFrom 覆盖）。
  static const String _defaultTitle = '新对话';

  /// 自动标题最大字数（超出截断加「…」）。
  static const int _titleMaxLen = 16;

  /// 单调递增序号，保证同一微秒内多次 create 的 ID 不冲突。
  static int _seq = 0;

  /// 当前 profile 的全部会话（按 updatedAt 倒序）。
  List<Conversation> getAll() {
    return HiveBoxes.conversations.values
        .where((c) => c.profileId == ProfileScope.currentId)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// 按 ID 获取会话。
  Conversation? getById(String id) {
    return HiveBoxes.conversations.get(ProfileScope.key(id));
  }

  /// 新建空标题会话并入库，返回该会话。
  Future<Conversation> create() async {
    final now = DateTime.now();
    final id = '${now.microsecondsSinceEpoch}_${_seq++}';
    final conversation = Conversation(
      id: id,
      profileId: ProfileScope.currentId,
      title: _defaultTitle,
      createdAt: now,
      updatedAt: now,
    );
    await HiveBoxes.conversations.put(ProfileScope.key(id), conversation);
    return conversation;
  }

  /// 重命名会话（用户覆盖自动标题）。空输入兜底默认标题。
  /// 不刷新 updatedAt：updatedAt 仅表征消息活跃度（见 design §2）。
  Future<void> rename(String id, String title) async {
    final conversation = getById(id);
    if (conversation == null) return;
    final trimmed = title.trim();
    conversation.title = trimmed.isEmpty ? _defaultTitle : trimmed;
    await conversation.save();
  }

  /// 删除会话并级联清理其全部消息。
  Future<void> delete(String id) async {
    final keys = HiveBoxes.messages.values
        .where(
          (m) =>
              m.conversationId == id &&
              m.profileId == ProfileScope.currentId,
        )
        .map((m) => ProfileScope.key(m.id))
        .toList();
    await HiveBoxes.messages.deleteAll(keys);
    await HiveBoxes.conversations.delete(ProfileScope.key(id));
  }

  /// 删除单条消息（重答时丢弃末尾 assistant，见 chat-ui design §4）。
  Future<void> deleteMessage(String id) async {
    await HiveBoxes.messages.delete(ProfileScope.key(id));
  }

  /// 某会话的全部消息（当前 profile，按 createdAt 升序）。
  List<Message> messagesOf(String conversationId) {
    return HiveBoxes.messages.values
        .where(
          (m) =>
              m.conversationId == conversationId &&
              m.profileId == ProfileScope.currentId,
        )
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// 追加一条消息：入库 + 刷新会话 updatedAt + 首条 user 自动标题。
  Future<void> appendMessage(Message message) async {
    // 自动标题仅在该会话此前无 user 消息时触发（须在 put 之前判断）。
    final isFirstUser = message.role == MessageRole.user &&
        messagesOf(message.conversationId)
            .where((m) => m.role == MessageRole.user)
            .isEmpty;

    await HiveBoxes.messages.put(ProfileScope.key(message.id), message);

    final conversation = getById(message.conversationId);
    if (conversation == null) return;
    conversation.updatedAt = DateTime.now();
    if (isFirstUser) {
      conversation.title = _titleFrom(message.content);
    }
    await conversation.save();
  }

  /// 本地标题规则：取首行、去空白、截断 ≤ 16 字、超出加「…」，
  /// 空输入兜底默认标题。不额外调用 LLM（降低成本与延迟）。
  String _titleFrom(String content) {
    final firstLine = content.split('\n').first.trim();
    if (firstLine.isEmpty) return _defaultTitle;
    if (firstLine.length <= _titleMaxLen) return firstLine;
    return '${firstLine.substring(0, _titleMaxLen)}…';
  }
}
