// test/features/assistant/assistant_page_test.dart
//
// AI 助手主页（AssistantPage）组件测试：
//   - 六态渲染：idle 空态 / loading 挂起气泡 / streaming 流式气泡 /
//     ready 气泡与操作按钮 / error 错误条 / unconfigured 未配置引导；
//   - 发送 / 停止 / 重答按钮显隐与回调接线；
//   - 含 LaTeX 的消息渲染不抛异常。
// 纯状态测试：覆写 assistantChatControllerProvider（固定状态 + 空操作）
//   与 assistantSessionProvider（conversationId=null，记录回调），不触碰 Hive。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/llm/chat_completion.dart';
import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/assistant/assistant_chat_controller.dart';
import 'package:poemath/features/assistant/assistant_chat_state.dart';
import 'package:poemath/features/assistant/assistant_page.dart';
import 'package:poemath/features/assistant/assistant_session_provider.dart';
import 'package:poemath/features/assistant/widgets/chat_input_bar.dart';
import 'package:poemath/features/assistant/widgets/chat_message_bubble.dart';
import 'package:poemath/features/assistant/widgets/tool_message_card.dart';

import '../../helpers/hive_test_helper.dart';

class _MockTtsService extends Mock implements TtsService {}

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
  final List<int> resentIndexes = <int>[];

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
  Future<void> resendFrom(int index) async {
    resentIndexes.add(index);
  }

  @override
  void discardPending() {}
}

typedef _Harness = ({
  ProviderContainer container,
  _FakeSession session,
  _FakeChat chat,
  _MockTtsService tts,
});

_Harness _harness(
  AssistantChatState chatState, {
  AssistantSessionState sessionState = const AssistantSessionState(),
}) {
  final chat = _FakeChat(chatState);
  final session = _FakeSession(sessionState);
  final tts = _MockTtsService();
  // 默认桩：页面 dispose / 停止路径都会调 stop；currentSessionId 兜底 0。
  // 朗读行为由各测试按需经 _stubSpeakSentences 覆写。
  when(() => tts.stop()).thenAnswer((_) async {});
  when(() => tts.currentSessionId).thenReturn(0);
  final container = ProviderContainer(
    overrides: <Override>[
      assistantChatControllerProvider.overrideWith(() => chat),
      assistantSessionProvider.overrideWith(() => session),
      ttsServiceProvider.overrideWithValue(tts),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, session: session, chat: chat, tts: tts);
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

/// 会话身份模拟器：复刻 TtsService 的会话代际令牌语义——朗读入口同步段
/// 递增，回调携带该 id，`currentSessionId` 返回最新值。恒返回常量会让
/// 过期会话的晚到回调被误判为当前会话（假绿），mock 须与真服务同构。
class _SessionIds {
  int _current = 0;

  int get current => _current;

  int next() => ++_current;
}

/// 一次可控朗读：合成期挂起 → [signalReady] 触发 onReady（遮罩解除）→
/// 朗读期挂起 → [signalFinish] 完成朗读 Future（页面回空闲）。
class _SpeakHandle {
  _SpeakHandle({
    required this.sessionId,
    required this.text,
    required this.onReady,
    required Completer<void> completer,
  }) : _completer = completer;

  final int sessionId;
  final String text;
  final void Function(int sessionId)? onReady;
  final Completer<void> _completer;

  void signalReady() => onReady?.call(sessionId);

  void signalFinish() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// 覆写 speakSentences 为可控脚本，返回按发生顺序累积的朗读记录。
List<_SpeakHandle> _stubSpeakSentences(_MockTtsService tts) {
  final handles = <_SpeakHandle>[];
  final sessions = _SessionIds();
  when(() => tts.currentSessionId).thenAnswer((_) => sessions.current);
  when(
    () => tts.speakSentences(any(), onReady: any(named: 'onReady')),
  ).thenAnswer((invocation) {
    final sessionId = sessions.next();
    final onReady =
        invocation.namedArguments[#onReady] as void Function(int)?;
    final completer = Completer<void>();
    handles.add(
      _SpeakHandle(
        sessionId: sessionId,
        text: invocation.positionalArguments[0] as String,
        onReady: onReady,
        completer: completer,
      ),
    );
    return completer.future;
  });
  return handles;
}

ChatMessage _user(String content) =>
    ChatMessage(role: ChatRole.user, content: content);

ChatMessage _assistant(String content) =>
    ChatMessage(role: ChatRole.assistant, content: content);

void main() {
  // AppBar 的 AssistantProviderSwitcher 读 settingsRepositoryProvider →
  // HiveBoxes.settings，需初始化 Hive（否则 LateInitializationError）。
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

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

  testWidgets('清除上下文后：消息列表在清除点出现分割线', (tester) async {
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.ready,
        messages: <ChatMessage>[
          _user('旧问'),
          _assistant('旧答'),
          _user('新问'),
          _assistant('新答'),
        ],
        contextBaseIndex: 2,
      ),
    );
    await _pump(tester, h.container);
    await tester.pumpAndSettle();

    expect(find.text('上下文已清除'), findsOneWidget);
  });

  testWidgets('未清除上下文（contextBaseIndex=0）：不显示分割线', (tester) async {
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.ready,
        messages: <ChatMessage>[_user('问'), _assistant('答')],
      ),
    );
    await _pump(tester, h.container);
    await tester.pumpAndSettle();

    expect(find.text('上下文已清除'), findsNothing);
  });

  /// 「清除上下文」按钮的 onPressed（null = 灰态不可点）。
  /// byTooltip 命中的是 Tooltip 组件，需向上取 IconButton 才能断言 onPressed。
  IconButton clearButton(WidgetTester tester) => tester.widget<IconButton>(
        find
            .ancestor(
              of: find.byTooltip('清除上下文'),
              matching: find.byType(IconButton),
            )
            .first,
      );

  testWidgets('清除上下文按钮：ready 且有未清除消息时可点', (tester) async {
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.ready,
        messages: <ChatMessage>[_user('问'), _assistant('答')],
      ),
    );
    await _pump(tester, h.container);
    await tester.pumpAndSettle();

    expect(clearButton(tester).onPressed, isNotNull);
  });

  testWidgets('清除上下文按钮：已清到末尾 / 空会话时灰态', (tester) async {
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.ready,
        messages: <ChatMessage>[_user('问'), _assistant('答')],
        contextBaseIndex: 2, // 已清到末尾
      ),
    );
    await _pump(tester, h.container);
    await tester.pumpAndSettle();

    expect(clearButton(tester).onPressed, isNull);

    final empty = _harness(const AssistantChatState());
    await _pump(tester, empty.container);
    await tester.pumpAndSettle();

    expect(clearButton(tester).onPressed, isNull);
  });

  testWidgets('清除上下文按钮：在途（loading/streaming）时灰态', (tester) async {
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.loading,
        messages: <ChatMessage>[_user('问')],
      ),
    );
    await _pump(tester, h.container);
    await tester.pump();

    expect(clearButton(tester).onPressed, isNull);

    await _teardownAnim(tester);
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
    // 用户气泡与助手气泡各一个复制按钮。
    expect(find.byTooltip('复制'), findsNWidgets(2));
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

  testWidgets('回答失败：用户提问气泡出「重新发送」，点击直接重发（末条不弹确认）',
      (tester) async {
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.error,
        messages: <ChatMessage>[_user('出一道题')],
        message: '网络开小差了',
      ),
    );
    await _pump(tester, h.container);
    await tester.pumpAndSettle();

    expect(find.byTooltip('重新发送'), findsOneWidget);

    await tester.tap(find.byTooltip('重新发送'));
    await tester.pumpAndSettle();

    // 末条提问之后无记录可删 → 不弹确认，直接重发 index 0。
    expect(h.session.resentIndexes, <int>[0]);
  });

  testWidgets('历史提问重发：先弹确认框；确认后转接 resendFrom(该下标)',
      (tester) async {
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.ready,
        messages: <ChatMessage>[
          _user('第一问'),
          _assistant('第一答'),
          _user('第二问'),
          _assistant('第二答'),
        ],
      ),
    );
    await _pump(tester, h.container);
    await tester.pumpAndSettle();

    // 两条用户提问各有一个「重新发送」。
    expect(find.byTooltip('重新发送'), findsNWidgets(2));

    // 点第一问（非末条）→ 弹确认框。
    await tester.tap(find.byTooltip('重新发送').first);
    await tester.pumpAndSettle();
    expect(find.text('重新发送这条提问？'), findsOneWidget);
    expect(h.session.resentIndexes, isEmpty); // 未确认前不执行

    // 取消：不执行。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(h.session.resentIndexes, isEmpty);

    // 再点并确认：以第一问的下标 0 重发。
    await tester.tap(find.byTooltip('重新发送').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '重新发送'));
    await tester.pumpAndSettle();
    expect(h.session.resentIndexes, <int>[0]);
  });

  testWidgets('在途（streaming）：用户提问气泡不出「重新发送」', (tester) async {
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.streaming,
        messages: <ChatMessage>[_user('讲讲乘法')],
        streamingText: '乘法是……',
      ),
    );
    await _pump(tester, h.container);
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byTooltip('重新发送'), findsNothing);

    await _teardownAnim(tester);
  });

  testWidgets('用户气泡出「复制」按钮（原先只能长按）', (tester) async {
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.ready,
        messages: <ChatMessage>[_user('1+1'), _assistant('等于 2')],
      ),
    );
    await _pump(tester, h.container);
    await tester.pumpAndSettle();

    // 用户气泡 + 助手气泡各一个复制按钮。
    expect(find.byTooltip('复制'), findsNWidgets(2));
  });

  testWidgets('进入页面有历史：消息列表自动定位到最下方', (tester) async {
    // 缩小视口（400x600 逻辑像素），使 30 条消息超出可滚动范围。
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final messages = <ChatMessage>[
      for (var i = 0; i < 15; i++) ...[
        _user('问题 $i：这是一段用来撑高列表的较长文本内容'),
        _assistant('回答 $i：这是一段用来撑高列表的较长文本内容'),
      ],
    ];
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.ready,
        messages: messages,
      ),
    );
    await _pump(tester, h.container);
    await tester.pumpAndSettle();

    // 末条消息在视口内已构建（未滚动时 ListView.builder 不构建视口外条目，
    // 末条 itemBuilder 下标即滚动位置的最直接证据）。
    expect(find.textContaining('回答 14'), findsOneWidget);
    // 首条已远出视口与缓存区（未构建 = 已滚离顶部）。
    expect(find.textContaining('回答 0'), findsNothing);
  });

  testWidgets('工具轮次：assistant.toolCalls 与 role:tool 渲染为可折叠工具卡，'
      '最终回答仍为气泡', (tester) async {
    final h = _harness(
      AssistantChatState(
        status: AssistantChatStatus.ready,
        messages: <ChatMessage>[
          _user('讲讲我的错题'),
          const ChatMessage(
            role: ChatRole.assistant,
            content: '',
            toolCalls: <ToolCall>[
              ToolCall(
                id: 'call_1',
                name: 'explain_mistake',
                argumentsJson: '{}',
              ),
            ],
          ),
          const ChatMessage(
            role: ChatRole.tool,
            content: '题目：25 + 38 = ?',
            toolCallId: 'call_1',
            name: 'explain_mistake',
          ),
          _assistant('我们一步步来看～'),
        ],
      ),
    );
    await _pump(tester, h.container);
    await tester.pumpAndSettle();

    // 调用请求 + 结果回灌 = 两张工具卡；user + 最终回答 = 两个气泡。
    expect(find.byType(ToolMessageCard), findsNWidgets(2));
    expect(find.byType(ChatMessageBubble), findsNWidgets(2));
    expect(find.text('调用工具：讲解错题'), findsOneWidget);
    expect(find.text('工具结果：讲解错题'), findsOneWidget);
    // 默认折叠：工具结果明细不出现在初始视图。
    expect(find.text('题目：25 + 38 = ?'), findsNothing);
    // 最终回答气泡仍带「重新生成」。
    expect(find.byTooltip('重新生成'), findsOneWidget);
  });

  group('回答朗读', () {
    testWidgets('ready：回答气泡出「朗读」，用户气泡不出', (tester) async {
      final h = _harness(
        AssistantChatState(
          status: AssistantChatStatus.ready,
          messages: <ChatMessage>[_user('1+1'), _assistant('等于 2')],
        ),
      );
      await _pump(tester, h.container);
      await tester.pumpAndSettle();

      expect(find.byTooltip('朗读'), findsOneWidget);
    });

    testWidgets('点击「朗读」：清洗后文本送 TTS，图标切停止；完成后还原',
        (tester) async {
      final h = _harness(
        AssistantChatState(
          status: AssistantChatStatus.ready,
          messages: <ChatMessage>[
            _user('二分之一怎么写'),
            _assistant(r'**结果是** $\frac{1}{2}$ 哦'),
          ],
        ),
      );
      final handles = _stubSpeakSentences(h.tts);
      await _pump(tester, h.container);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('朗读'));
      await tester.pumpAndSettle();

      // Markdown / LaTeX 已清洗为口语文本再送 TTS。
      expect(handles.single.text, '结果是 2分之1 哦');
      // 朗读中：按钮切换为「停止朗读」。
      expect(find.byTooltip('停止朗读'), findsOneWidget);

      // 首段就绪 → 全部朗读完毕：回空闲，按钮还原。
      handles.single.signalReady();
      handles.single.signalFinish();
      await tester.pumpAndSettle();
      expect(find.byTooltip('朗读'), findsOneWidget);
      verifyNever(() => h.tts.stop());
    });

    testWidgets('朗读中再次点击：转接 tts.stop，停止后按钮还原', (tester) async {
      final h = _harness(
        AssistantChatState(
          status: AssistantChatStatus.ready,
          messages: <ChatMessage>[_user('1+1'), _assistant('等于 2')],
        ),
      );
      final handles = _stubSpeakSentences(h.tts);
      await _pump(tester, h.container);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('朗读'));
      await tester.pumpAndSettle();
      handles.single.signalReady();
      await tester.pump();

      await tester.tap(find.byTooltip('停止朗读'));
      await tester.pumpAndSettle();

      verify(() => h.tts.stop()).called(1);
      expect(find.byTooltip('朗读'), findsOneWidget);
      // 收尾挂起的朗读 Future（过期会话不写状态）。
      handles.single.signalFinish();
      await tester.pump();
    });

    testWidgets('播放中点其他回答：先停再切，新文本送 TTS', (tester) async {
      final h = _harness(
        AssistantChatState(
          status: AssistantChatStatus.ready,
          messages: <ChatMessage>[
            _user('第一问'),
            _assistant('第一答内容'),
            _user('第二问'),
            _assistant('第二答内容'),
          ],
        ),
      );
      final handles = _stubSpeakSentences(h.tts);
      await _pump(tester, h.container);
      await tester.pumpAndSettle();

      // 播第一条回答；之后第二条按钮仍为「朗读」。
      await tester.tap(find.byTooltip('朗读').first);
      await tester.pumpAndSettle();
      handles.first.signalReady();
      await tester.pump();

      // 点第二条回答的「朗读」→ 先 stop 再切。
      await tester.tap(find.byTooltip('朗读'));
      await tester.pumpAndSettle();

      verify(() => h.tts.stop()).called(1);
      expect(handles.length, 2);
      expect(handles.last.text, '第二答内容');
      // 新回答在播（其按钮已切「停止朗读」）。
      expect(find.byTooltip('停止朗读'), findsOneWidget);

      handles.first.signalFinish();
      handles.last.signalReady();
      handles.last.signalFinish();
      await tester.pumpAndSettle();
      expect(find.byTooltip('停止朗读'), findsNothing);
    });

    testWidgets('退出页面：停止朗读', (tester) async {
      final h = _harness(
        AssistantChatState(
          status: AssistantChatStatus.ready,
          messages: <ChatMessage>[_user('1+1'), _assistant('等于 2')],
        ),
      );
      final handles = _stubSpeakSentences(h.tts);
      await _pump(tester, h.container);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('朗读'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());

      verify(() => h.tts.stop()).called(1);
      handles.single.signalFinish();
      await tester.pump();
    });

    testWidgets('无可朗读文本（全代码块回答）：提示且不调 TTS', (tester) async {
      final h = _harness(
        AssistantChatState(
          status: AssistantChatStatus.ready,
          messages: <ChatMessage>[
            _user('写段代码'),
            _assistant('```\nprint(1);\n```'),
          ],
        ),
      );
      final handles = _stubSpeakSentences(h.tts);
      await _pump(tester, h.container);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('朗读'));
      await tester.pumpAndSettle();

      expect(find.text('这条回答没有可朗读的文本内容'), findsOneWidget);
      expect(handles, isEmpty);
      // 未进入播放态，按钮保持「朗读」。
      expect(find.byTooltip('朗读'), findsOneWidget);
    });

    testWidgets('正在朗读的回答被重发截断移除：自动停止', (tester) async {
      final h = _harness(
        AssistantChatState(
          status: AssistantChatStatus.ready,
          messages: <ChatMessage>[
            _user('问一'),
            _assistant('答一'),
            _user('问二'),
            _assistant('答二'),
          ],
        ),
      );
      final handles = _stubSpeakSentences(h.tts);
      await _pump(tester, h.container);
      await tester.pumpAndSettle();

      // 播最后一条回答（答二）。
      await tester.tap(find.byTooltip('朗读').last);
      await tester.pumpAndSettle();
      handles.single.signalReady();
      await tester.pump();

      // 重发第一问：其后记录（含正在朗读的答二）被截断删除 → 自动停播。
      h.chat.state = AssistantChatState(
        status: AssistantChatStatus.ready,
        messages: <ChatMessage>[_user('问一')],
      );
      await tester.pumpAndSettle();

      verify(() => h.tts.stop()).called(1);
      expect(find.byTooltip('停止朗读'), findsNothing);
      handles.single.signalFinish();
      await tester.pump();
    });

    testWidgets('准备期（首段未就绪）截断正在启动的朗读：同样自动停止',
        (tester) async {
      final h = _harness(
        AssistantChatState(
          status: AssistantChatStatus.ready,
          messages: <ChatMessage>[
            _user('问一'),
            _assistant('答一'),
            _user('问二'),
            _assistant('答二'),
          ],
        ),
      );
      final handles = _stubSpeakSentences(h.tts);
      await _pump(tester, h.container);
      await tester.pumpAndSettle();

      // 点击朗读但不投递 onReady（停留在合成准备期）。
      await tester.tap(find.byTooltip('朗读').last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('停止朗读'), findsOneWidget);

      // 截断移除正在启动的目标 → 仍自动停播，不留幽灵音频。
      h.chat.state = AssistantChatState(
        status: AssistantChatStatus.ready,
        messages: <ChatMessage>[_user('问一')],
      );
      await tester.pumpAndSettle();

      verify(() => h.tts.stop()).called(1);
      expect(find.byTooltip('停止朗读'), findsNothing);
      // 被停止的会话完成后不复活状态（令牌失守）。
      handles.single.signalFinish();
      await tester.pumpAndSettle();
      expect(find.byTooltip('停止朗读'), findsNothing);
    });
  });
}





