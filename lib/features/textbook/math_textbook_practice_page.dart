import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_progress.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/math_textbook_learning_repository.dart';
import 'package:poemath/domain/math_textbook_grading.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/textbook/math_textbook_labels.dart';
import 'package:poemath/features/textbook/providers/math_textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_study_content.dart';

/// 教材练习独立冻结本课题目；普通口算会话和键盘状态继续独立。
class MathTextbookPracticePage extends ConsumerStatefulWidget {
  const MathTextbookPracticePage({
    super.key,
    required this.bookId,
    required this.lessonId,
    this.planId,
  });
  final String bookId, lessonId;
  final String? planId;
  @override
  ConsumerState<MathTextbookPracticePage> createState() =>
      _MathTextbookPracticePageState();
}

class _MathTextbookPracticePageState
    extends ConsumerState<MathTextbookPracticePage>
    with WidgetsBindingObserver {
  MathTextbookLearningRepository? _repository;
  MathTextbookPracticeDraft? _draft;
  MathSession? _session;
  final _controllers = <String, TextEditingController>{};
  final _clock = Stopwatch();
  late final StreamSubscription<String> _profileSubscription;
  Timer? _debounce;
  bool _loading = true,
      _busy = false,
      _committed = false,
      _scopeChanged = false,
      _foreground = true;
  int _baseSeconds = 0, _inputRevision = 0;
  String? _error;
  Textbook? get _book => _repository?.book;

  @override
  void initState() {
    super.initState();
    final shared = ref.read(
      mathTextbookLearningRepositoryProvider(widget.bookId),
    );
    if (shared != null) {
      _repository = MathTextbookLearningRepository(
        book: shared.book,
        courses: shared.courses,
        findBook: shared.findBook,
        recordStatistics: shared.recordStatistics,
        isActive: () => mounted && !_scopeChanged,
      );
    }
    WidgetsBinding.instance.addObserver(this);
    _profileSubscription = ProfileScope.changes.listen((_) {
      _debounce?.cancel();
      _clock.stop();
      if (mounted) {
        setState(() {
          _scopeChanged = true;
          _error = '孩子档案已切换，当前练习属于原档案，已保存的草稿会保留，请返回后重新打开';
        });
      }
    });
    unawaited(_load());
  }

  void _updateClock() {
    if (_foreground &&
        !_busy &&
        !_loading &&
        !_scopeChanged &&
        _session == null &&
        _draft?.finishedAt == null) {
      _clock.start();
    } else {
      _clock.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updateClock();
    if (!_foreground) {
      _debounce?.cancel();
      unawaited(_save());
    }
  }

  Future<void> _load() async {
    try {
      final repository = _repository;
      if (repository == null) throw StateError('数学教材已移除，请返回后重新选择');
      final previous = await repository.loadDraft(
        widget.lessonId,
        planId: widget.planId,
      );
      final draft =
          previous ??
          await repository.start(widget.lessonId, planId: widget.planId);
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _baseSeconds = draft.elapsedSeconds;
        _committed =
            draft.index < draft.items.length &&
            draft.results[draft.index] != null;
      });
      _syncControllers();
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace, '本课练习暂时无法打开，已有草稿保留。');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _updateClock();
      }
    }
  }

  void _report(Object error, StackTrace stackTrace, String fallback) {
    AppLogger.e(
      fallback,
      tag: 'MathTextbook',
      error: error,
      stackTrace: stackTrace,
    );
    if (mounted) {
      setState(() => _error = mathTextbookDisplayError(error, fallback));
    }
  }

  MathTextbookPracticeDraft _snapshot() => _draft!.copyWith(
    elapsedSeconds: _draft!.finishedAt == null
        ? _baseSeconds + _clock.elapsed.inSeconds
        : _draft!.elapsedSeconds,
  );

  Future<bool> _save() async {
    if (_draft == null || _session != null || _scopeChanged) return true;
    final snapshot = _snapshot(), revision = _inputRevision;
    try {
      await _repository!.saveDraft(snapshot);
      if (mounted && !_scopeChanged && revision == _inputRevision) {
        setState(() => _error = null);
      }
      return true;
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace, '输入尚未保存，请保持本页并重试。');
      return false;
    }
  }

  void _syncControllers() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    final draft = _draft;
    if (draft == null || draft.index >= draft.items.length) return;
    final item = draft.items[draft.index];
    for (final field in item.exercise.fields) {
      final answer = draft.answers[draft.index][field.id] ?? '';
      if (field.rule.kind == MathTextbookAnswerKind.remainder) {
        final parts = answer.split('…');
        _controllers['${field.id}:q'] = TextEditingController(
          text: parts.first,
        );
        _controllers['${field.id}:r'] = TextEditingController(
          text: parts.length > 1 ? parts[1] : '',
        );
      } else {
        _controllers[field.id] = TextEditingController(text: answer);
      }
    }
  }

  void _change(String id, String value) {
    final draft = _draft!;
    final answers = draft.answers.map((a) => <String, String>{...a}).toList();
    answers[draft.index][id] = value;
    setState(() {
      _draft = draft.copyWith(answers: answers);
      _error = null;
      _inputRevision++;
    });
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_save()),
    );
  }

  Future<void> _submit() async {
    if (_busy || _scopeChanged) return;
    final item = _draft!.items[_draft!.index];
    if (!mathTextbookAnswersComplete(
      item.exercise,
      _draft!.answers[_draft!.index],
    )) {
      setState(() => _error = '请完成本题全部作答项。纸上题请填写完成情况。');
      return;
    }
    _debounce?.cancel();
    setState(() {
      _busy = true;
      _error = null;
      _committed = false;
    });
    _updateClock();
    try {
      final draft = _snapshot();
      await _repository!.saveDraft(draft);
      await _repository!.submit(draft, draft.index);
      final results = [...draft.results];
      results[draft.index] = gradeMathTextbookExercise(
        item.exercise,
        draft.answers[draft.index],
      ).result;
      final next = draft.copyWith(results: results);
      if (mounted) setState(() => _draft = next);
      await _repository!.saveDraft(next);
      if (!mounted) return;
      setState(() => _committed = true);
      ref.invalidate(mathTextbookProgressProvider(widget.bookId));
      ref.invalidate(userStatsProvider);
      ref.invalidate(mathMistakesProvider);
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace, '作答尚未保存完成，请重试核对。');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _updateClock();
      }
    }
  }

  Future<void> _next() async {
    if (_busy || !_committed || _scopeChanged) return;
    if (_draft!.index == _draft!.items.length - 1) {
      await _finish();
      return;
    }
    setState(() {
      _draft = _snapshot().copyWith(index: _draft!.index + 1);
      _committed = false;
      _error = null;
    });
    _syncControllers();
    await _save();
  }

  Future<void> _finish() async {
    if (_busy || _scopeChanged) return;
    _debounce?.cancel();
    final snapshot = _snapshot();
    _clock.stop();
    setState(() {
      _busy = true;
      _error = null;
      _draft = snapshot.copyWith(
        index: snapshot.items.length,
        finishedAt: snapshot.finishedAt ?? DateTime.now(),
      );
    });
    try {
      await _repository!.saveDraft(_draft!);
      final session = await _repository!.finish(_draft!);
      if (!mounted) return;
      setState(() => _session = session);
      ref.invalidate(mathTextbookProgressProvider(widget.bookId));
      ref.invalidate(userStatsProvider);
      ref.invalidate(todayCheckInProvider);
      ref.invalidate(todayMathCountProvider);
      ref.invalidate(recentSessionsProvider);
      ref.invalidate(totalProblemsCountProvider);
      ref.invalidate(overallAccuracyProvider);
      ref.invalidate(mathMistakesProvider);
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace, '本次记录还没有结算完成，请重试保存。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restart() async {
    if (_busy || _scopeChanged || _repository == null) return;
    if (_session == null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('重新开始本课练习？'),
          content: const Text('当前未完成的练习草稿会被新题替换，已经保存的作答历史会保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('继续当前练习'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('重新开始'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    _debounce?.cancel();
    _clock.stop();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final draft = await _repository!.start(
        widget.lessonId,
        planId: widget.planId,
      );
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _session = null;
        _committed = false;
        _baseSeconds = 0;
        _clock.reset();
        _inputRevision++;
      });
      _syncControllers();
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace, '新练习未开始，原草稿保留。');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _updateClock();
      }
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    _debounce?.cancel();
    _clock.stop();
    final saved = await _save();
    if (!mounted) return;
    if (!saved) {
      _updateClock();
      return;
    }
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _clock.stop();
    unawaited(_profileSubscription.cancel());
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: _session != null || _scopeChanged || _draft == null,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.planId == null ? '教材原题' : '本课巩固'),
        leading: IconButton(
          tooltip: '保存并返回',
          onPressed: _busy ? null : _leave,
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            tooltip: '重新开始',
            onPressed: _busy || _scopeChanged ? null : _restart,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _draft == null
          ? AppEmptyState(
              icon: Icons.school_outlined,
              title: '本课练习暂不可用',
              description: _error ?? '请家长补齐学习配置并审核本课。',
              actions: [
                TextButton(
                  onPressed: _scopeChanged ? null : _restart,
                  child: const Text('重新开始'),
                ),
              ],
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(SpacingTokens.md),
                children:
                    _session != null || _draft!.index >= _draft!.items.length
                    ? _summary()
                    : _question(),
              ),
            ),
    ),
  );

  List<Widget> _summary() {
    final draft = _draft!,
        pending = draft.results
            .where((r) => r == MathTextbookResult.pendingParent)
            .length;
    return [
      Text(
        _session == null ? '正在保存本次练习' : '本次练习已完成',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: SpacingTokens.md),
      ColoredCard(
        color: Theme.of(context).colorScheme.primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('已保存 ${draft.items.length} 题'),
            if (_session != null && _session!.totalProblems > 0)
              Text(
                '自动核对通过 ${_session!.correctCount}/${_session!.totalProblems} 题 · ${_session!.starsEarned} 颗星',
              ),
            if (pending > 0) Text('$pending 题待家长核对'),
            const Text('返回本课可查看学习进度与作答记录。'),
          ],
        ),
      ),
      if (_error != null) _errorCard(),
      const SizedBox(height: SpacingTokens.md),
      if (_session == null)
        FilledButton(
          onPressed: _busy || _scopeChanged ? null : _finish,
          child: Text(_busy ? '正在保存…' : '重试保存本次记录'),
        )
      else ...[
        FilledButton(onPressed: _leave, child: const Text('返回本课')),
        OutlinedButton(onPressed: _restart, child: const Text('再练一次')),
      ],
    ];
  }

  List<Widget> _question() {
    final draft = _draft!,
        item = draft.items[draft.index],
        result = draft.results[draft.index];
    final evaluation = result == null
        ? null
        : gradeMathTextbookExercise(item.exercise, draft.answers[draft.index]);
    return [
      Text(
        '${draft.index + 1} / ${draft.items.length}',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: SpacingTokens.sm),
      Text(item.exercise.title, style: Theme.of(context).textTheme.titleLarge),
      if (item.exercise.number.isNotEmpty) Text('原书题号：${item.exercise.number}'),
      if (widget.planId != null)
        Text(
          item.exercise.fields.every(
                (field) => field.rule.kind == MathTextbookAnswerKind.parent,
              )
              ? '本课纸上练习，完成后记录作答'
              : '按本课已审核范围生成的巩固题',
        ),
      const SizedBox(height: SpacingTokens.md),
      for (final block in item.blocks)
        Padding(
          padding: const EdgeInsets.only(bottom: SpacingTokens.md),
          child: MathTextbookStudyContent(book: _book!, block: block),
        ),
      if (item.exercise.note.isNotEmpty) Text(item.exercise.note),
      for (final field in item.exercise.fields) ...[
        const SizedBox(height: SpacingTokens.md),
        ..._answer(field, enabled: !_busy && !_scopeChanged && result == null),
        if (evaluation != null)
          Text(
            evaluation.fields[field.id] == null
                ? '此项待家长核对'
                : evaluation.fields[field.id]!
                ? '这项答对了'
                : '再检查这一项',
          ),
        if (result != null &&
            field.rule.kind != MathTextbookAnswerKind.parent &&
            evaluation!.fields[field.id] == false)
          Text(
            '参考答案：${field.rule.kind == MathTextbookAnswerKind.choice ? field.rule.correctChoices.join('、') : '${field.rule.expected}${MathTextbookUnits.label(field.rule.unit)}'}',
          ),
      ],
      if (result != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
          child: Text(mathTextbookResultLabel(result)),
        ),
      if (_error != null) _errorCard(),
      const SizedBox(height: SpacingTokens.md),
      if (result == null || !_committed)
        FilledButton(
          onPressed: _busy || _scopeChanged ? null : _submit,
          child: Text(
            _busy
                ? '正在保存…'
                : result == null
                ? '核对答案'
                : '重试保存作答',
          ),
        )
      else
        FilledButton(
          onPressed: _busy || _scopeChanged ? null : _next,
          child: Text(draft.index == draft.items.length - 1 ? '完成本次练习' : '下一题'),
        ),
      if (_error != null)
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: jsonEncode(draft.answers)),
            );
            if (mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('当前作答已复制')));
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('复制当前作答'),
        ),
    ];
  }

  Widget _errorCard() => Padding(
    padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
    child: ColoredCard(
      color: Theme.of(context).colorScheme.error,
      child: Text(_error!),
    ),
  );

  List<Widget> _answer(MathTextbookAnswerField field, {required bool enabled}) {
    final rule = field.rule,
        value = _draft!.answers[_draft!.index][field.id] ?? '';
    if (rule.kind == MathTextbookAnswerKind.choice) {
      var selected = <String>{};
      try {
        final raw = jsonDecode(value);
        if (raw is List) selected = raw.cast<String>().toSet();
      } on Object {
        if (rule.options.contains(value)) selected.add(value);
      }
      return [
        Text(field.label),
        for (final option in rule.options)
          Padding(
            padding: const EdgeInsets.only(top: SpacingTokens.sm),
            child: AppTile(
              iconColor: Theme.of(context).colorScheme.primary,
              title: option,
              subtitle: '',
              trailing: Checkbox(
                value: selected.contains(option),
                onChanged: enabled
                    ? (v) {
                        final next = {...selected};
                        if (v == true) {
                          next.add(option);
                        } else {
                          next.remove(option);
                        }
                        _change(field.id, jsonEncode(next.toList()));
                      }
                    : null,
              ),
            ),
          ),
      ];
    }
    if (rule.kind == MathTextbookAnswerKind.comparison) {
      return [
        Text(field.label),
        const SizedBox(height: SpacingTokens.sm),
        SegmentedButton<String>(
          emptySelectionAllowed: true,
          segments: const [
            ButtonSegment(value: '<', label: Text('<')),
            ButtonSegment(value: '=', label: Text('=')),
            ButtonSegment(value: '>', label: Text('>')),
          ],
          selected: value.isEmpty ? <String>{} : {value},
          onSelectionChanged: enabled
              ? (values) =>
                    _change(field.id, values.isEmpty ? '' : values.single)
              : null,
        ),
      ];
    }
    if (rule.kind == MathTextbookAnswerKind.remainder) {
      return [
        Text(field.label),
        const SizedBox(height: SpacingTokens.sm),
        TextField(
          controller: _controllers['${field.id}:q'],
          enabled: enabled,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '商'),
          onChanged: (_) => _change(
            field.id,
            '${_controllers['${field.id}:q']!.text}…${_controllers['${field.id}:r']!.text}',
          ),
        ),
        const SizedBox(height: SpacingTokens.sm),
        TextField(
          controller: _controllers['${field.id}:r'],
          enabled: enabled,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '余数'),
          onChanged: (_) => _change(
            field.id,
            '${_controllers['${field.id}:q']!.text}…${_controllers['${field.id}:r']!.text}',
          ),
        ),
      ];
    }
    return [
      TextField(
        controller: _controllers[field.id],
        enabled: enabled,
        minLines: rule.kind == MathTextbookAnswerKind.parent ? 3 : 1,
        maxLines: rule.kind == MathTextbookAnswerKind.parent ? null : 3,
        maxLength: rule.kind == MathTextbookAnswerKind.parent ? 5000 : 512,
        decoration: InputDecoration(
          labelText: field.label,
          counterText: rule.kind == MathTextbookAnswerKind.parent ? null : '',
          helperText: rule.kind == MathTextbookAnswerKind.parent
              ? '可在纸上完成，请记下完成情况或解题过程'
              : '${mathTextbookFormLabel(rule.form)}${rule.unit.isEmpty ? '' : ' · 请带单位：${MathTextbookUnits.label(rule.unit)}'}',
          helperMaxLines: 3,
        ),
        onChanged: (value) => _change(field.id, value),
      ),
    ];
  }
}
