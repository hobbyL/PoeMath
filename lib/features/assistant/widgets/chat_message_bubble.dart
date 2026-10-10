// lib/features/assistant/widgets/chat_message_bubble.dart
//
// 层级：features/assistant/widgets
// 职责：单条对话气泡。基于 ColoredCard（禁手写 BoxDecoration）：
//       用户消息 primary 右对齐，助手 / 工具消息 secondary 左对齐；
//       正文委托 AssistantMarkdown 渲染 Markdown + LaTeX。
//       长按复制；助手气泡底部操作行（复制 / 重新生成，按状态显隐）。
//       停止操作在输入栏（流式中切为停止），不在气泡内（见 design §4）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/colored_card.dart';
import 'package:poemath/features/assistant/widgets/assistant_markdown.dart';

/// 单条对话气泡。
///
/// - [role]：消息角色，决定对齐与配色（user 右 / 其余左）。
/// - [text]：正文（Markdown + `$...$` LaTeX）。
/// - [isStreaming]：流式气泡（启用淡入动画，禁用复制 / 操作行）。
/// - [onRegenerate]：非空时在助手气泡底部显示「重新生成」。
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.role,
    required this.text,
    this.isStreaming = false,
    this.onRegenerate,
  });

  final ChatRole role;
  final String text;
  final bool isStreaming;
  final VoidCallback? onRegenerate;

  bool get _isUser => role == ChatRole.user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxWidth = MediaQuery.sizeOf(context).width * 0.82;
    // 用户 primary、助手/工具 secondary；ColoredCard 内部按 8% 透明度着色。
    final bubbleColor =
        _isUser ? theme.colorScheme.primary : theme.colorScheme.secondary;
    // 助手完成态才显示操作行（流式中内容仍在增长，不可复制 / 重答）。
    final showActions = !_isUser && !isStreaming;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.xs),
      child: Align(
        alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment:
                _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              GestureDetector(
                onLongPress: isStreaming ? null : () => _copy(context),
                child: ColoredCard(
                  color: bubbleColor,
                  child: AssistantMarkdown(text, isStreaming: isStreaming),
                ),
              ),
              if (showActions) _buildActions(context, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, ThemeData theme) {
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          onPressed: () => _copy(context),
          icon: const Icon(Icons.copy_outlined, size: 18),
          tooltip: '复制',
          visualDensity: VisualDensity.compact,
          color: color,
        ),
        if (onRegenerate != null)
          IconButton(
            onPressed: onRegenerate,
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: '重新生成',
            visualDensity: VisualDensity.compact,
            color: color,
          ),
      ],
    );
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制'),
        duration: Duration(seconds: 1),
      ),
    );
  }
}
