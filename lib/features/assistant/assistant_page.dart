// lib/features/assistant/assistant_page.dart
//
// 层级：features/assistant
// 职责：AI 助手主页。AppBar（当前会话标题 + 新建）+ 会话抽屉 + 消息列表 +
//       输入栏。进入页面经 session.ensureOpen() 打开最近 / 新建会话；
//       发送 / 停止 / 重答 / 会话增删改经 assistantSessionProvider 协调，
//       持久化由 session 的监听-diff 自动完成（见 assistant_session_provider）。
//       页面销毁仅 discardPending（丢弃在途流晚到回调，不写状态）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/colored_card.dart';
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

  @override
  void initState() {
    super.initState();
    _session = ref.read(assistantSessionProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _session.ensureOpen();
    });
  }

  @override
  void dispose() {
    // 仅丢弃在途流晚到回调，不写状态（避免对已卸载 element markNeedsBuild）。
    _session.discardPending();
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
      (_, __) => _scrollToBottomSoon(),
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
                    final cleared = ref
                        .read(assistantChatControllerProvider.notifier)
                        .clearContext();
                    if (cleared) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已清除上下文，后续对话不再带入之前的记录（记录保留）'),
                        ),
                      );
                    }
                  }
                : null,
            icon: const Icon(Icons.cleaning_services_outlined),
            tooltip: '清除上下文',
          ),
          Builder(
            builder: (context) => IconButton(
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              icon: const Icon(Icons.forum_outlined),
              tooltip: '会话列表',
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
    final itemCount = messages.length +
        (hasPending ? 1 : 0) +
        (showTrailingDivider ? 1 : 0);
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
    );
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
            Icon(Icons.smart_toy_outlined,
                size: 48, color: theme.colorScheme.primary,),
            const SizedBox(height: SpacingTokens.md),
            Text('你好，我是 AI 学习助手',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,),
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
            Icon(Icons.error_outline,
                color: theme.colorScheme.error, size: 20,),
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
                  Icon(Icons.smart_toy_outlined,
                      color: theme.colorScheme.tertiary,),
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
