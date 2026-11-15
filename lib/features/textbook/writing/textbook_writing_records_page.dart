import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook_writing_progress.dart';
import 'package:poemath/domain/textbook_writing_content.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/writing/stroke_data_provider.dart';
import 'package:poemath/features/textbook/writing/writing_providers.dart';

/// 本课各字的练习事实，直接读取现有进度，不记录新的练习。
class TextbookWritingRecordsPage extends ConsumerWidget {
  const TextbookWritingRecordsPage({
    super.key,
    required this.bookId,
    required this.lessonId,
  });

  final String bookId, lessonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('练习记录')),
    body: SafeArea(child: _content(context, ref)),
  );

  Widget _content(BuildContext context, WidgetRef ref) {
    final course = ref.watch(textbookCourseProvider(bookId));
    final strokes = ref.watch(writingStrokeDataProvider);
    final progress = ref.watch(textbookWritingProgressProvider(bookId));
    // 刷新时先隐藏旧值，避免短暂展示上一个档案或版本的记录。
    if (course.isLoading || strokes.isLoading || progress.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (course.hasError || strokes.hasError || progress.hasError) {
      return AppEmptyState(
        icon: Icons.history_outlined,
        title: '暂时无法读取练习记录',
        description: '请重试。',
        actions: [
          TextButton(
            onPressed: () {
              ref.invalidate(textbookCourseProvider(bookId));
              ref.invalidate(writingStrokeDataProvider);
              ref.invalidate(textbookWritingProgressProvider(bookId));
            },
            child: const Text('重试'),
          ),
        ],
      );
    }
    final pack = course.valueOrNull;
    final asset = strokes.valueOrNull;
    final saved = progress.valueOrNull;
    final lesson = pack?.lessons.where((l) => l.id == lessonId).firstOrNull;
    if (pack == null ||
        asset == null ||
        saved == null ||
        lesson == null ||
        saved.profileId != ProfileScope.currentId ||
        saved.bookId != bookId ||
        saved.editionId != pack.edition.id) {
      return const AppEmptyState(
        icon: Icons.menu_book_outlined,
        title: '本课暂不可用',
        description: '请返回教材重新进入。',
      );
    }
    final targets = writingTargets(
      pack,
      lesson,
      hasStrokeData: asset.hasStrokeDataSync,
    );
    if (targets.isEmpty) {
      return const AppEmptyState(
        icon: Icons.edit_outlined,
        title: '本课暂无会写字。',
        description: '请家长核对本课的书写内容。',
      );
    }
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(SpacingTokens.md),
      children: [
        Semantics(
          header: true,
          child: Text(lesson.title, style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: SpacingTokens.md),
        for (var index = 0; index < targets.length; index++) ...[
          _recordTile(context, targets[index], saved),
          if (index + 1 < targets.length)
            const Divider(height: SpacingTokens.lg),
        ],
      ],
    );
  }

  Widget _recordTile(
    BuildContext context,
    WritingTarget target,
    WritingProgress progress,
  ) {
    final saved =
        progress.records[WritingProgress.targetKey(lessonId, target.id)];
    final record = saved?.fingerprint == target.fingerprint ? saved : null;
    final counts = [
      ('描红', record?.traceCount ?? 0),
      ('自写', record?.freeCount ?? 0),
      ('拼装', record?.puzzleCount ?? 0),
    ];
    return AppTile(
      key: ValueKey('writing-record-${target.id}'),
      iconColor: Theme.of(context).colorScheme.primary,
      title: target.text,
      titleSuffix: target.pinyin.isEmpty ? null : target.pinyin,
      titleSuffixInline: true,
      titleWrap: true,
      subtitle: counts
          .map((entry) {
            final (label, count) = entry;
            return '$label $count 次 · ${count > 0 ? '已完成' : '未完成'}';
          })
          .join('\n'),
      trailing: const SizedBox.shrink(),
      flat: true,
      flatLeadingEdgeAligned: true,
      flatTrailingEdgeAligned: true,
    );
  }
}
