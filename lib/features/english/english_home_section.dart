import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/features/english/english_providers.dart';
import 'package:poemath/features/home/home_section.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

class EnglishHomeSection extends ConsumerWidget {
  const EnglishHomeSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dayKeyProvider);
    ref.watch(englishDraftChangesProvider);
    final drafts = PracticeDraftRepository();
    final entries = <Widget>[], theme = Theme.of(context);
    final books = ref
        .watch(textbookListProvider)
        .where((b) => b.subject == TextbookSubject.english);
    for (final book in books) {
      final progress = ref.watch(englishProgressProvider(book.pdfSha256)),
          course = ref.watch(englishCourseProvider(book.pdfSha256)).valueOrNull;
      if (course == null || progress == null) continue;
      for (final kind in ['englishPractice', 'englishSpeaking']) {
        for (final scope
            in drafts
                .scopes(kind)
                .where((s) => s.startsWith('${book.pdfSha256}/'))) {
          try {
            final draft = drafts.get(kind, scope: scope);
            if (draft == null) continue;
            final practice = kind == 'englishPractice';
            final lesson = practice
                ? draft['lessonId'] as String?
                : scope.substring(book.pdfSha256.length + 1);
            entries.add(
              AppTile(
                icon: practice ? Icons.edit_note : Icons.mic_none,
                iconColor: theme.colorScheme.primary,
                title: practice ? '继续练习' : '继续跟读',
                subtitle:
                    '${book.volumeLabel} · ${lesson == null ? '全书练习' : course.lesson(lesson)?.title ?? '原课时'}',
                onTap: () => context.push(
                  AppRoutes.englishBookOf(
                    book.pdfSha256,
                    action: practice ? 'practice' : 'speaking',
                    lesson: lesson,
                    kind: practice ? draft['practiceKind'] as String? : null,
                    due: draft['due'] == true,
                    retry: draft['retry'] == true,
                    targetKey: draft['targetKey'] as String?,
                  ),
                ),
              ),
            );
            break;
          } on Object {
            /* 不展示无法恢复的草稿。 */
          }
        }
      }
      final last = progress.lastLessonId == null
          ? null
          : course.lesson(progress.lastLessonId!);
      final due = ref
          .watch(englishProgressRepositoryProvider(book.pdfSha256))!
          .dueKeys(course, DateTime.now())
          .length;
      if (last != null) {
        entries.add(
          AppTile(
            icon: Icons.auto_stories_outlined,
            iconColor: theme.colorScheme.primary,
            title: '继续学习',
            titleMaxLines: 1,
            subtitle: '${book.volumeLabel} · ${last.unitTitle} · ${last.title}',
            onTap: () => context.push(
              AppRoutes.englishBookOf(book.pdfSha256, lesson: last.id),
            ),
          ),
        );
      }
      if (due > 0) {
        entries.add(
          AppTile(
            icon: Icons.event_repeat,
            iconColor: theme.colorScheme.primary,
            title: '到期复习 · $due 项',
            titleMaxLines: 1,
            subtitle: book.volumeLabel,
            onTap: () => context.push(
              AppRoutes.englishBookOf(
                book.pdfSha256,
                action: 'practice',
                due: true,
              ),
            ),
          ),
        );
      }
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeSectionHeading('英语学习'),
        const SizedBox(height: SpacingTokens.sm),
        HomeEntryGroup(children: entries),
        const SizedBox(height: SpacingTokens.lg),
      ],
    );
  }
}
