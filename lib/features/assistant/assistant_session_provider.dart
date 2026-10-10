// lib/features/assistant/assistant_session_provider.dart
//
// 层级：features/assistant
// 职责：会话衔接层（design §3 方案 B）。把子任务 1 的纯内存对话控制器
//       （AssistantChatController）与子任务 2 的持久化仓储
//       （ConversationRepository）接通：
//         - 持当前 conversationId，供 AppBar 标题 / 抽屉读取；
//         - 监听控制器消息列表的增减，增量落库 / 删除（镜像到 repo）；
//         - 进入页面 / 新建 / 切换 / 删除会话时协调控制器与 repo。
//
// 持久化纪律：以 _persistedIds 平行追踪「已落库消息」与控制器 messages
//       前缀的一一对应（当前所有变更均为「尾部追加」或「从尾部截断」，
//       故按长度 diff 即可，见 send/finalize/stop/regenerate）。
//       载入 / 新建会话整列替换，经 _suspend 跳过 diff 并手工重置 _persistedIds。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/assistant_message.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/assistant_conversation_repository.dart';
import 'package:poemath/features/assistant/assistant_chat_controller.dart';
import 'package:poemath/features/assistant/assistant_chat_state.dart';

/// 持久化 [Message] → 内核 [ChatMessage] 映射（载入历史会话用）。
ChatMessage chatMessageFromMessage(Message m) => ChatMessage(
      role: switch (m.role) {
        MessageRole.user => ChatRole.user,
        MessageRole.assistant => ChatRole.assistant,
        MessageRole.tool => ChatRole.tool,
      },
      content: m.content,
      toolCallId: m.toolCallId,
      name: m.toolName,
    );

/// 内核 [ChatMessage] → 持久化 [MessageRole] 映射。
///
/// system 轮次不入库（运行时组装），控制器 messages 亦绝不含 system；
/// 此处防御性归并为 user（实际不可达）。
MessageRole _roleFromChatRole(ChatRole role) => switch (role) {
      ChatRole.user => MessageRole.user,
      ChatRole.assistant => MessageRole.assistant,
      ChatRole.tool => MessageRole.tool,
      ChatRole.system => MessageRole.user,
    };

/// 会话衔接状态：当前会话 id + 修订号（repo 变更后自增以驱动 UI 重建）。
///
/// repo（Hive）本身非响应式，标题自动生成 / 重命名 / 新建 / 删除均只改 repo，
/// 故用 [revision] 作为「repo 已变更」的信号，让监听本 provider 的 AppBar
/// 标题与会话抽屉重新读取 repo。
class AssistantSessionState {
  const AssistantSessionState({this.conversationId, this.revision = 0});

  /// 当前会话 id（null 表示尚未打开任何会话）。
  final String? conversationId;

  /// 修订号：任一 repo 变更后自增。
  final int revision;

  AssistantSessionState copyWith({String? conversationId, int? revision}) =>
      AssistantSessionState(
        conversationId: conversationId ?? this.conversationId,
        revision: revision ?? this.revision,
      );
}

class AssistantSessionController extends Notifier<AssistantSessionState> {
  late final ConversationRepository _repo;
  late final AssistantChatController _chat;

  /// 已落库消息的 id，顺序对应控制器 messages 的前缀。
  List<String> _persistedIds = <String>[];

  /// 载入 / 新建会话期间置真：跳过 diff 落库（整列替换非尾部增减）。
  bool _suspend = false;

  /// 串行化 repo 写入，保序并集中捕获异常；完成后自增 revision 刷新 UI。
  Future<void> _writeChain = Future<void>.value();

  /// 生成消息 id 的单调序号（同一微秒多条不冲突）。
  static int _seq = 0;

  @override
  AssistantSessionState build() {
    _repo = ref.read(conversationRepositoryProvider);
    _chat = ref.read(assistantChatControllerProvider.notifier);
    // 监听控制器消息列表增减，增量镜像到 repo。
    ref.listen<AssistantChatState>(
      assistantChatControllerProvider,
      (prev, next) => _syncMessages(next),
    );
    return const AssistantSessionState();
  }

  /// 控制器消息变更 → 增量落库（尾部追加）/ 删除（从尾部截断）。
  void _syncMessages(AssistantChatState next) {
    if (_suspend) return;
    final convId = state.conversationId;
    if (convId == null) return;
    final msgs = next.messages;

    // 从尾部截断（regenerate 删末条 assistant）：删除多出的已落库 id。
    final toDelete = <String>[];
    while (_persistedIds.length > msgs.length) {
      toDelete.add(_persistedIds.removeLast());
    }
    // 尾部追加（send 的 user / finalize|stop 的 assistant）：落库新消息。
    final toAppend = <Message>[];
    for (var i = _persistedIds.length; i < msgs.length; i++) {
      final m = _buildMessage(msgs[i], convId);
      _persistedIds.add(m.id);
      toAppend.add(m);
    }
    if (toDelete.isEmpty && toAppend.isEmpty) return;
    _enqueue(() async {
      for (final id in toDelete) {
        await _repo.deleteMessage(id);
      }
      for (final m in toAppend) {
        await _repo.appendMessage(m);
      }
    });
  }

  /// 把 repo 写入排到串行链尾，完成后刷新 revision。
  void _enqueue(Future<void> Function() op) {
    _writeChain = _writeChain.then((_) => op()).then((_) => _bumpRevision());
  }

  void _bumpRevision() {
    state = state.copyWith(revision: state.revision + 1);
  }

  Message _buildMessage(ChatMessage c, String conversationId) {
    final now = DateTime.now();
    return Message(
      id: '${now.microsecondsSinceEpoch}_${_seq++}',
      conversationId: conversationId,
      profileId: ProfileScope.currentId,
      role: _roleFromChatRole(c.role),
      content: c.content,
      createdAt: now,
      toolName: c.name,
      toolCallId: c.toolCallId,
    );
  }

  // PLACEHOLDER_OPS

  /// 进入页面：已打开且仍存在则保持；否则打开最近一条会话，无则新建。
  Future<void> ensureOpen() async {
    final current = state.conversationId;
    if (current != null && _repo.getById(current) != null) return;
    final all = _repo.getAll(); // updatedAt 倒序
    if (all.isNotEmpty) {
      await _open(all.first.id);
    } else {
      await startNew();
    }
  }

  /// 载入目标会话：读 repo 消息 → 注入控制器（丢弃在途流），重置 _persistedIds。
  Future<void> _open(String id) async {
    final models = _repo.messagesOf(id); // createdAt 升序
    _persistedIds = models.map((m) => m.id).toList();
    _suspend = true;
    _chat.loadConversation(models.map(chatMessageFromMessage).toList());
    _suspend = false;
    state = state.copyWith(conversationId: id, revision: state.revision + 1);
  }

  /// 新建空会话并设为当前。
  Future<void> startNew() async {
    final c = await _repo.create();
    _persistedIds = <String>[];
    _suspend = true;
    _chat.startNewConversation();
    _suspend = false;
    state = state.copyWith(conversationId: c.id, revision: state.revision + 1);
  }

  /// 切换到指定会话。
  Future<void> switchTo(String id) async {
    if (id == state.conversationId) return;
    await _open(id);
  }

  /// 发送用户消息：由控制器驱动流式回答，持久化经 _syncMessages 自动完成。
  Future<void> send(String text) => _chat.send(text);

  /// 重新生成：删末条 assistant（内存+repo 经 _syncMessages）后以末条 user 重跑。
  Future<void> regenerate() => _chat.regenerate();

  /// 停止在途流（固化部分内容为 assistant 并落库）。
  void stop() => _chat.stop();

  /// 重命名会话（不改 updatedAt / 不改排序）。
  Future<void> rename(String id, String title) async {
    await _repo.rename(id, title);
    _bumpRevision();
  }

  /// 删除会话；若删的是当前会话，自动切到最近一条或新建。
  Future<void> delete(String id) async {
    await _repo.delete(id);
    if (state.conversationId == id) {
      _persistedIds = <String>[];
      final all = _repo.getAll();
      if (all.isNotEmpty) {
        await _open(all.first.id);
      } else {
        await startNew();
      }
    } else {
      _bumpRevision();
    }
  }

  /// 页面销毁：仅丢弃控制器在途流的晚到回调，不写状态。
  void discardPending() => _chat.discardPending();
}

/// 会话衔接 provider（App 生命周期内常驻，跨页面导航保留当前会话）。
final assistantSessionProvider =
    NotifierProvider<AssistantSessionController, AssistantSessionState>(
  AssistantSessionController.new,
);

