import 'package:flutter/material.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/features/textbook/widgets/textbook_review_layout.dart';

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
    final retainedIds = course.outline?.retainedLessonIds.toSet() ?? <String>{};
    final retained = course.lessons
        .where((lesson) => retainedIds.contains(lesson.id))
        .toList();
    final entries =
        <({MathTextbookCourseRange? range, MathTextbookLesson? lesson})>[
          for (final range
              in course.outline?.ranges ?? <MathTextbookCourseRange>[])
            (range: range, lesson: lessons.remove(range.lessonId)),
          for (final lesson in lessons.values) (range: null, lesson: lesson),
        ];
    final groups =
        <
          String,
          List<({MathTextbookCourseRange? range, MathTextbookLesson? lesson})>
        >{};
    for (final entry in entries) {
      final unit = entry.lesson?.learning?.unitTitle.trim();
      final title = unit != null && unit.isNotEmpty
          ? unit
          : entry.range?.unitTitle.trim() ?? '';
      (groups[title.isEmpty ? '待确认归属的内容' : title] ??= []).add(entry);
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
                    .where(
                      (entry) =>
                          (entry.lesson?.title ?? entry.range!.title).trim() ==
                          group.key,
                    )
                    .toList();
                final merged = matching.length == 1 ? matching.single : null;
                final mergedLesson = merged?.lesson;
                final saved = [
                  for (final entry in group.value)
                    if (entry.lesson != null) entry.lesson!,
                ];
                final mergedPending =
                    merged != null &&
                    course.pendingLessons.any(
                      (lesson) => lesson.id == mergedLesson?.id,
                    );
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
                                  ? '有新整理结果待比较'
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
                            final pending = course.pendingLessons.any(
                              (lesson) => lesson.id == id,
                            );
                            return AppTile(
                              key: ValueKey('math-review-lesson-$id'),
                              flat: true,
                              flatTrailingEdgeAligned: true,
                              iconColor: color,
                              title: lesson?.title ?? entry.range!.title,
                              subtitle: pending ? '有新整理结果待比较' : '',
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
