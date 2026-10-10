// lib/features/assistant/widgets/conversation_drawer.dart
//
// 层级：features/assistant/widgets
// 职责：会话抽屉。列出当前 profile 的全部会话（updatedAt 倒序），
//       支持新建 / 切换 / 重命名（AlertDialog）/ 删除（二次确认）。
//       repo（Hive）非响应式，故 watch assistantSessionProvider 的 revision
//       触发重建后重新读取 repo（见 session provider 注释）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/assistant_conversation.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/assistant/assistant_session_provider.dart';

/// 会话历史抽屉。
class ConversationDrawer extends ConsumerWidget {
  const ConversationDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // 订阅 session：conversationId（高亮当前）+ revision（repo 变更后重读）。
    final session = ref.watch(assistantSessionProvider);
    final repo = ref.read(conversationRepositoryProvider);
    final conversations = repo.getAll();
    final currentId = session.conversationId;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SpacingTokens.md,
                SpacingTokens.md,
                SpacingTokens.sm,
                SpacingTokens.sm,
              ),
              child: Row(
                children: <Widget>[
                  Text(
                    '对话历史',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      ref.read(assistantSessionProvider.notifier).startNew();
                    },
                    icon: const Icon(Icons.add),
                    tooltip: '新建对话',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: conversations.isEmpty
                  ? Center(
                      child: Text(
                        '暂无对话',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(SpacingTokens.sm),
                      itemCount: conversations.length,
                      itemBuilder: (context, index) {
                        final c = conversations[index];
                        return _buildItem(
                          context,
                          ref,
                          theme,
                          c,
                          isCurrent: c.id == currentId,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    Conversation c, {
    required bool isCurrent,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        onTap: () {
          Navigator.of(context).pop();
          ref.read(assistantSessionProvider.notifier).switchTo(c.id);
        },
        child: AppTile(
          icon: isCurrent
              ? Icons.chat_bubble
              : Icons.chat_bubble_outline,
          iconColor: isCurrent
              ? theme.colorScheme.primary
              : theme.colorScheme.secondary,
          title: c.title,
          subtitle: _formatTime(c.updatedAt),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'rename') {
                _showRenameDialog(context, ref, c);
              } else if (value == 'delete') {
                _confirmDelete(context, ref, theme, c);
              }
            },
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'rename', child: Text('重命名')),
              PopupMenuItem<String>(value: 'delete', child: Text('删除')),
            ],
          ),
        ),
      ),
    );
  }

  /// 重命名对话：AlertDialog + TextField，确定后写 repo。
  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    Conversation c,
  ) async {
    final controller = TextEditingController(text: c.title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名对话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(hintText: '输入对话名称'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) {
      await ref.read(assistantSessionProvider.notifier).rename(c.id, result);
    }
  }

  /// 删除对话：二次确认 AlertDialog，确认后级联删除。
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    Conversation c,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除对话'),
        content: Text('确定删除「${c.title}」吗？此操作不可撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(assistantSessionProvider.notifier).delete(c.id);
    }
  }

  /// 友好的相对时间：今天 HH:mm / 昨天 HH:mm / N 天前 / yyyy/MM/dd。
  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(t.year, t.month, t.day);
    final diffDays = today.difference(that).inDays;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    if (diffDays == 0) return '$hh:$mm';
    if (diffDays == 1) return '昨天 $hh:$mm';
    if (diffDays < 7) return '$diffDays 天前';
    final mo = t.month.toString().padLeft(2, '0');
    final da = t.day.toString().padLeft(2, '0');
    return '${t.year}/$mo/$da';
  }
}
