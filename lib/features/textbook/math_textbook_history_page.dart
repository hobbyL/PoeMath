import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_progress.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/domain/math_textbook_practice.dart';
import 'package:poemath/features/textbook/math_textbook_labels.dart';
import 'package:poemath/features/textbook/providers/math_textbook_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_study_content.dart';

class MathTextbookHistoryPage extends ConsumerWidget {
  const MathTextbookHistoryPage({
    super.key,
    required this.bookId,
    this.parent = false,
  });
  final String bookId;
  final bool parent;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref
        .watch(textbookLocalListProvider)
        .where(
          (b) => b.pdfSha256 == bookId && b.subject == TextbookSubject.math,
        )
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(parent ? '作答记录与家长核对' : '本书学习记录')),
      body: SafeArea(
        child: book == null
            ? const AppEmptyState(
                icon: Icons.history_outlined,
                title: '本书已移除',
                description: '已结算的自动练习记录仍可在数学练习记录中查看。',
              )
            : ref
                  .watch(mathTextbookProgressProvider(bookId))
                  .when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => AppEmptyState(
                      icon: Icons.error_outline,
                      title: '记录暂时无法读取',
                      description: mathTextbookDisplayError(error, '请稍后重试。'),
                      actions: [
                        TextButton(
                          onPressed: () => ref.invalidate(
                            mathTextbookProgressProvider(bookId),
                          ),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                    data: (progress) {
                      if (progress == null || progress.history.isEmpty) {
                        return const AppEmptyState(
                          icon: Icons.history_outlined,
                          title: '还没有本书作答',
                          description: '完成原题或巩固后，作答和核对结果会保存在这里。',
                        );
                      }
                      final course = ref
                          .watch(mathTextbookCourseProvider(bookId))
                          .valueOrNull;
                      bool currentAttempt(MathTextbookAttempt attempt) {
                        final lesson = course?.lessons
                            .where((lesson) => lesson.id == attempt.lessonId)
                            .firstOrNull;
                        return lesson?.isApproved(bookId) == true &&
                            _currentTarget(lesson!, attempt) &&
                            progress.targets[attempt.targetKey]?.attemptId ==
                                attempt.id;
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(SpacingTokens.md),
                        itemCount: progress.history.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ColoredCard(
                                  color: Theme.of(context).colorScheme.primary,
                                  child: Text(
                                    '${book.title} · ${book.volumeLabel}\n最近 ${progress.history.length} 次作答 · ${progress.history.where((a) => a.result == MathTextbookResult.pendingParent && currentAttempt(a)).length} 次待家长核对\n详细记录保留最近 300 次，累计学习进度继续保留。',
                                  ),
                                ),
                                if (!parent)
                                  TextButton(
                                    onPressed: () => context.push(
                                      AppRoutes.mathTextbookHistoryOf(
                                        bookId,
                                        parent: true,
                                      ),
                                    ),
                                    child: const Text('请家长核对开放题'),
                                  ),
                                const SizedBox(height: SpacingTokens.md),
                              ],
                            );
                          }
                          final attempt = progress.history[index - 1];
                          final current = currentAttempt(attempt);
                          final time = attempt.createdAt.toLocal();
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: SpacingTokens.sm,
                            ),
                            child: AppTile(
                              icon: Icons.assignment_outlined,
                              iconColor: Theme.of(context).colorScheme.primary,
                              title: attempt.item.exercise.title,
                              subtitle:
                                  '${attempt.lessonTitle} · ${attempt.planId == null ? '教材原题' : '本课巩固'}\n${mathTextbookResultLabel(attempt.result)}${current ? '' : ' · 历史作答'} · ${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                              onTap: () => Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) {
                                    final page = _MathTextbookAttemptPage(
                                      book: book,
                                      attempt: attempt,
                                      current: current,
                                      parent: parent,
                                    );
                                    return parent
                                        ? ParentAccessBoundary(child: page)
                                        : page;
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
      ),
    );
  }
}

bool _currentTarget(MathTextbookLesson lesson, MathTextbookAttempt attempt) {
  try {
    return mathTextbookTargetDigest(
          lesson,
          attempt.planId,
          attempt.item.exercise.id,
        ) ==
        attempt.scopeDigest;
  } on FormatException {
    return false;
  }
}

class _MathTextbookAttemptPage extends ConsumerStatefulWidget {
  const _MathTextbookAttemptPage({
    required this.book,
    required this.attempt,
    required this.current,
    required this.parent,
  });
  final Textbook book;
  final MathTextbookAttempt attempt;
  final bool current, parent;
  @override
  ConsumerState<_MathTextbookAttemptPage> createState() =>
      _MathTextbookAttemptPageState();
}

class _MathTextbookAttemptPageState
    extends ConsumerState<_MathTextbookAttemptPage> {
  late MathTextbookAttempt _attempt = widget.attempt;
  final int _profileRevision = ProfileScope.revision;
  bool _saving = false;
  String? _error;
  Future<void> _check(bool passed) async {
    if (_saving) return;
    final reviewer = TextEditingController(text: '家长');
    try {
      if (ProfileScope.revision != _profileRevision) {
        throw StateError('孩子档案已切换，请重新打开核对记录');
      }
      assertParentAccess(context);
      final authorize = ParentAccessService.instance.captureAuthorization();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(passed ? '确认这份作答已完成？' : '建议孩子再练？'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('请对照原书和孩子纸上的作答核对。这个结果会单独保存为家长核对。'),
                const SizedBox(height: SpacingTokens.md),
                TextField(
                  controller: reviewer,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: '核对人'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('保存核对结果'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      setState(() {
        _saving = true;
        _error = null;
      });
      void check() {
        authorize();
        assertParentAccess(context);
      }

      final progress = await ref
          .read(mathTextbookLearningRepositoryProvider(widget.book.pdfSha256))!
          .parentCheck(
            attemptId: _attempt.id,
            passed: passed,
            reviewer: reviewer.text.trim(),
            authorize: check,
          );
      if (!mounted) return;
      setState(
        () =>
            _attempt = progress.history.firstWhere((a) => a.id == _attempt.id),
      );
      ref.invalidate(mathTextbookProgressProvider(widget.book.pdfSha256));
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = mathTextbookDisplayError(error, '核对未保存，请重新解锁后重试。'),
        );
      }
    } finally {
      reviewer.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _attempt.item;
    return Scaffold(
      appBar: AppBar(title: const Text('作答详情')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SpacingTokens.md),
          children: [
            Text(
              item.exercise.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(_attempt.lessonTitle),
            Text(mathTextbookResultLabel(_attempt.result)),
            if (!widget.current) const Text('已有新作答或课程已更新：这里保留的是当时的原题与答案规则。'),
            if (_attempt.parentReviewer != null)
              Text(
                '核对人：${_attempt.parentReviewer} · ${_attempt.parentReviewedAt!.toLocal().toString().split('.').first}',
              ),
            const SizedBox(height: SpacingTokens.md),
            for (final block in item.blocks)
              Padding(
                padding: const EdgeInsets.only(bottom: SpacingTokens.md),
                child: MathTextbookStudyContent(
                  book: widget.book,
                  block: block,
                ),
              ),
            if (item.exercise.note.isNotEmpty) Text(item.exercise.note),
            for (final field in item.exercise.fields)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
                child: ColoredCard(
                  color: Theme.of(context).colorScheme.primary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        field.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('你的作答：${_attempt.answers[field.id] ?? ''}'),
                      Text(
                        _attempt.fieldResults[field.id] == null
                            ? '此项由家长核对'
                            : _attempt.fieldResults[field.id]!
                            ? '自动核对通过'
                            : '自动核对未通过',
                      ),
                      if (field.rule.kind != MathTextbookAnswerKind.parent)
                        Text(
                          '参考答案：${field.rule.kind == MathTextbookAnswerKind.choice ? field.rule.correctChoices.join('、') : '${field.rule.expected}${MathTextbookUnits.label(field.rule.unit)}'}',
                        ),
                      if (field.rule.reference.isNotEmpty)
                        Text('核对要点：${field.rule.reference}'),
                    ],
                  ),
                ),
              ),
            if (_error != null)
              ColoredCard(
                color: Theme.of(context).colorScheme.error,
                child: Text(_error!),
              ),
            if (widget.parent &&
                widget.current &&
                item.exercise.needsParent) ...[
              const SizedBox(height: SpacingTokens.md),
              FilledButton(
                onPressed:
                    _saving ||
                        _attempt.fieldResults.values.any((v) => v == false)
                    ? null
                    : () => _check(true),
                child: Text(_saving ? '正在保存…' : '家长确认完成'),
              ),
              OutlinedButton(
                onPressed: _saving ? null : () => _check(false),
                child: const Text('建议再练一次'),
              ),
            ],
            if (!widget.parent && item.exercise.needsParent)
              TextButton(
                onPressed: () => context.push(
                  AppRoutes.mathTextbookHistoryOf(
                    widget.book.pdfSha256,
                    parent: true,
                  ),
                ),
                child: const Text('请家长核对'),
              ),
            if (widget.current && !widget.parent)
              OutlinedButton(
                onPressed: () => context.push(
                  AppRoutes.mathTextbookPracticeOf(
                    widget.book.pdfSha256,
                    _attempt.lessonId,
                    planId: _attempt.planId,
                  ),
                ),
                child: Text(_attempt.planId == null ? '重新练本课原题' : '重新练本课巩固'),
              ),
          ],
        ),
      ),
    );
  }
}
