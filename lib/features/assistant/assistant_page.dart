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
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/assistant/assistant_chat_controller.dart';
import 'package:poemath/features/assistant/assistant_chat_state.dart';
import 'package:poemath/features/assistant/assistant_session_provider.dart';
import 'package:poemath/features/assistant/widgets/chat_input_bar.dart';
import 'package:poemath/features/assistant/widgets/chat_message_bubble.dart';
import 'package:poemath/features/assistant/widgets/conversation_drawer.dart';

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
    final sessionState = ref.watch(assistantSessionProvider);
    // 消息 / 流式变化后滚到底部。
    ref.listen<AssistantChatState>(
      assistantChatControllerProvider,
      (_, __) => _scrollToBottomSoon(),
    );

    final repo = ref.read(conversationRepositoryProvider);
    final convId = sessionState.conversationId;
    final title =
        convId != null ? (repo.getById(convId)?.title ?? '新对话') : 'AI 助手';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(title),
        actions: <Widget>[
          IconButton(
            onPressed: () => _session.startNew(),
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: '新建对话',
          ),
        ],
      ),
      drawer: const ConversationDrawer(),
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
    final hasPending = chatState.isLoading || chatState.isStreaming;
    if (messages.isEmpty && !hasPending && !chatState.isError) {
      return _buildEmptyState(theme);
    }
    final itemCount = messages.length + (hasPending ? 1 : 0);
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.md,
        vertical: SpacingTokens.sm,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
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
      },
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
