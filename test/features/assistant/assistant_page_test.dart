// test/features/assistant/assistant_page_test.dart
//
// AI 助手主页（AssistantPage）组件测试：
//   - 六态渲染：idle 空态 / loading 挂起气泡 / streaming 流式气泡 /
//     ready 气泡与操作按钮 / error 错误条 / unconfigured 未配置引导；
//   - 发送 / 停止 / 重答按钮显隐与回调接线；
//   - 含 LaTeX 的消息渲染不抛异常。
// 纯状态测试：覆写 assistantChatControllerProvider（固定状态 + 空操作）
//   与 assistantSessionProvider（conversationId=null，记录回调），不触碰 Hive。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/features/assistant/assistant_chat_controller.dart';
import 'package:poemath/features/assistant/assistant_chat_state.dart';
import 'package:poemath/features/assistant/assistant_page.dart';
import 'package:poemath/features/assistant/assistant_session_provider.dart';
import 'package:poemath/features/assistant/widgets/chat_input_bar.dart';
import 'package:poemath/features/assistant/widgets/chat_message_bubble.dart';

/// 固定状态的假对话控制器：build 返回目标状态，所有变更方法空操作，
/// 使注入状态在渲染期间保持不变（不触发真实 chatStream / 网络）。
class _FakeChat extends AssistantChatController {
  _FakeChat(this._state);

  final AssistantChatState _state;

  @override
  AssistantChatState build() => _state;

  @override
  Future<void> send(String userInput) async {}

  @override
  Future<void> regenerate() async {}

  @override
  void stop() {}

  @override
  void loadConversation(List<ChatMessage> messages) {}

  @override
  void startNewConversation() {}

  @override
  void discardPending() {}
}

/// 假会话衔接层：固定 conversationId=null（标题走「AI 助手」分支，不读
/// repo），记录 send/stop/regenerate/startNew 调用以验证页面接线。
class _FakeSession extends AssistantSessionController {
  _FakeSession(this._initial);

  final AssistantSessionState _initial;

  final List<String> sent = <String>[];
  int stopCount = 0;
  int regenerateCount = 0;
  int startNewCount = 0;

  @override
  AssistantSessionState build() => _initial;

  @override
  Future<void> ensureOpen() async {}

  @override
  Future<void> startNew() async {
    startNewCount++;
  }

  @override
  Future<void> send(String text) async {
    sent.add(text);
  }

  @override
  void stop() {
    stopCount++;
  }

  @override
  Future<void> regenerate() async {
    regenerateCount++;
  }

  @override
  void discardPending() {}
}

typedef _Harness = ({ProviderContainer container, _FakeSession session});

_Harness _harness(
  AssistantChatState chatState, {
  AssistantSessionState sessionState = const AssistantSessionState(),
}) {
  final session = _FakeSession(sessionState);
  final container = ProviderContainer(
    overrides: <Override>[
      assistantChatControllerProvider.overrideWith(() => _FakeChat(chatState)),
      assistantSessionProvider.overrideWith(() => session),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, session: session);
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AssistantPage()),
    ),
  );
}

/// 卸载页面以释放持续动画（loading 转圈 / streaming 淡入），再排空计时器，
/// 规避「A Timer is still pending」。
Future<void> _teardownAnim(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

ChatMessage _user(String content) =>
    ChatMessage(role: ChatRole.user, content: content);

ChatMessage _assistant(String content) =>
    ChatMessage(role: ChatRole.assistant, content: content);

void main() {
  testWidgets('idle 空会话：显示空态引导，无消息气泡', (tester) async {
    final h = _harness(const AssistantChatState());
    await _pump(tester, h.container);
    await tester.pumpAndSettle();

    expect(find.text('你好，我是 AI 学习助手'), findsOneWidget);
    expect(find.byType(ChatMessageBubble), findsNothing);
    expect(find.byType(ChatInputBar), findsOneWidget);
    // 空输入 → 发送按钮在、停止按钮不在。
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsNothing);
  });

  testWidgets('ready：末条 assistant 显示复制 + 重答，输入栏为发送态',
      (tester) async {
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.ready,
        messages: <ChatMessage>[_user('1+1'), _assistant('等于 2')],
      ),
    );
    await _pump(tester, h.container);
    await tester.pumpAndSettle();

    expect(find.byType(ChatMessageBubble), findsNWidgets(2));
    expect(find.byTooltip('复制'), findsOneWidget);
    expect(find.byTooltip('重新生成'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsNothing);
  });

  testWidgets('loading：显示「思考中…」挂起气泡，输入栏为停止态', (tester) async {
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.loading,
        messages: <ChatMessage>[_user('出一道题')],
      ),
    );
    await _pump(tester, h.container);
    await tester.pump(); // 不可 pumpAndSettle：转圈动画永不停止。

    expect(find.text('思考中…'), findsOneWidget);
    expect(find.byType(ChatMessageBubble), findsOneWidget); // 仅 user
    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);

    await _teardownAnim(tester);
  });

  testWidgets('streaming：流式气泡无操作按钮，输入栏为停止态', (tester) async {
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.streaming,
        messages: <ChatMessage>[_user('讲讲乘法')],
        streamingText: '乘法是……',
      ),
    );
    await _pump(tester, h.container);
    await tester.pump(const Duration(milliseconds: 600)); // 推进淡入

    expect(find.byType(ChatMessageBubble), findsNWidgets(2)); // user + 流式
    expect(find.byTooltip('复制'), findsNothing); // 流式气泡不出操作
    expect(find.byTooltip('重新生成'), findsNothing);
    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);

    await _teardownAnim(tester);
  });

  testWidgets('error：显示错误条与「重试」，消息仍渲染', (tester) async {
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.error,
        messages: <ChatMessage>[_user('出一道题')],
        message: '网络开小差了',
      ),
    );
    await _pump(tester, h.container);
    await tester.pumpAndSettle();

    expect(find.text('网络开小差了'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.byType(ChatMessageBubble), findsOneWidget);
    expect(find.byType(ChatInputBar), findsOneWidget);
  });

  testWidgets('unconfigured：显示未配置引导与「去配置」，无输入栏', (tester) async {
    final h = _harness(
      const AssistantChatState(
        status: AssistantChatStatus.unconfigured,
        message: '还没有配置 AI 服务，配置后即可使用 AI 助手。',
      ),
    );
    await _pump(tester, h.container);
    await tester.pumpAndSettle();

    expect(find.text('尚未配置 AI 服务'), findsOneWidget);
    expect(find.text('去配置'), findsOneWidget);
    expect(find.byType(ChatInputBar), findsNothing);
    expect(find.byType(ChatMessageBubble), findsNothing);
  });

  testWidgets('渲染含 LaTeX 的 assistant 消息不抛异常（ready）', (tester) async {
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.ready,
        messages: <ChatMessage>[
          _user('二分之一怎么写'),
          _assistant(r'结果是 $\frac{1}{2}$ 哦'),
        ],
      ),
    );
    await _pump(tester, h.container);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ChatMessageBubble), findsNWidgets(2));
  });

  testWidgets('渲染含 LaTeX 的流式文本不抛异常（streaming + 淡入）',
      (tester) async {
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.streaming,
        messages: <ChatMessage>[_user('写个公式')],
        streamingText: r'$\frac{1}{2}$',
      ),
    );
    await _pump(tester, h.container);
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);

    await _teardownAnim(tester);
  });

  testWidgets('点击「重新生成」转接 session.regenerate', (tester) async {
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.ready,
        messages: <ChatMessage>[_user('1+1'), _assistant('等于 2')],
      ),
    );
    await _pump(tester, h.container);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('重新生成'));
    await tester.pumpAndSettle();

    expect(h.session.regenerateCount, 1);
  });

  testWidgets('点击「停止」转接 session.stop', (tester) async {
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.streaming,
        messages: <ChatMessage>[_user('讲讲乘法')],
        streamingText: '乘法是……',
      ),
    );
    await _pump(tester, h.container);
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();

    expect(h.session.stopCount, 1);

    await _teardownAnim(tester);
  });

  testWidgets('点击错误条「重试」转接 session.regenerate', (tester) async {
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.error,
        messages: <ChatMessage>[_user('出一道题')],
        message: '网络开小差了',
      ),
    );
    await _pump(tester, h.container);
    await tester.pumpAndSettle();

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(h.session.regenerateCount, 1);
  });
}





