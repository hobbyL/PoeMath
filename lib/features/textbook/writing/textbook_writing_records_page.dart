import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook_writing_attempt.dart';
import 'package:poemath/data/models/textbook_writing_progress.dart';
import 'package:poemath/domain/textbook_writing_content.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/writing/stroke_data_provider.dart';
import 'package:poemath/features/textbook/writing/writing_attempt_preview.dart';
import 'package:poemath/features/textbook/writing/writing_providers.dart';

typedef _WritingRecordsView = ({String title, Widget content});

/// 本课各字的练习事实，直接读取现有进度，不记录新的练习。
class TextbookWritingRecordsPage extends ConsumerWidget {
  const TextbookWritingRecordsPage({
    super.key,
    required this.bookId,
    required this.lessonId,
    this.targetId,
    this.attemptId,
  });

  final String bookId, lessonId;
  final String? targetId, attemptId;

  static const double _cardWidth = 160;
  static const int _maximumColumns = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = _content(context, ref);
    return Scaffold(
      appBar: AppBar(title: Text(view.title)),
      body: SafeArea(child: view.content),
    );
  }

  _WritingRecordsView _content(BuildContext context, WidgetRef ref) {
    _WritingRecordsView view(Widget content, {WritingTarget? target}) => (
      title: attemptId != null
          ? '练习详情'
          : target != null
          ? '${target.text}·练习记录'
          : '练习记录',
      content: content,
    );
    final course = ref.watch(textbookCourseProvider(bookId));
    final strokes = ref.watch(writingStrokeDataProvider);
    final progress = ref.watch(textbookWritingProgressProvider(bookId));
    // 刷新时先隐藏旧值，避免短暂展示上一个档案或版本的记录。
    if (course.isLoading || strokes.isLoading || progress.isLoading) {
      return view(const Center(child: CircularProgressIndicator()));
    }
    if (course.hasError || strokes.hasError || progress.hasError) {
      return view(
        AppEmptyState(
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
        ),
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
      return view(
        const AppEmptyState(
          icon: Icons.menu_book_outlined,
          title: '本课暂不可用',
          description: '请返回教材重新进入。',
        ),
      );
    }
    final targets = writingTargets(
      pack,
      lesson,
      hasStrokeData: asset.hasStrokeDataSync,
    );
    if (targets.isEmpty) {
      return view(
        const AppEmptyState(
          icon: Icons.edit_outlined,
          title: '本课暂无会写字。',
          description: '请家长核对本课的书写内容。',
        ),
      );
    }
    if (targetId != null || attemptId != null) {
      final target = targets.where((t) => t.id == targetId).firstOrNull;
      if (target == null) {
        return view(
          const AppEmptyState(
            icon: Icons.edit_outlined,
            title: '这个字的记录暂不可用',
            description: '请返回本课练习记录重新选择。',
          ),
        );
      }
      final record = _record(target, saved);
      if (attemptId != null) {
        final attempt = record?.attempts
            .where((a) => a.id == attemptId)
            .firstOrNull;
        if (attempt == null) {
          return view(
            const AppEmptyState(
              icon: Icons.history_outlined,
              title: '该次练习详情暂不可用',
              description: '请返回这个字的练习记录重新选择。',
            ),
          );
        }
        return view(
          _WritingAttemptDetails(
            key: ValueKey(attempt.id),
            target: target,
            attempt: attempt,
          ),
        );
      }
      return view(_characterHistory(context, target, record), target: target);
    }
    final theme = Theme.of(context);
    final countFontSize = theme.textTheme.bodySmall!.fontSize!;
    final textScale =
        (MediaQuery.textScalerOf(context).scale(countFontSize) / countFontSize)
            .clamp(1.0, double.infinity);
    return view(
      LayoutBuilder(
        builder: (context, constraints) {
          final gap = SpacingTokens.sm;
          final available = constraints.maxWidth - SpacingTokens.md * 2;
          final columns = ((available + gap) / (_cardWidth * textScale + gap))
              .floor()
              .clamp(1, _maximumColumns);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: MasonryLayout(
              key: const ValueKey('writing-records-grid'),
              columnCount: columns,
              gap: gap,
              children: [
                for (final target in targets)
                  _recordCard(context, target, saved),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _recordCard(
    BuildContext context,
    WritingTarget target,
    WritingProgress progress,
  ) {
    final theme = Theme.of(context);
    final record = _record(target, progress);
    final counts = [
      ('描红', record?.traceCount ?? 0),
      ('自写', record?.freeCount ?? 0),
      ('拼装', record?.puzzleCount ?? 0),
    ];
    return ColoredCard(
      key: ValueKey('writing-record-${target.id}'),
      color: theme.colorScheme.primary,
      onTap: () => _open(
        context,
        AppRoutes.textbookWritingRecordOf(bookId, lessonId, target.id),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            target.text,
            textAlign: TextAlign.center,
            style: theme.textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          AutoFitLine(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < counts.length; index++) ...[
                  if (index > 0) const SizedBox(width: SpacingTokens.xs),
                  Text(
                    '${counts[index].$1} ${counts[index].$2} 次',
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  WritingRecord? _record(WritingTarget target, WritingProgress progress) {
    final saved =
        progress.records[WritingProgress.targetKey(lessonId, target.id)];
    return saved?.fingerprint == target.fingerprint ? saved : null;
  }

  void _open(BuildContext context, String path) {
    if (ModalRoute.of(context)?.isCurrent == true) context.push<void>(path);
  }

  Widget _characterHistory(
    BuildContext context,
    WritingTarget target,
    WritingRecord? record,
  ) {
    final attempts = (record?.attempts ?? <WritingAttempt>[]).toList()
      ..sort((a, b) {
        final time = b.completedAt.compareTo(a.completedAt);
        return time == 0 ? b.id.compareTo(a.id) : time;
      });
    final total =
        (record?.traceCount ?? 0) +
        (record?.freeCount ?? 0) +
        (record?.puzzleCount ?? 0);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(SpacingTokens.md),
      children: [
        if (attempts.isEmpty)
          AppEmptyState(
            icon: Icons.history_outlined,
            title: total > 0 ? '以前的练习未保存详情' : '还没有练习作品',
            description: total > 0
                ? '原来的次数已保留。新完成的练习会保存时间、用时和作品。'
                : '完成一次描红、自写或拼装后，可在这里回看作品。',
          )
        else ...[
          for (var i = 0; i < attempts.length; i++) ...[
            AppTile(
              key: ValueKey('writing-attempt-${attempts[i].id}'),
              iconColor: theme.colorScheme.primary,
              title:
                  '${_kindLabel(attempts[i].kind)} · ${_time(attempts[i].completedAt)}',
              titleWrap: true,
              subtitle:
                  '用时 ${_duration(attempts[i].durationSeconds)} · '
                  '${attempts[i].puzzle == null ? '${attempts[i].strokes.length} 笔' : '${attempts[i].puzzle!.pieces.length} 块碎片'}',
              flat: true,
              flatLeadingEdgeAligned: true,
              flatTrailingEdgeAligned: true,
              onTap: () => _open(
                context,
                AppRoutes.textbookWritingRecordOf(
                  bookId,
                  lessonId,
                  target.id,
                  attemptId: attempts[i].id,
                ),
              ),
            ),
            if (i + 1 < attempts.length)
              const Divider(height: SpacingTokens.lg),
          ],
          if (total > attempts.length) ...[
            const SizedBox(height: SpacingTokens.sm),
            Text(
              '另有 ${total - attempts.length} 次早期练习未保存详情。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _WritingAttemptDetails extends StatefulWidget {
  const _WritingAttemptDetails({
    super.key,
    required this.target,
    required this.attempt,
  });
  final WritingTarget target;
  final WritingAttempt attempt;

  @override
  State<_WritingAttemptDetails> createState() => _WritingAttemptDetailsState();
}

class _WritingAttemptDetailsState extends State<_WritingAttemptDetails> {
  bool _showPieceBorders = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attempt = widget.attempt;
    final puzzle = attempt.puzzle;
    return ListView(
      padding: const EdgeInsets.all(SpacingTokens.md),
      children: [
        Semantics(
          header: true,
          child: Text(
            '${widget.target.text} · ${_kindLabel(attempt.kind)}',
            style: theme.textTheme.titleLarge,
          ),
        ),
        if (widget.target.pinyin.isNotEmpty) Text(widget.target.pinyin),
        const SizedBox(height: SpacingTokens.md),
        Text(
          '开始 ${_time(attempt.startedAt)}\n'
          '完成 ${_time(attempt.completedAt)}\n'
          '用时 ${_duration(attempt.durationSeconds)}',
        ),
        const SizedBox(height: SpacingTokens.lg),
        Text(
          puzzle == null ? '我的笔迹' : '拼装结果',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: SpacingTokens.sm),
        WritingAttemptPreview(
          attempt: attempt,
          showPieceBorders: _showPieceBorders,
        ),
        const SizedBox(height: SpacingTokens.md),
        if (puzzle == null)
          Text(
            attempt.strokes.isEmpty
                ? '本次没有留下笔迹。'
                : '共 ${attempt.strokes.length} 笔',
          )
        else ...[
          Text(
            '${puzzle.pieces.length} 块碎片已拼好\n'
            '完成时提示：${puzzle.hintEnabled ? '开启' : '关闭'}\n'
            '放置调整 ${puzzle.wrongPlacements} 次',
          ),
          const SizedBox(height: SpacingTokens.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('writing-attempt-pieces-toggle'),
              onPressed: () =>
                  setState(() => _showPieceBorders = !_showPieceBorders),
              icon: Icon(_showPieceBorders ? Icons.grid_off : Icons.grid_on),
              label: Text(_showPieceBorders ? '隐藏碎片' : '查看碎片'),
            ),
          ),
        ],
      ],
    );
  }
}

String _kindLabel(WritingAttemptKind kind) => switch (kind) {
  WritingAttemptKind.trace => '描红',
  WritingAttemptKind.free => '自写',
  WritingAttemptKind.puzzle => '拼装',
};

String _time(DateTime value) =>
    value.toLocal().toIso8601String().substring(0, 19).replaceFirst('T', ' ');

String _duration(int seconds) {
  if (seconds < 60) return '$seconds 秒';
  if (seconds < 3600) return '${seconds ~/ 60} 分 ${seconds % 60} 秒';
  return '${seconds ~/ 3600} 小时 ${seconds % 3600 ~/ 60} 分';
}
