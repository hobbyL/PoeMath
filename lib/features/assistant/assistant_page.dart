// lib/features/assistant/assistant_page.dart
//
// 层级：features/assistant
// 职责：AI 助手主页。AppBar（当前会话标题 + 新建）+ 会话抽屉 + 消息列表 +
//       输入栏。进入页面经 session.ensureOpen() 打开最近 / 新建会话；
//       发送 / 停止 / 重答 / 会话增删改经 assistantSessionProvider 协调，
//       持久化由 session 的监听-diff 自动完成（见 assistant_session_provider）。
//       页面销毁仅 discardPending（丢弃在途流晚到回调，不写状态）。
//       回答气泡提供朗读（TtsService，Markdown 清洗后逐句播）；竞态纪律
//       复用讲解弹层：会话令牌护栏 + _isPreparing 遮罩 + 先停再切。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/services/tts/markdown_speech_text.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/colored_card.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/assistant/assistant_chat_controller.dart';
import 'package:poemath/features/assistant/assistant_chat_state.dart';
import 'package:poemath/features/assistant/assistant_session_provider.dart';
import 'package:poemath/features/assistant/widgets/assistant_provider_switcher.dart';
import 'package:poemath/features/assistant/widgets/chat_input_bar.dart';
import 'package:poemath/features/assistant/widgets/chat_message_bubble.dart';
import 'package:poemath/features/assistant/widgets/conversation_drawer.dart';
import 'package:poemath/features/assistant/widgets/tool_message_card.dart';

/// AI 助手主页。
class AssistantPage extends ConsumerStatefulWidget {
  const AssistantPage({super.key});

  @override
  ConsumerState<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends ConsumerState<AssistantPage> {
  final ScrollController _scrollController = ScrollController();
  late final AssistantSessionController _session;

  /// TTS 服务（dispose 阶段 ref 不可用，initState 先捕获）。
  late final TtsService _tts;

  /// 正在朗读的回答（对象身份跟踪：重发截断 / 切换会话后据此停播）。
  ChatMessage? _speakingMessage;

  /// 是否正在朗读（含首段音频就绪前的准备期）。
  bool _isSpeaking = false;

  /// 点击朗读 → 首段音频就绪前（或停止 await 期）的遮罩期，作为重入
  /// 守卫拦截一切重复点击，避免 stop 未完成时并发启动第二个会话。
  bool _isPreparing = false;

  /// 当前持有播放态的会话 id，-1 表示无（空闲 / 已停止）。
  /// 身份来源是 [TtsService.currentSessionId]（服务唯一权威）。
  int _activeSessionId = -1;

  /// 该回调 / 该次 await 是否仍属于当前持有播放态的会话。
  bool _isCurrentSession(int sessionId) => sessionId == _activeSessionId;

  @override
  void initState() {
    super.initState();
    _session = ref.read(assistantSessionProvider.notifier);
    _tts = ref.read(ttsServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _session.ensureOpen();
      // 进入时直接跳到最下方（瞬时定位，不做动画）。重进页面时 ensureOpen
      // 早退（provider 常驻、会话仍打开），聊天状态无变化、ref.listen 不
      // 触发，列表会停在顶部——故此处无条件定位；无历史时 jumpTo(0) 无感。
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
    });
  }

  @override
  void dispose() {
    // 仅丢弃在途流晚到回调，不写状态（避免对已卸载 element markNeedsBuild）。
    _session.discardPending();
    // 退出页面即停朗读（同讲解弹层「关闭停播」）：stop 同步段递增服务
    // 令牌，在途朗读的晚到回调天然失配。
    unawaited(
      _tts.stop().onError(
            (error, stackTrace) => AppLogger.e(
              '退出 AI 助手时停止朗读失败',
              tag: 'Assistant',
              error: error,
              stackTrace: stackTrace,
            ),
          ),
    );
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatState = ref.watch(assistantChatControllerProvider);
    // 消息 / 流式变化后滚到底部。
    ref.listen<AssistantChatState>(
      assistantChatControllerProvider,
      (_, next) {
        _syncSpeakingMessage(next.messages);
        _scrollToBottomSoon();
      },
    );

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        // leading 显式返回箭头（点左上角退出页面）；标题位放「模型 | 供应商」
        // 切换器；会话列表入口在右侧 endDrawer（右滑或点图标打开）。
        leading: const BackButton(),
        titleSpacing: 0,
        centerTitle: false,
        title: const AssistantProviderSwitcher(),
        actions: <Widget>[
          IconButton(
            onPressed: (chatState.messages.isNotEmpty &&
                    chatState.contextBaseIndex < chatState.messages.length &&
                    !chatState.isBusy)
                ? () {
                    final cleared = _session.clearContext();
                    if (cleared) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已清除上下文，后续对话不再带入之前的记录（记录保留）'),
                        ),
                      );
                    }
                  }
                : null,
            iconSize: 24,
            icon: const Icon(Icons.cleaning_services_outlined),
            tooltip: '清除上下文',
          ),
          Builder(
            builder: (context) => IconButton(
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              iconSize: 24,
              icon: const Icon(Icons.history),
              tooltip: '对话记录',
            ),
          ),
        ],
      ),
      endDrawer: const ConversationDrawer(),
      body: _buildBody(theme, chatState),
    );
  }

  Widget _buildBody(ThemeData theme, AssistantChatState chatState) {
    if (chatState.isUnconfigured) {
      return _buildUnconfigured(theme);
    }
    return Column(
      children: <Widget>[
        Expanded(child: _buildMessageList(theme, chatState)),
        if (chatState.isError && chatState.message != null)
          _buildErrorBanner(theme, chatState.message!),
        ChatInputBar(
          isBusy: chatState.isBusy,
          onSend: (text) =>
              ref.read(assistantSessionProvider.notifier).send(text),
          onStop: () => ref.read(assistantSessionProvider.notifier).stop(),
        ),
      ],
    );
  }

  Widget _buildMessageList(ThemeData theme, AssistantChatState chatState) {
    final messages = chatState.messages;
    final base = chatState.contextBaseIndex;
    final hasPending = chatState.isLoading || chatState.isStreaming;
    if (messages.isEmpty && !hasPending && !chatState.isError) {
      return _buildEmptyState(theme);
    }
    // 清除点正好在末尾、且无在途气泡时，补一条末尾分割线项。
    final showTrailingDivider =
        base > 0 && base == messages.length && !hasPending;
    final itemCount =
        messages.length + (hasPending ? 1 : 0) + (showTrailingDivider ? 1 : 0);
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.md,
        vertical: SpacingTokens.sm,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (showTrailingDivider && index == itemCount - 1) {
          return _buildContextDivider(theme);
        }
        final item = _buildMessageItem(theme, chatState, index);
        // 上下文起点前插入分割线：此点之前的消息仅存档、不参与请求。
        if (base > 0 && index == base) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[_buildContextDivider(theme), item],
          );
        }
        return item;
      },
    );
  }

  /// 单条消息项（流式/等待气泡、工具卡、普通气泡），不含上下文分割线。
  Widget _buildMessageItem(
    ThemeData theme,
    AssistantChatState chatState,
    int index,
  ) {
    final messages = chatState.messages;
    if (index >= messages.length) {
      if (chatState.isStreaming) {
        return ChatMessageBubble(
          role: ChatRole.assistant,
          text: chatState.streamingText,
          isStreaming: true,
        );
      }
      return const _PendingBubble();
    }
    final m = messages[index];
    // 工具调用请求（assistant 携带 toolCalls）→ 可折叠小卡（默认折叠）。
    final toolCalls = m.toolCalls;
    if (m.role == ChatRole.assistant &&
        toolCalls != null &&
        toolCalls.isNotEmpty) {
      final labels = toolCalls.map((c) => toolDisplayName(c.name)).join('、');
      final detail = <String>[
        if (m.content.trim().isNotEmpty) m.content.trim(),
        for (final c in toolCalls)
          '${toolDisplayName(c.name)}（${c.name}）\n参数：${c.argumentsJson}',
      ].join('\n\n');
      return ToolMessageCard(title: '调用工具：$labels', detail: detail);
    }
    // 工具结果回灌（role:tool）→ 可折叠小卡（默认折叠）。
    if (m.role == ChatRole.tool) {
      return ToolMessageCard(
        title: '工具结果：${toolDisplayName(m.name ?? '')}',
        detail: m.content,
      );
    }
    final isLastAssistant = index == messages.length - 1 &&
        m.role == ChatRole.assistant &&
        !chatState.isBusy;
    return ChatMessageBubble(
      role: m.role,
      text: m.content,
      onRegenerate: isLastAssistant
          ? () => ref.read(assistantSessionProvider.notifier).regenerate()
          : null,
      // 用户提问：非在途时可重新发送（回答失败 / 被中断后的重试入口）。
      onResend: (m.role == ChatRole.user && !chatState.isBusy)
          ? () => _confirmResend(index, isLast: index == messages.length - 1)
          : null,
      // 助手回答：朗读当前内容（Markdown 清洗后逐句播）。
      onSpeak: m.role == ChatRole.assistant ? () => _onTapSpeak(m) : null,
      isSpeaking: _isSpeaking && identical(_speakingMessage, m),
    );
  }

  /// 重新发送第 [index] 条提问。其后尚有记录时先确认（删除不可撤销）；
  /// [isLast]（末条提问，无后续记录可删）直接重发。
  Future<void> _confirmResend(int index, {required bool isLast}) async {
    if (!isLast) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('重新发送这条提问？'),
          content: const Text('这条提问之后的对话记录会被删除，且不能恢复。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('重新发送'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      if (!mounted) return;
    }
    await ref.read(assistantSessionProvider.notifier).resendFrom(index);
  }

  /// 朗读目标失守检测：正在朗读的回答被重发截断 / 切换会话移除后停播，
  /// 避免气泡已消失而音频仍在播、且无停止入口。ChatMessage 未覆写 ==，
  /// contains 即对象身份判断。准备期（首段音频未就绪）同样停播：stop
  /// 递增服务令牌使在途会话首个检查即死，[_startSpeaking] 的 finally 因
  /// 令牌失配不会复位已清理的状态。
  void _syncSpeakingMessage(List<ChatMessage> messages) {
    final target = _speakingMessage;
    if (target == null || messages.contains(target)) return;
    unawaited(_stopSpeaking());
  }

  /// 点回答气泡的朗读按钮：空闲 → 朗读；正在播本条 → 停止；正在播其他
  /// 条 → 先停再切（stop 失败不切换，防双读——同诗词页点击播放纪律）。
  Future<void> _onTapSpeak(ChatMessage message) async {
    if (_isPreparing) return;
    if (_isSpeaking) {
      final wasSame = _speakingMessage == message;
      // 先置遮罩再 await stop：挡住停止窗口期的二次点击。
      setState(() => _isPreparing = true);
      final stopped = await _stopSpeaking();
      if (mounted) setState(() => _isPreparing = false);
      if (!stopped || wasSame || !mounted) return;
    }
    await _startSpeaking(message);
  }

  /// 停止当前朗读并清理播放态。返回 stop 是否成功；失败时已弹 SnackBar。
  /// 失败保留 `_isSpeaking`（音频可能仍在播），让后续点击继续走停止路由。
  Future<bool> _stopSpeaking() async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await _tts.stop();
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '停止 AI 助手朗读失败',
        tag: 'Assistant',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          const SnackBar(content: Text('停止朗读失败，请稍后重试')),
        );
      }
      return false;
    }
    _activeSessionId = -1;
    _speakingMessage = null;
    if (mounted) setState(() => _isSpeaking = false);
    return true;
  }

  /// 朗读一条回答（Markdown 清洗后按标点分句播）。会话令牌护栏复用讲解
  /// 弹层纪律：`Future.sync` 使「捕获会话 id」一定先于任何异常 / 回调被
  /// 观察到。
  Future<void> _startSpeaking(ChatMessage message) async {
    final speakable = markdownToSpeechText(message.content).trim();
    if (speakable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这条回答没有可朗读的文本内容')),
      );
      return;
    }
    final scaffold = ScaffoldMessenger.of(context);
    setState(() {
      _isPreparing = true;
      _isSpeaking = true;
    });
    _speakingMessage = message;
    final speaking = Future.sync(() {
      return _tts.speakSentences(
        speakable,
        onReady: (sessionId) {
          if (mounted && _isCurrentSession(sessionId)) {
            setState(() => _isPreparing = false);
          }
        },
      );
    });
    // 朗读入口在任何 await 之前递增服务令牌，发起与读取之间无挂起点。
    final sessionId = _tts.currentSessionId;
    _activeSessionId = sessionId;
    try {
      await speaking;
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        'AI 助手朗读失败',
        tag: 'Assistant',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted && _isCurrentSession(sessionId)) {
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          SnackBar(
            content: Text(
              error is TtsException
                  ? '朗读失败：${error.message}'
                  : '朗读失败，请检查系统语音服务后重试',
            ),
          ),
        );
      }
    } finally {
      // 过期会话（已被 stop / 新会话接管）不清理，避免复位新会话的状态。
      if (_isCurrentSession(sessionId)) {
        _activeSessionId = -1;
        _speakingMessage = null;
        if (mounted) {
          setState(() {
            _isPreparing = false;
            _isSpeaking = false;
          });
        }
      }
    }
  }

  /// 上下文清除分割线：标记此处之前的消息仅存档、不再作为对话上下文发送。
  Widget _buildContextDivider(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
      child: Row(
        children: <Widget>[
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm),
            child: Text(
              '上下文已清除',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.smart_toy_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: SpacingTokens.md),
            Text(
              '你好，我是 AI 学习助手',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SpacingTokens.sm),
            Text(
              '可以问我数学题、古诗词，或任何学习上的问题～',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(ThemeData theme, String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SpacingTokens.md,
        0,
        SpacingTokens.md,
        SpacingTokens.sm,
      ),
      child: ColoredCard(
        color: theme.colorScheme.error,
        width: double.infinity,
        child: Row(
          children: <Widget>[
            Icon(
              Icons.error_outline,
              color: theme.colorScheme.error,
              size: 20,
            ),
            const SizedBox(width: SpacingTokens.sm),
            Expanded(
              child: Text(message, style: theme.textTheme.bodySmall),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(assistantSessionProvider.notifier).regenerate(),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnconfigured(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: ColoredCard(
          color: theme.colorScheme.tertiary,
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.smart_toy_outlined,
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: SpacingTokens.sm),
                  Expanded(
                    child: Text(
                      '尚未配置 AI 服务',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SpacingTokens.sm),
              Text(
                'AI 助手需要家长先配置一个 OpenAI 兼容的大模型服务'
                '（地址、模型与 API Key）。配置后即可开始对话。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: SpacingTokens.md),
              FilledButton.tonalIcon(
                onPressed: () => context.push(AppRoutes.llmSettings),
                icon: const Icon(Icons.settings_outlined),
                label: const Text('去配置'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 挂起（loading）气泡：助手正在思考。
class _PendingBubble extends StatelessWidget {
  const _PendingBubble();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.xs),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ColoredCard(
          color: theme.colorScheme.secondary,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: SpacingTokens.sm),
              Text('思考中…', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
