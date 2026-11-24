import 'dart:async';
import 'dart:math' as math;

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
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
import 'package:poemath/features/textbook/providers/textbook_learning_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/textbook_learning_page.dart';

final _englishPageStorage = Provider.family<PageStorageBucket, String>(
  (ref, id) => PageStorageBucket(),
);
final _englishSection = StateProvider.family<String, String>((ref, id) {
  final value = HiveBoxes.settings.get('${id}_english_section_v1');
  return value is String && ['books', 'practice', 'review'].contains(value)
      ? value
      : 'books';
});

class EnglishTabPage extends ConsumerStatefulWidget {
  const EnglishTabPage({super.key, this.section});
  final String? section;
  @override
  ConsumerState<EnglishTabPage> createState() => _EnglishTabPageState();
}

class _EnglishTabPageState extends ConsumerState<EnglishTabPage> {
  late String _section;
  late final StreamSubscription<String> _profiles;
  String _saved() => ref.read(_englishSection(ProfileScope.currentId));
  @override
  void initState() {
    super.initState();
    _section = ['books', 'practice', 'review'].contains(widget.section)
        ? widget.section!
        : _saved();
    _profiles = ProfileScope.changes.listen((_) {
      if (mounted) setState(() => _section = _saved());
    });
  }

  @override
  void didUpdateWidget(EnglishTabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.section != oldWidget.section &&
        ['books', 'practice', 'review'].contains(widget.section)) {
      _section = widget.section!;
    }
  }

  @override
  void dispose() {
    unawaited(_profiles.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dayKeyProvider);
    final selected = _section;
    final scaler = MediaQuery.textScalerOf(context);
    final labelStyle = Theme.of(context).textTheme.labelLarge!;
    final labelHeight =
        scaler.scale(labelStyle.fontSize!) * (labelStyle.height ?? 1);
    final toolbarHeight = math.max(
      kToolbarHeight,
      labelHeight + SpacingTokens.sm * 4,
    );
    final title = SegmentedButton<String>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(0, SpacingTokens.xxl),
        padding: const EdgeInsets.all(SpacingTokens.sm),
      ),
      segments: const [
        ButtonSegment(
          value: 'books',
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('课本', maxLines: 1),
          ),
        ),
        ButtonSegment(
          value: 'practice',
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('练习', maxLines: 1),
          ),
        ),
        ButtonSegment(
          value: 'review',
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('复习', maxLines: 1),
          ),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (v) async {
        setState(() => _section = v.single);
        ref.read(_englishSection(ProfileScope.currentId).notifier).state =
            v.single;
        final key = ProfileScope.key('english_section_v1');
        context.go(AppRoutes.englishSectionOf(v.single));
        try {
          await HiveBoxes.settings.put(key, v.single);
        } on Object {
          if (context.mounted) {
            englishMessage(context, StateError('栏目偏好暂未保存'));
          }
        }
      },
    );
    if (selected == 'books') {
      return PageStorage(
        bucket: ref.watch(_englishPageStorage(ProfileScope.currentId)),
        child: TextbookLearningPage(
          subject: TextbookSubject.english,
          navigationTitle: title,
          navigationToolbarHeight: toolbarHeight,
        ),
      );
    }
    final books = ref.watch(subjectTextbooksProvider(TextbookSubject.english));
    return AppScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: title,
        centerTitle: true,
        toolbarHeight: toolbarHeight,
      ),
      body: SafeArea(
        top: false,
        child: PageStorage(
          bucket: ref.watch(_englishPageStorage(ProfileScope.currentId)),
          child: ListView(
            key: PageStorageKey('english-$selected-${ProfileScope.currentId}'),
            padding: const EdgeInsets.all(SpacingTokens.md),
            children: [
              if (books.isEmpty)
                const AppEmptyState(
                  icon: Icons.menu_book_outlined,
                  title: '还没有当前年级的英语课本',
                  description: '请家长在书籍管理添加英语教材。',
                ),
              if (selected == 'review')
                for (final progress
                    in ref
                        .watch(englishSavedProgressProvider)
                        .where(
                          (p) => !ref
                              .watch(textbookListProvider)
                              .any((b) => b.pdfSha256 == p.bookId),
                        ))
                  AppTile(
                    icon: Icons.history,
                    iconColor: Theme.of(context).colorScheme.primary,
                    title: progress.attempts.lastOrNull?.title ?? '已恢复的英语记录',
                    subtitle: '${progress.attempts.length} 次已保存 · 需重新下载原书',
                    onTap: () => context.push(
                      AppRoutes.englishBookOf(
                        progress.bookId,
                        action: 'history',
                      ),
                    ),
                  ),
              for (final book in books) ...[
                if (book != books.first)
                  const SizedBox(height: SpacingTokens.md),
                _EnglishBookEntry(book: book, review: selected == 'review'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EnglishBookEntry extends ConsumerWidget {
  const _EnglishBookEntry({required this.book, required this.review});
  final Textbook book;
  final bool review;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(englishCourseProvider(book.pdfSha256));
    final p = ref.watch(englishProgressProvider(book.pdfSha256));
    final c = course.valueOrNull;
    final count = c == null || !review
        ? 0
        : ref
              .watch(englishProgressRepositoryProvider(book.pdfSha256))!
              .dueKeys(c, DateTime.now())
              .length;
    return AppTileGroup(
      children: [
        AppTile(
          icon: review ? Icons.event_repeat : Icons.extension_outlined,
          iconColor: Theme.of(context).colorScheme.primary,
          title: review ? '今日复习 · $count 项' : '选择练习',
          subtitle: c == null
              ? '先整理并核对课本'
              : review
              ? '按题型进入复习'
              : '继续上次练习',
          onTap: () => context.push(
            AppRoutes.englishBookOf(
              book.pdfSha256,
              action: 'practice',
              due: review,
            ),
          ),
        ),
        if (review)
          AppTile(
            icon: Icons.replay,
            iconColor: Theme.of(context).colorScheme.primary,
            title: '错题再练',
            subtitle: '含提示题和家长标记',
            onTap: () => context.push(
              AppRoutes.englishBookOf(
                book.pdfSha256,
                action: 'practice',
                retry: true,
              ),
            ),
          ),
        AppTile(
          icon: Icons.history,
          iconColor: Theme.of(context).colorScheme.primary,
          title: '学习与跟读记录',
          subtitle: '${p?.attempts.length ?? 0} 次已保存',
          onTap: () => context.push(
            AppRoutes.englishBookOf(book.pdfSha256, action: 'history'),
          ),
        ),
      ],
    );
  }
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
