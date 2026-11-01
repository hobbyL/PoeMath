import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_exercise_progress.dart';
import 'package:poemath/data/repositories/textbook_exercise_repository.dart';
import 'package:poemath/domain/textbook_exercise.dart';
import 'package:poemath/features/textbook/exercise/exercise_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/textbook_exercise_prompt.dart';

class TextbookExerciseOverview extends ConsumerStatefulWidget {
  const TextbookExerciseOverview({
    super.key,
    required this.bookId,
    required this.lesson,
    required this.exercises,
  });

  final String bookId;
  final TextbookCourseLesson lesson;
  final List<TextbookCourseExercise> exercises;

  @override
  ConsumerState<TextbookExerciseOverview> createState() =>
      _TextbookExerciseOverviewState();
}

class _TextbookExerciseOverviewState
    extends ConsumerState<TextbookExerciseOverview> {
  final Map<String, Set<String>> _selectedChoices = {};
  final Map<String, List<TextEditingController>> _blankControllers = {};
  String? _busyExerciseId;

  @override
  void initState() {
    super.initState();
    _resetDrafts();
  }

  @override
  void didUpdateWidget(covariant TextbookExerciseOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = oldWidget.lesson.id != widget.lesson.id ||
        oldWidget.exercises.length != widget.exercises.length ||
        oldWidget.exercises.indexed.any(
          (entry) =>
              entry.$2.contentDigest !=
              widget.exercises[entry.$1].contentDigest,
        );
    if (!changed) return;
    for (final controllers in _blankControllers.values) {
      for (final controller in controllers) {
        controller.dispose();
      }
    }
    _selectedChoices.clear();
    _blankControllers.clear();
    _resetDrafts();
  }

  void _resetDrafts() {
    for (final exercise in widget.exercises) {
      _selectedChoices[exercise.id] = <String>{};
      _blankControllers[exercise.id] = [
        for (final _ in exercise.fillBlanks) TextEditingController(),
      ];
    }
  }

  @override
  void dispose() {
    for (final controllers in _blankControllers.values) {
      for (final controller in controllers) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = ref.watch(textbookExerciseProgressProvider(widget.bookId));
    return progress.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text('习题进度加载失败：$error'),
      data: (value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, exercise) in widget.exercises.indexed) ...[
            if (index > 0) const SizedBox(height: SpacingTokens.md),
            ColoredCard(
              key: ValueKey(
                'textbook-exercise-${widget.lesson.id}-${exercise.id}',
              ),
              color: theme.colorScheme.primary,
              padding: EdgeInsets.only(
                left: SpacingTokens.md,
                right: SpacingTokens.md,
                top: exercise.questionType == TextbookExerciseQuestionType.oral
                    ? SpacingTokens.xs
                    : SpacingTokens.md,
                bottom: SpacingTokens.md,
              ),
              child: _exercise(
                context,
                exercise,
                value?.records[TextbookExerciseProgress.targetKey(
                  widget.lesson.id,
                  exercise.id,
                )],
                value,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _exercise(
    BuildContext context,
    TextbookCourseExercise exercise,
    TextbookExerciseRecord? record,
    TextbookExerciseProgress? progress,
  ) {
    final theme = Theme.of(context);
    final choiceMode = exercise.choiceMode;
    final busy = _busyExerciseId == exercise.id;
    final oral = exercise.questionType == TextbookExerciseQuestionType.oral;
    final prompt = TextbookExercisePrompt(
      exercise: exercise,
      showHeading: !oral,
    );
    final heading = oral ? prompt.heading : null;
    final title = oral
        ? heading == null
            ? TextbookExercisePrompt(exercise: exercise)
            : SelectableText(heading, style: theme.textTheme.titleMedium)
        : Text(
            exercise.questionType.label,
            style: theme.textTheme.titleMedium,
          );
    const oralButtonStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(SpacingTokens.minTapTarget, SpacingTokens.minTapTarget),
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: SpacingTokens.sm),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (oral)
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: title),
              const SizedBox(width: SpacingTokens.sm),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  TextButton(
                    style: oralButtonStyle,
                    onPressed: busy ? null : () => _submit(exercise, progress),
                    child: const Text('完成', textAlign: TextAlign.center),
                  ),
                  if (record?.lastResult ==
                      TextbookExerciseResult.parentPending) ...[
                    const SizedBox(width: SpacingTokens.xs),
                    TextButton(
                      style: oralButtonStyle,
                      onPressed: busy
                          ? null
                          : () => _parentCheck(exercise, progress, record),
                      child: const Text('核对', textAlign: TextAlign.center),
                    ),
                  ],
                ],
              ),
            ],
          )
        else
          title,
        if ((!oral || heading != null) && prompt.hasContent) ...[
          const SizedBox(height: SpacingTokens.sm),
          prompt,
        ],
        const SizedBox(height: SpacingTokens.xs),
        Text(
          _answerHint(exercise),
          style: theme.textTheme.bodySmall,
        ),
        if (!oral) const SizedBox(height: SpacingTokens.sm),
        if (exercise.questionType == TextbookExerciseQuestionType.choice &&
            choiceMode != null)
          Material(
            type: MaterialType.transparency,
            child: _choiceFields(context, exercise, choiceMode),
          ),
        if (exercise.questionType == TextbookExerciseQuestionType.fillBlank)
          ..._blankFields(context, exercise),
        if (!oral) ...[
          const SizedBox(height: SpacingTokens.sm),
          Wrap(
            spacing: SpacingTokens.sm,
            runSpacing: SpacingTokens.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: busy ? null : () => _submit(exercise, progress),
                icon: const Icon(Icons.check),
                label: const Text('提交答案'),
              ),
              if (record?.lastResult == TextbookExerciseResult.parentPending)
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _parentCheck(exercise, progress, record),
                  icon: const Icon(Icons.family_restroom),
                  label: const Text('核对'),
                ),
            ],
          ),
        ],
        if (record != null) ...[
          const SizedBox(height: SpacingTokens.xs),
          _recordSummary(context, record),
        ],
      ],
    );
  }

  Widget _choiceFields(
    BuildContext context,
    TextbookCourseExercise exercise,
    TextbookExerciseChoiceMode mode,
  ) {
    final selected = _selectedChoices[exercise.id]!;
    if (mode == TextbookExerciseChoiceMode.single) {
      return RadioGroup<String>(
        groupValue: selected.singleOrNull,
        onChanged: (value) {
          if (value == null) return;
          setState(() {
            selected
              ..clear()
              ..add(value);
          });
        },
        child: Column(
          children: [
            for (final option in exercise.choiceOptions)
              RadioListTile<String>(
                value: option.id,
                contentPadding: EdgeInsets.zero,
                title: Text(option.text),
              ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final option in exercise.choiceOptions)
          CheckboxListTile(
            value: selected.contains(option.id),
            contentPadding: EdgeInsets.zero,
            title: Text(option.text),
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  selected.add(option.id);
                } else {
                  selected.remove(option.id);
                }
              });
            },
          ),
      ],
    );
  }

  List<Widget> _blankFields(
    BuildContext context,
    TextbookCourseExercise exercise,
  ) {
    final controllers = _blankControllers[exercise.id]!;
    return [
      for (final (index, blank) in exercise.fillBlanks.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
          child: TextField(
            controller: controllers[index],
            textInputAction: index == controllers.length - 1
                ? TextInputAction.done
                : TextInputAction.next,
            decoration: InputDecoration(
              labelText: '第${index + 1}空',
              hintText: blank.id,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
    ];
  }

  Widget _recordSummary(BuildContext context, TextbookExerciseRecord record) {
    final result = record.lastResult;
    final label = switch (result) {
      TextbookExerciseResult.correct => '最近作答：正确',
      TextbookExerciseResult.incorrect => '最近作答：再试一次',
      TextbookExerciseResult.parentPending => '最近作答：待家长核对',
      TextbookExerciseResult.parentCorrect => '家长已确认完成',
      TextbookExerciseResult.parentAgain => '家长建议再练习',
      null => '尚未作答',
    };
    return Text(
      '$label · 已作答 ${record.attempts} 次',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  String _answerHint(TextbookCourseExercise exercise) =>
      switch (exercise.answerType) {
        TextbookAnswerType.exact => exercise.answerOrigin == 'textbook'
            ? '原书标准答案，提交后自动核对。'
            : '标准答案，提交后自动核对。',
        TextbookAnswerType.reference => '审核者整理的参考要点，请提交后由家长核对。',
        TextbookAnswerType.parentCheck => '这道题需要家长核对完成情况。',
        TextbookAnswerType.none => '这道题没有标准答案，请提交后由家长核对。',
      };

  Future<void> _submit(
    TextbookCourseExercise exercise,
    TextbookExerciseProgress? progress,
  ) async {
    final answer = switch (exercise.questionType) {
      TextbookExerciseQuestionType.choice => TextbookExerciseAnswer.choice(
          _selectedChoices[exercise.id]!.toList(),
        ),
      TextbookExerciseQuestionType.fillBlank =>
        TextbookExerciseAnswer.fillBlank(
          [
            for (final controller in _blankControllers[exercise.id]!)
              controller.text,
          ],
        ),
      TextbookExerciseQuestionType.oral => const TextbookExerciseAnswer.oral(),
    };
    await _runChange(
      exercise,
      progress,
      (repository, revision, operationId) => repository.recordAttempt(
        lessonId: widget.lesson.id,
        exerciseId: exercise.id,
        answer: answer,
        day: _today(),
        operationId: operationId,
        expectedRevision: revision,
      ),
    );
  }

  Future<void> _parentCheck(
    TextbookCourseExercise exercise,
    TextbookExerciseProgress? progress,
    TextbookExerciseRecord? record,
  ) async {
    if (record?.lastResult != TextbookExerciseResult.parentPending) return;
    final passed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('家长核对'),
        content: Text('请确认“${exercise.prompt}”是否完成。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('还要练习'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认完成'),
          ),
        ],
      ),
    );
    if (passed == null || !mounted) return;
    await _runChange(
      exercise,
      progress,
      (repository, revision, operationId) => repository.recordParentCheck(
        lessonId: widget.lesson.id,
        exerciseId: exercise.id,
        passed: passed,
        day: _today(),
        operationId: operationId,
        expectedRevision: revision,
      ),
    );
  }

  Future<void> _runChange(
    TextbookCourseExercise exercise,
    TextbookExerciseProgress? progress,
    Future<TextbookExerciseProgress> Function(
      TextbookExerciseRepository repository,
      int revision,
      String operationId,
    ) change,
  ) async {
    final book = ref
        .read(textbookListProvider)
        .where(
          (item) => item.pdfSha256 == widget.bookId,
        )
        .firstOrNull;
    final pack = ref.read(textbookCourseProvider(widget.bookId)).valueOrNull;
    if (book == null || pack == null) return;
    setState(() => _busyExerciseId = exercise.id);
    try {
      await change(
        TextbookExerciseRepository(
          book: book,
          editionId: pack.edition.id,
          courses: ref.read(textbookCourseRepositoryProvider),
          box: ref.read(textbookExerciseBoxProvider),
        ),
        progress?.revision ?? 0,
        '${DateTime.now().microsecondsSinceEpoch}-${exercise.id}',
      );
      ref.invalidate(textbookExerciseProgressProvider(widget.bookId));
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存习题记录失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyExerciseId = null);
    }
  }

  static String _today() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}

extension on TextbookExerciseQuestionType {
  String get label => switch (this) {
        TextbookExerciseQuestionType.choice => '选择题',
        TextbookExerciseQuestionType.fillBlank => '填空题',
        TextbookExerciseQuestionType.oral => '口答题',
      };
}
