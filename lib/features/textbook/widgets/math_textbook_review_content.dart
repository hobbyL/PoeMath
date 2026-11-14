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
    required this.onLessonActions,
    required this.onBookReview,
  });

  final Textbook book;
  final MathTextbookCourse course;
  final Widget progress;
  final bool running;
  final void Function(MathTextbookLesson) onLesson;
  final void Function(MathTextbookLesson) onLessonActions;
  final VoidCallback onBookReview;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final lessons = {for (final lesson in course.lessons) lesson.id: lesson};
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
          TextbookReviewHeading(
            title: book.title,
            summary: '${book.editionNote} · $approved/${entries.length} 课已通过',
          ),
          progress,
          for (final group in groups.entries) ...[
            TextbookReviewSectionHeader(
              key: ValueKey('math-review-unit-${group.key}'),
              title: group.key,
              summary:
                  '${group.value.where((entry) => entry.lesson?.isApproved(book.pdfSha256) == true).length}/${group.value.length} 课已通过',
            ),
            for (final entry in group.value)
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
                    subtitle:
                        'PDF 第 ${lesson?.startPage ?? entry.range!.startPage}～${lesson?.endPage ?? entry.range!.endPage} 页${pending ? '\n有新整理结果待比较' : ''}',
                    trailingText: lesson == null
                        ? '待整理'
                        : lesson.isApproved(book.pdfSha256)
                        ? '已通过'
                        : '待家长核对',
                    onTap: lesson == null ? null : () => onLesson(lesson),
                    trailingIcon: lesson == null
                        ? Icons.chevron_right
                        : Icons.more_vert,
                    trailingTooltip: '课时更多操作',
                    onTrailingTap: lesson == null || running
                        ? null
                        : () => onLessonActions(lesson),
                  );
                },
              ),
          ],
          const Divider(height: SpacingTokens.xl),
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
