import 'package:flutter/material.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/features/textbook/widgets/textbook_review_layout.dart';

const _unassignedMathTextbookUnit = '待确认归属的内容';
typedef _MathTextbookReviewEntry = ({
  MathTextbookCourseRange? range,
  MathTextbookLesson? lesson,
  MathTextbookLesson? candidate,
});

class MathTextbookReviewContent extends StatelessWidget {
  const MathTextbookReviewContent({
    super.key,
    required this.book,
    required this.course,
    required this.progress,
    required this.running,
    required this.onLesson,
    required this.onUnitActions,
    required this.onBookReview,
  });

  final Textbook book;
  final MathTextbookCourse course;
  final Widget progress;
  final bool running;
  final void Function(MathTextbookLesson) onLesson;
  final void Function(List<MathTextbookLesson>) onUnitActions;
  final VoidCallback onBookReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    final lessons = {
      for (final lesson in course.currentLessons) lesson.id: lesson,
    };
    final candidates = {
      for (final lesson in course.pendingLessons) lesson.id: lesson,
    };
    final retainedIds = course.outline?.retainedLessonIds.toSet() ?? <String>{};
    final retained = course.lessons
        .where((lesson) => retainedIds.contains(lesson.id))
        .toList();
    final entries = <_MathTextbookReviewEntry>[
      for (final range in course.outline?.ranges ?? <MathTextbookCourseRange>[])
        (
          range: range,
          lesson: lessons.remove(range.lessonId),
          candidate: candidates[range.lessonId],
        ),
      for (final lesson in lessons.values)
        (range: null, lesson: lesson, candidate: candidates[lesson.id]),
    ];
    final groups = <String, List<_MathTextbookReviewEntry>>{};
    String entryTitle(_MathTextbookReviewEntry entry) =>
        entry.candidate?.title ?? entry.lesson?.title ?? entry.range!.title;
    String entryUnit(_MathTextbookReviewEntry entry) {
      if (entry.candidate != null) {
        final proposed = entry.candidate!.learning?.unitTitle.trim() ?? '';
        return proposed.isNotEmpty
            ? proposed
            : entry.range?.unitTitle.trim() ?? '';
      }
      final current = entry.lesson?.learning?.unitTitle.trim();
      return current != null && current.isNotEmpty
          ? current
          : entry.range?.unitTitle.trim() ?? '';
    }

    String pendingSubtitle(_MathTextbookReviewEntry entry) {
      final candidate = entry.candidate;
      if (candidate == null) return '';
      final details = <String>[];
      final current = entry.lesson;
      final currentTitle = current?.title.trim() ?? '';
      if (currentTitle.isNotEmpty && currentTitle != candidate.title.trim()) {
        details.add('当前草稿：$currentTitle');
      }
      final currentUnit = current?.learning?.unitTitle.trim() ?? '';
      final proposedUnit = candidate.learning?.unitTitle.trim() ?? '';
      if (currentUnit.isNotEmpty && currentUnit != proposedUnit) {
        details.add('原单元：$currentUnit');
      }
      return ['有新整理结果待比较', ...details].join(' · ');
    }

    for (final entry in entries) {
      final title = entryUnit(entry);
      (groups[title.isEmpty ? _unassignedMathTextbookUnit : title] ??= []).add(
        entry,
      );
    }
    final approved = entries
        .where((entry) => entry.lesson?.isApproved(book.pdfSha256) == true)
        .length;
    return SafeArea(
      child: ListView(
        key: PageStorageKey('math-review-${book.pdfSha256}'),
        padding: const EdgeInsets.all(SpacingTokens.md),
        children: [
          progress,
          for (final group in groups.entries)
            Builder(
              builder: (context) {
                final matching = group.value
                    .where((entry) => entryTitle(entry).trim() == group.key)
                    .toList();
                final merged = matching.length == 1 ? matching.single : null;
                final mergedLesson = merged?.lesson;
                final saved = [
                  for (final entry in group.value)
                    if (entry.lesson != null) entry.lesson!,
                ];
                final mergedPending = merged?.candidate != null;
                final summary =
                    '${group.value.where((entry) => entry.lesson?.isApproved(book.pdfSha256) == true).length}/${group.value.length} 课已通过';
                final showDivider = group.key != groups.keys.first;
                final menuEnabled = !running && saved.isNotEmpty;
                return Column(
                  key: ValueKey('math-review-unit-${group.key}'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showDivider) const Divider(height: SpacingTokens.xs),
                    LayoutBuilder(
                      builder: (context, constraints) => Row(
                        children: [
                          Expanded(
                            child: AppTile(
                              key: merged != null
                                  ? ValueKey(
                                      'math-review-lesson-${mergedLesson?.id ?? merged.range!.lessonId}',
                                    )
                                  : null,
                              flat: true,
                              flatLeadingEdgeAligned: true,
                              flatTrailingEdgeAligned: true,
                              allowTapWithTrailing: true,
                              iconColor: color,
                              title: group.key,
                              titleWrap: true,
                              subtitle: merged != null && mergedLesson == null
                                  ? '待整理'
                                  : mergedPending
                                  ? pendingSubtitle(merged!)
                                  : '',
                              trailing: const SizedBox.shrink(),
                              onTap: mergedLesson != null
                                  ? () => onLesson(mergedLesson)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: SpacingTokens.sm),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth:
                                  constraints.maxWidth / 2 - SpacingTokens.sm,
                            ),
                            child: Tooltip(
                              message: '课时更多操作',
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor:
                                      theme.colorScheme.onSurfaceVariant,
                                  disabledForegroundColor:
                                      theme.colorScheme.onSurfaceVariant,
                                  textStyle: theme.textTheme.bodySmall,
                                  minimumSize: const Size(
                                    SpacingTokens.minTapTarget,
                                    SpacingTokens.minTapTarget,
                                  ),
                                  padding: EdgeInsets.zero,
                                  alignment: AlignmentDirectional.centerEnd,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: menuEnabled
                                    ? () => onUnitActions(saved)
                                    : null,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        summary,
                                        textAlign: TextAlign.end,
                                      ),
                                    ),
                                    const SizedBox(width: SpacingTokens.xs),
                                    Icon(
                                      Icons.more_vert,
                                      size: SpacingTokens.lg,
                                      color: menuEnabled
                                          ? null
                                          : theme.colorScheme.onSurface
                                                .withValues(alpha: .38),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final entry in group.value)
                      if (entry != merged)
                        Builder(
                          builder: (context) {
                            final lesson = entry.lesson;
                            final id = lesson?.id ?? entry.range!.lessonId;
                            return AppTile(
                              key: ValueKey('math-review-lesson-$id'),
                              flat: true,
                              flatLeadingEdgeAligned:
                                  group.key == _unassignedMathTextbookUnit,
                              flatTrailingEdgeAligned: true,
                              iconColor: color,
                              title: entryTitle(entry),
                              subtitle: pendingSubtitle(entry),
                              trailingText: lesson == null
                                  ? '待整理'
                                  : lesson.isApproved(book.pdfSha256)
                                  ? '已通过'
                                  : null,
                              onTap: lesson == null
                                  ? null
                                  : () => onLesson(lesson),
                            );
                          },
                        ),
                  ],
                );
              },
            ),
          if (retained.isNotEmpty) ...[
            if (groups.isNotEmpty) const Divider(height: SpacingTokens.xs),
            const TextbookReviewSectionHeader(
              title: '保留的原课时',
              showDivider: false,
              summary: '目录已重新划分，可打开原稿对照；历史记录仍保留。',
            ),
            for (final lesson in retained)
              AppTile(
                key: ValueKey('math-retained-lesson-${lesson.id}'),
                flat: true,
                flatTrailingEdgeAligned: true,
                iconColor: color,
                title: lesson.title,
                subtitle: '',
                onTap: () => onLesson(lesson),
              ),
          ],
          if (entries.isNotEmpty || retained.isNotEmpty)
            const Divider(height: SpacingTokens.xs),
          AppTile(
            flat: true,
            flatTrailingEdgeAligned: true,
            iconColor: color,
            title: '整书核对',
            subtitle: entries.isNotEmpty && approved == entries.length
                ? '本书课时均已审核'
                : '还有 ${entries.length - approved} 课待整理或审核',
            onTap: onBookReview,
          ),
        ],
      ),
    );
  }
}
