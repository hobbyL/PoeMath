// test/features/assistant/assistant_session_provider_test.dart
//
// 会话衔接层（AssistantSessionController）测试：进入 / 新建 / 切换 /
// 重命名 / 删除会话的协调，以及消息镜像落库（增量 diff）。
// 用真实 repo + 临时目录 Hive；对话控制器用脚本假实现（send/regenerate
// 同步改状态以驱动 ref.listen 落库），规避网络。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/assistant_message.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/assistant_conversation_repository.dart';
import 'package:poemath/features/assistant/assistant_chat_controller.dart';
import 'package:poemath/features/assistant/assistant_chat_state.dart';
import 'package:poemath/features/assistant/assistant_session_provider.dart';

import '../../helpers/hive_test_helper.dart';

/// 脚本化假控制器：send 一次追加 user+assistant；regenerate 分两步
/// （先截断末条 assistant，再追加新 assistant），与真实控制器的状态轨迹
/// 一致，使 session 的长度 diff（尾部追加 / 从尾部截断）被正确触发。
class _ScriptedChat extends AssistantChatController {
  @override
  AssistantChatState build() => const AssistantChatState();

  @override
  Future<void> send(String userInput) async {
    final text = userInput.trim();
    if (text.isEmpty) return;
    state = AssistantChatState(
      status: AssistantChatStatus.ready,
      messages: <ChatMessage>[
        ...state.messages,
        ChatMessage(role: ChatRole.user, content: text),
        ChatMessage(role: ChatRole.assistant, content: '回答：$text'),
      ],
    );
  }

  @override
  Future<void> regenerate() async {
    final msgs = state.messages;
    final lastUser = msgs.lastIndexWhere((m) => m.role == ChatRole.user);
    if (lastUser < 0) return;
    final kept = msgs.sublist(0, lastUser + 1);
    // 两步轨迹：先从尾部截断旧 assistant（触发删除 diff），再追加新
    // assistant（触发追加 diff）—— 与真实控制器一致。
    state = AssistantChatState(
      status: AssistantChatStatus.loading,
      messages: List<ChatMessage>.unmodifiable(kept),
    );
    state = AssistantChatState(
      status: AssistantChatStatus.ready,
      messages: <ChatMessage>[
        ...kept,
        const ChatMessage(role: ChatRole.assistant, content: '重答'),
      ],
    );
  }

  @override
  void stop() {}

  @override
  void loadConversation(List<ChatMessage> messages) {
    state = AssistantChatState(
      status: messages.isEmpty
          ? AssistantChatStatus.idle
          : AssistantChatStatus.ready,
      messages: List<ChatMessage>.unmodifiable(messages),
    );
  }

  @override
  void startNewConversation() {
    state = const AssistantChatState();
  }

  @override
  void discardPending() {}
}

/// 构造持久化消息（profileId 默认当前 profile，createdAt 可控以定序）。
Message _msg({
  required String id,
  required String conversationId,
  required MessageRole role,
  required String content,
  DateTime? createdAt,
  String? toolName,
  String? toolCallId,
}) =>
    Message(
      id: id,
      conversationId: conversationId,
      profileId: ProfileScope.currentId,
      role: role,
      content: content,
      createdAt: createdAt ?? DateTime(2026, 10, 1),
      toolName: toolName,
      toolCallId: toolCallId,
    );

void main() {
  late ProviderContainer container;

  setUp(() async {
    await setUpHiveForTesting();
    container = ProviderContainer(
      overrides: <Override>[
        assistantChatControllerProvider.overrideWith(_ScriptedChat.new),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    ProfileScope.reset();
    await tearDownHiveForTesting();
  });

  AssistantSessionController session() =>
      container.read(assistantSessionProvider.notifier);
  AssistantSessionState sessionState() =>
      container.read(assistantSessionProvider);
  ConversationRepository repo() =>
      container.read(conversationRepositoryProvider);
  List<ChatMessage> chatMessages() =>
      container.read(assistantChatControllerProvider).messages;

  /// 排空 session 的串行写链（repo 写入为异步微任务 / 文件 IO）。
  Future<void> settle() async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  test('ensureOpen 空库：自动新建并打开会话', () async {
    await session().ensureOpen();

    final id = sessionState().conversationId;
    expect(id, isNotNull);
    expect(repo().getById(id!), isNotNull);
    expect(repo().getAll().length, 1);
  });

  test('ensureOpen 有历史：打开最近会话并载入其消息（升序）', () async {
    final c = await repo().create();
    await repo().appendMessage(_msg(
      id: 'm1',
      conversationId: c.id,
      role: MessageRole.user,
      content: '你好',
      createdAt: DateTime(2026, 10, 1, 9, 0, 0),
    ),);
    await repo().appendMessage(_msg(
      id: 'm2',
      conversationId: c.id,
      role: MessageRole.assistant,
      content: '你也好',
      createdAt: DateTime(2026, 10, 1, 9, 0, 1),
    ),);

    await session().ensureOpen();

    expect(sessionState().conversationId, c.id);
    expect(
      chatMessages().map((m) => m.content).toList(),
      <String>['你好', '你也好'],
    );
  });

  test('startNew：新建空会话并设为当前，控制器清空', () async {
    await session().send('临时'); // 产生一些内存消息（当前会话为空、不落库）
    await session().startNew();

    expect(sessionState().conversationId, isNotNull);
    expect(chatMessages(), isEmpty);
  });

  test('switchTo：切换到另一会话并载入其消息', () async {
    final a = await repo().create();
    await repo().appendMessage(_msg(
      id: 'a1',
      conversationId: a.id,
      role: MessageRole.user,
      content: 'A 的问题',
      createdAt: DateTime(2026, 10, 1, 8, 0, 0),
    ),);
    final b = await repo().create();
    await repo().appendMessage(_msg(
      id: 'b1',
      conversationId: b.id,
      role: MessageRole.user,
      content: 'B 的问题',
      createdAt: DateTime(2026, 10, 1, 8, 5, 0),
    ),);
    // 显式定序 updatedAt：B 更晚活跃 → getAll 首位为 B（规避时钟分辨率抖动）。
    final ca = repo().getById(a.id)!;
    ca.updatedAt = DateTime(2026, 10, 1, 8, 0);
    await ca.save();
    final cb = repo().getById(b.id)!;
    cb.updatedAt = DateTime(2026, 10, 1, 9, 0);
    await cb.save();

    await session().ensureOpen(); // 打开最近 = B
    expect(sessionState().conversationId, b.id);

    await session().switchTo(a.id);
    expect(sessionState().conversationId, a.id);
    expect(
      chatMessages().map((m) => m.content).toList(),
      <String>['A 的问题'],
    );
  });

  test('rename：改标题并自增 revision', () async {
    await session().startNew();
    final id = sessionState().conversationId!;
    final before = sessionState().revision;

    await session().rename(id, '我的数学问题');

    expect(repo().getById(id)?.title, '我的数学问题');
    expect(sessionState().revision, greaterThan(before));
  });

  test('delete 非当前会话：仅删目标，当前会话不变', () async {
    final other = await repo().create();
    await session().startNew();
    final currentId = sessionState().conversationId!;

    await session().delete(other.id);

    expect(repo().getById(other.id), isNull);
    expect(sessionState().conversationId, currentId);
    expect(repo().getById(currentId), isNotNull);
  });

  test('delete 当前会话：自动切到剩余最近一条', () async {
    final keep = await repo().create();
    await session().startNew(); // 当前 = 新会话
    final currentId = sessionState().conversationId!;

    await session().delete(currentId);

    expect(repo().getById(currentId), isNull);
    expect(sessionState().conversationId, keep.id);
  });

  test('delete 唯一会话：自动新建空会话（新 id 不等于旧 id）', () async {
    await session().startNew();
    final oldId = sessionState().conversationId!;

    await session().delete(oldId);

    final newId = sessionState().conversationId;
    expect(newId, isNotNull);
    expect(newId, isNot(oldId));
    expect(repo().getById(oldId), isNull);
    expect(repo().getById(newId!), isNotNull);
  });

  test('send：用户与助手消息镜像落库', () async {
    await session().startNew();
    final id = sessionState().conversationId!;

    await session().send('出一道题');
    await settle();

    // Set 规避同微秒 createdAt 的定序抖动。
    expect(
      repo().messagesOf(id).map((m) => m.content).toSet(),
      <String>{'出一道题', '回答：出一道题'},
    );
    expect(repo().messagesOf(id).length, 2);
  });

  test('regenerate：删除旧回答并镜像新回答（长度不变、内容替换）', () async {
    await session().startNew();
    final id = sessionState().conversationId!;

    await session().send('出一道题');
    await settle();

    await session().regenerate();
    await settle();

    expect(
      repo().messagesOf(id).map((m) => m.content).toSet(),
      <String>{'出一道题', '重答'},
    );
    expect(repo().messagesOf(id).length, 2);
  });

  test('载入含工具轮次会话：assistant 轮次按后续 role:tool 重建 tool_calls',
      () async {
    final c = await repo().create();
    await repo().appendMessage(_msg(
      id: 'u1',
      conversationId: c.id,
      role: MessageRole.user,
      content: '讲讲我的错题',
      createdAt: DateTime(2026, 10, 1, 9, 0, 0),
    ),);
    // assistant 发起工具调用的轮次：持久层未落 tool_calls（content 为空）。
    await repo().appendMessage(_msg(
      id: 'a1',
      conversationId: c.id,
      role: MessageRole.assistant,
      content: '',
      createdAt: DateTime(2026, 10, 1, 9, 0, 1),
    ),);
    // 工具结果回灌：toolCallId/toolName 已落库（field 6/7）。
    await repo().appendMessage(_msg(
      id: 't1',
      conversationId: c.id,
      role: MessageRole.tool,
      content: '题目：25 + 38 = ?',
      createdAt: DateTime(2026, 10, 1, 9, 0, 2),
      toolName: 'explain_mistake',
      toolCallId: 'call_1',
    ),);

    await session().ensureOpen();

    final msgs = chatMessages();
    // 长度不变（原地重建，_persistedIds 对齐）。
    expect(msgs, hasLength(3));
    // assistant 轮次重建出 tool_calls，指向后续 role:tool。
    final assistant = msgs[1];
    expect(assistant.role, ChatRole.assistant);
    expect(assistant.toolCalls, hasLength(1));
    expect(assistant.toolCalls!.single.id, 'call_1');
    expect(assistant.toolCalls!.single.name, 'explain_mistake');
    // 工具结果轮次保留 toolCallId/name。
    expect(msgs[2].role, ChatRole.tool);
    expect(msgs[2].toolCallId, 'call_1');
    expect(msgs[2].name, 'explain_mistake');
  });

  test('写入失败不毒化串行链：后续消息仍能落库，revision 只随成功写入自增', () async {
    final flakyRepo = _FlakyAppendRepository(failUntilCall: 1);
    final flakyContainer = ProviderContainer(
      overrides: <Override>[
        assistantChatControllerProvider.overrideWith(_ScriptedChat.new),
        conversationRepositoryProvider.overrideWithValue(flakyRepo),
      ],
    );
    addTearDown(flakyContainer.dispose);

    final flakySession =
        flakyContainer.read(assistantSessionProvider.notifier);
    await flakySession.startNew();
    final id = flakyContainer.read(assistantSessionProvider).conversationId!;
    final revisionAfterOpen =
        flakyContainer.read(assistantSessionProvider).revision;

    // 第一批（user + assistant）：首个 appendMessage 抛异常，整批失败。
    // 裸 Future 链的旧实现会就此进入错误态并粘连，后续写入全被跳过；
    // 且此处若无 onError，未捕获的异步异常会直接把本测试判红。
    await flakySession.send('第一条');
    await settle();

    expect(flakyRepo.appendCalls, 1, reason: '首次调用抛异常后整批中止');
    expect(flakyRepo.persisted, isEmpty);
    expect(
      flakyContainer.read(assistantSessionProvider).revision,
      revisionAfterOpen,
      reason: '写入失败不得自增 revision（语义是「repo 确已变更」）',
    );

    // 第二批：链条已自愈，正常落库。
    await flakySession.send('第二条');
    await settle();

    expect(
      flakyRepo.persisted.map((m) => m.content).toSet(),
      <String>{'第二条', '回答：第二条'},
      reason: '一次失败后链条必须自愈，后续写入照常生效',
    );
    expect(
      flakyRepo.messagesOf(id).map((m) => m.content).toSet(),
      <String>{'第二条', '回答：第二条'},
    );
    expect(
      flakyContainer.read(assistantSessionProvider).revision,
      greaterThan(revisionAfterOpen),
    );
  });
}

/// 前 [failUntilCall] 次 `appendMessage` 抛异常，之后正常落库。
/// 用于验证单次写入失败不会毒化 session 的串行写链。
class _FlakyAppendRepository extends ConversationRepository {
  _FlakyAppendRepository({required this.failUntilCall});

  final int failUntilCall;
  int appendCalls = 0;
  final List<Message> persisted = <Message>[];

  @override
  Future<void> appendMessage(Message message) async {
    appendCalls++;
    if (appendCalls <= failUntilCall) {
      throw StateError('append failed #$appendCalls');
    }
    persisted.add(message);
    await super.appendMessage(message);
  }
}
