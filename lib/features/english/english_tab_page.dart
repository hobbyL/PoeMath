import 'package:poemath/core/utils/profile_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/domain/english_practice.dart';
import 'package:poemath/features/english/english_providers.dart';
import 'package:poemath/features/english/english_widgets.dart';
import 'package:poemath/features/home/providers/home_providers.dart'
    show dayKeyProvider;
import 'package:poemath/features/textbook/textbook_learning_page.dart';

final _englishPageStorage = Provider.family<PageStorageBucket, String>(
  (ref, id) => PageStorageBucket(),
);

class EnglishTabPage extends ConsumerWidget {
  const EnglishTabPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PageStorage(
    bucket: ref.watch(_englishPageStorage(ProfileScope.currentId)),
    child: const TextbookLearningPage(
      subject: TextbookSubject.english,
      centerTitle: true,
    ),
  );
}

class EnglishPracticeHubPage extends ConsumerWidget {
  const EnglishPracticeHubPage({
    super.key,
    required this.bookId,
    this.lessonId,
    this.due = false,
    this.retry = false,
    this.targetKey,
  });
  final String bookId;
  final String? lessonId;
  final bool due, retry;
  final String? targetKey;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dayKeyProvider);
    final voice = ref.watch(englishVoiceProvider), theme = Theme.of(context);
    ref.watch(englishProgressProvider(bookId));
    return AppScaffold(
      appBar: AppBar(
        title: Text(
          due
              ? '到期复习'
              : retry
              ? '再练一遍'
              : '英语练习',
        ),
      ),
      body: SafeArea(
        top: false,
        child: EnglishCourseBody(
          bookId: bookId,
          builder: (_, course) {
            final repository = ref.watch(
              englishProgressRepositoryProvider(bookId),
            )!;
            final keys = targetKey != null
                ? {targetKey!}
                : due
                ? repository.dueKeys(course, DateTime.now())
                : retry
                ? repository.retryKeys(course)
                : null;
            final questionsByKind = {
              for (final kind in EnglishPracticeKind.values)
                kind: buildEnglishQuestions(
                  course,
                  kind,
                  lessonId: lessonId,
                  targetKeys: keys,
                  voiceKey: voice == null ? null : englishVoiceKey(voice),
                ),
            };
            return ListView(
              padding: const EdgeInsets.all(SpacingTokens.md),
              children: [
                if (lessonId != null) ...[
                  Text(
                    '${course.lesson(lessonId!)?.unitTitle ?? ''} · ${course.lesson(lessonId!)?.title ?? ''}',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: SpacingTokens.md),
                ],
                AppTileGroup(
                  children: [
                    for (final kind in EnglishPracticeKind.values)
                      AppTile(
                        icon: Icons.extension_outlined,
                        iconColor: theme.colorScheme.primary,
                        title: kind.label,
                        subtitle: questionsByKind[kind]!.isEmpty
                            ? (kind == EnglishPracticeKind.listening
                                  ? '需核对词语和英语示范'
                                  : '暂无可练题目')
                            : '${questionsByKind[kind]!.length} 项可练',
                        trailing: questionsByKind[kind]!.isEmpty
                            ? const SizedBox.shrink()
                            : null,
                        onTap: questionsByKind[kind]!.isEmpty
                            ? null
                            : () => context.push(
                                AppRoutes.englishBookOf(
                                  bookId,
                                  action: 'practice',
                                  kind: kind.name,
                                  lesson: lessonId,
                                  due: due,
                                  retry: retry,
                                  targetKey: targetKey,
                                ),
                              ),
                      ),
                  ],
                ),
                if (keys != null) ...[
                  englishHeading(context, '本次复习内容'),
                  AppTileGroup(
                    children: [
                      for (final kind in EnglishPracticeKind.values)
                        for (final q in questionsByKind[kind]!)
                          AppTile(
                            icon: Icons.replay,
                            iconColor: theme.colorScheme.primary,
                            title: q.target.text,
                            titleMaxLines: 3,
                            subtitle:
                                '${course.lesson(q.lessonId)?.title} · ${kind.label}',
                            onTap: () => context.push(
                              AppRoutes.englishBookOf(
                                bookId,
                                action: 'practice',
                                kind: kind.name,
                                lesson: q.lessonId,
                                due: due,
                                retry: retry,
                                targetKey: q.recordKey,
                              ),
                            ),
                          ),
                    ],
                  ),
                ],
                TextButton(
                  onPressed: () => context.push(
                    AppRoutes.englishBookOf(bookId, review: true),
                  ),
                  child: const Text('家长整理课程'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
