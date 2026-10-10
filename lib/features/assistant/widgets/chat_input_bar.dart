// lib/features/assistant/widgets/chat_input_bar.dart
//
// 层级：features/assistant/widgets
// 职责：底部输入栏。多行 TextField + 主按钮；非在途时为「发送」（空文本禁用），
//       在途（loading/streaming）时切为「停止」。SafeArea 适配底部安全区。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';

/// 对话输入栏。
///
/// - [isBusy]：是否在途（loading/streaming）；为 true 时主按钮为「停止」。
/// - [onSend]：发送回调（已去空白、非空）。
/// - [onStop]：停止回调。
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.isBusy,
    required this.onSend,
    required this.onStop,
  });

  final bool isBusy;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final canSend = _controller.text.trim().isNotEmpty;
    if (canSend != _canSend) setState(() => _canSend = canSend);
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: '问问 AI 助手…',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.md,
                    vertical: SpacingTokens.sm + 2,
                  ),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(SpacingTokens.radiusLarge),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: SpacingTokens.sm),
            _buildButton(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(ThemeData theme) {
    if (widget.isBusy) {
      return IconButton.filled(
        onPressed: widget.onStop,
        icon: const Icon(Icons.stop),
        tooltip: '停止',
        style: IconButton.styleFrom(
          backgroundColor: theme.colorScheme.error,
          foregroundColor: theme.colorScheme.onError,
        ),
      );
    }
    return IconButton.filled(
      onPressed: _canSend ? _handleSend : null,
      icon: const Icon(Icons.arrow_upward),
      tooltip: '发送',
    );
  }
}
