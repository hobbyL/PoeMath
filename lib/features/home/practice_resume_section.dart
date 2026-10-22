import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';

final practiceDraftsProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) async* {
  final drafts = PracticeDraftRepository();
  List<Map<String, dynamic>> read() {
    final result = <Map<String, dynamic>>[];
    for (final kind in PracticeDraftRepository.kinds) {
      try {
        final draft = drafts.get(kind);
        if (draft != null) {
          if (draft['records'] is! List || draft['problems'] is! List) {
            throw const FormatException('草稿题组无法读取');
          }
          result.add(draft);
        }
      } catch (_) {
        if (drafts.exists(kind)) result.add({'kind': kind, 'invalid': true});
      }
    }
    return result;
  }

  yield read();
  await for (final _ in drafts.changes()) {
    yield read();
  }
});

class PracticeResumeSection extends ConsumerWidget {
  const PracticeResumeSection({super.key});

  Future<void> _discard(BuildContext context, String kind) async {
    final drafts = PracticeDraftRepository();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未完成的题组？'),
        content: const Text('已答题目的历史记录会保留，未完成部分不再继续。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留草稿'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃草稿'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await drafts.remove(kind);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('草稿未能删除，请重试')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(practiceDraftsProvider).valueOrNull ?? [];
    if (drafts.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '继续练习',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: SpacingTokens.sm),
        for (final draft in drafts) ...[
          AppTile(
            icon: Icons.play_circle_outline,
            iconColor: theme.colorScheme.secondary,
            crossAxisAlignment: CrossAxisAlignment.start,
            title: draft['kind'] == 'math' ? '继续上次口算' : '继续上次应用题',
            subtitle: draft['invalid'] == true
                ? '草稿无法读取，可放弃后重新练习'
                : '已答 ${(draft['records'] as List<dynamic>).length} / ${(draft['problems'] as List<dynamic>).length} 题',
            onTap: draft['invalid'] == true
                ? null
                : () => context.push(
                      '${draft['kind'] == 'math' ? AppRoutes.mathPractice : AppRoutes.wordProblemPractice}?resume=1',
                    ),
            trailingAction: TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: theme.textTheme.bodySmall?.copyWith(height: 1.2),
              ),
              onPressed: () => _discard(context, draft['kind'] as String),
              child: const Text('放弃草稿'),
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
        ],
        const SizedBox(height: SpacingTokens.md),
      ],
    );
  }
}
