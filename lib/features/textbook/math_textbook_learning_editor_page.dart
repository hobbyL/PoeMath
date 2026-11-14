import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/domain/math_textbook_practice.dart';
import 'package:poemath/features/textbook/math_textbook_labels.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_content.dart';
import 'package:poemath/features/textbook/widgets/textbook_review_layout.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

part 'math_textbook_learning_forms.dart';

enum MathTextbookLearningSection {
  all,
  knowledge,
  exercises,
  practice,
  coverage,
}

/// 学习规则由家长明确填写；保存回课时草稿，仍须对照原书审核。
class MathTextbookLearningEditorPage extends StatefulWidget {
  const MathTextbookLearningEditorPage({
    super.key,
    required this.book,
    required this.lesson,
    this.section = MathTextbookLearningSection.all,
    this.startAdding = false,
  });
  final Textbook book;
  final MathTextbookLesson lesson;
  final MathTextbookLearningSection section;
  final bool startAdding;
  @override
  State<MathTextbookLearningEditorPage> createState() =>
      _MathTextbookLearningEditorPageState();
}

class _MathTextbookLearningEditorPageState
    extends State<MathTextbookLearningEditorPage> {
  late final TextEditingController _unit;
  late List<MathTextbookKnowledgePoint> _knowledge;
  late List<MathTextbookExercise> _exercises;
  late List<MathTextbookPracticePlan> _plans;
  bool _coverage = false, _noExercises = false, _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final learning = widget.lesson.learning;
    _unit = TextEditingController(text: learning?.unitTitle ?? '');
    _knowledge = [...?learning?.knowledgePoints];
    _exercises = [...?learning?.exercises];
    _plans = [...?learning?.practicePlans];
    _coverage = learning?.coverageConfirmed ?? false;
    _noExercises = learning?.noExercises ?? false;
    if (widget.startAdding) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final kind = switch (widget.section) {
          MathTextbookLearningSection.knowledge => _LearningFormKind.knowledge,
          MathTextbookLearningSection.exercises => _LearningFormKind.exercise,
          MathTextbookLearningSection.practice => _LearningFormKind.plan,
          _ => null,
        };
        if (kind != null) unawaited(_edit(kind, null));
      });
    }
  }

  MathTextbookLearning get _learning => MathTextbookLearning(
    unitTitle: _unit.text.trim(),
    knowledgePoints: _knowledge,
    exercises: _exercises,
    practicePlans: _plans,
    coverageConfirmed: _coverage,
    noExercises: _noExercises,
  );

  void _change(VoidCallback action) => setState(() {
    action();
    _dirty = true;
    _coverage = false;
    _error = null;
  });

  Future<void> _edit(
    _LearningFormKind kind,
    Map<String, dynamic>? initial,
  ) async {
    assertParentAccess(context);
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ParentAccessBoundary(
          child: _MathLearningFormPage(
            book: widget.book,
            lesson: widget.lesson.edit(learning: _learning),
            kind: kind,
            initial: initial,
          ),
        ),
      ),
    );
    if (!mounted || result == null) return;
    assertParentAccess(context);
    _change(() {
      switch (kind) {
        case _LearningFormKind.knowledge:
          final value = MathTextbookKnowledgePoint.fromJson(result);
          final index = _knowledge.indexWhere((k) => k.id == value.id);
          if (index < 0) {
            _knowledge.add(value);
          } else {
            _knowledge[index] = value;
          }
        case _LearningFormKind.exercise:
          final value = MathTextbookExercise.fromJson(result);
          final index = _exercises.indexWhere((e) => e.id == value.id);
          if (index < 0) {
            _exercises.add(value);
          } else {
            _exercises[index] = value;
          }
          _noExercises = false;
        case _LearningFormKind.plan:
          final value = MathTextbookPracticePlan.fromJson(result);
          final index = _plans.indexWhere((p) => p.id == value.id);
          if (index < 0) {
            _plans.add(value);
          } else {
            _plans[index] = value;
          }
        case _LearningFormKind.answer:
          break;
      }
    });
  }

  Future<void> _remove(_LearningFormKind kind, String id) async {
    if (kind == _LearningFormKind.knowledge &&
        (_exercises.any((e) => e.knowledgePointIds.contains(id)) ||
            _plans.any((p) => p.knowledgePointId == id))) {
      setState(() => _error = '请先调整引用这个知识点的题目和巩固计划，再移除知识点');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('移除这一项？'),
        content: const Text('应用修改后，本课需要重新审核。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    assertParentAccess(context);
    _change(() {
      switch (kind) {
        case _LearningFormKind.knowledge:
          _knowledge.removeWhere((k) => k.id == id);
        case _LearningFormKind.exercise:
          _exercises.removeWhere((e) => e.id == id);
        case _LearningFormKind.plan:
          _plans.removeWhere((p) => p.id == id);
        case _LearningFormKind.answer:
          break;
      }
    });
  }

  Future<void> _import() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            const ParentAccessBoundary(child: _MathLearningJsonPage()),
      ),
    );
    if (!mounted || raw == null) return;
    try {
      assertParentAccess(context);
      if (utf8.encode(raw).length > 4 * 1024 * 1024) {
        throw const FormatException('学习配置不能超过 4 MB');
      }
      final value = MathTextbookLearning.fromJson(jsonDecode(raw));
      value.matchBlocks(widget.lesson.blocks);
      _change(() {
        _unit.text = value.unitTitle;
        _knowledge = [...value.knowledgePoints];
        _exercises = [...value.exercises];
        _plans = [...value.practicePlans];
        _noExercises = value.noExercises;
      });
    } on Object catch (error) {
      setState(
        () => _error = error is FormatException
            ? error.message.toString()
            : '学习配置无法读取，请检查格式',
      );
    }
  }

  void _apply() {
    try {
      assertParentAccess(context);
      final value = MathTextbookLearning.fromJson(_learning.toJson());
      value.matchBlocks(widget.lesson.blocks);
      if (value.coverageConfirmed) value.checkReady();
      Navigator.pop(context, value);
    } on Object catch (error) {
      setState(
        () => _error = error is FormatException
            ? error.message.toString()
            : '修改未应用，请重新解锁后重试',
      );
    }
  }

  Future<void> _leave() async {
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    final discard = await _confirmDiscard(context);
    if (mounted && discard) Navigator.pop(context);
  }

  @override
  void dispose() {
    _unit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final section = widget.section;
    final all = section == MathTextbookLearningSection.all;
    final coverage = all || section == MathTextbookLearningSection.coverage;
    return PopScope<void>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(switch (section) {
            MathTextbookLearningSection.all => '知识点、题目与巩固',
            MathTextbookLearningSection.knowledge => '知识点',
            MathTextbookLearningSection.exercises => '教材原题与题组',
            MathTextbookLearningSection.practice => '本课巩固',
            MathTextbookLearningSection.coverage => '核对内容范围',
          }),
          leading: IconButton(
            tooltip: '返回',
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(SpacingTokens.md),
            children: [
              ColoredCard(
                color: color,
                child: Text(
                  '${widget.lesson.title}\n把知识点和题目关联到原书内容，填写确定的答案或家长核对方式。应用后请回到课时页面保存并审核。',
                ),
              ),
              const SizedBox(height: SpacingTokens.md),
              if (coverage)
                TextField(
                  controller: _unit,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: '所属单元'),
                  onChanged: (_) => _change(() {}),
                ),
              if (all || section == MathTextbookLearningSection.knowledge)
                _collection('知识点', _LearningFormKind.knowledge, [
                  for (final k in _knowledge)
                    (k.id, k.title, k.summary, k.toJson()),
                ]),
              if (all || section == MathTextbookLearningSection.exercises)
                _collection('教材原题与题组', _LearningFormKind.exercise, [
                  for (final e in _exercises)
                    (
                      e.id,
                      e.title,
                      '${e.fields.length} 个作答项 · ${e.needsParent ? '含家长核对项' : '自动核对'}',
                      e.toJson(),
                    ),
                ]),
              if (all || section == MathTextbookLearningSection.practice)
                _collection('本课巩固', _LearningFormKind.plan, [
                  for (final p in _plans)
                    (
                      p.id,
                      p.title,
                      mathTextbookPracticeLabel(p.kind),
                      p.toJson(),
                    ),
                ]),
              if (_exercises.isEmpty &&
                  (coverage ||
                      section == MathTextbookLearningSection.exercises))
                AppTile(
                  iconColor: color,
                  title: '本课没有独立习题',
                  subtitle: '仅在原书确实没有本课习题时确认',
                  trailing: Switch(
                    value: _noExercises,
                    onChanged: (v) => _change(() => _noExercises = v),
                  ),
                ),
              const SizedBox(height: SpacingTokens.md),
              if (coverage)
                AppTile(
                  iconColor: color,
                  title: '本课内容已逐页核对',
                  subtitle: '知识点、完整题组、多空答案、单位和巩固范围均与原书一致',
                  trailing: Checkbox(
                    value: _coverage,
                    onChanged: (v) => setState(() {
                      _coverage = v ?? false;
                      _dirty = true;
                    }),
                  ),
                ),
              if (all)
                Wrap(
                  spacing: SpacingTokens.sm,
                  runSpacing: SpacingTokens.sm,
                  children: [
                    TextButton.icon(
                      onPressed: _import,
                      icon: const Icon(Icons.input_outlined),
                      label: const Text('导入学习配置'),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: const JsonEncoder.withIndent('  ')
                                .convert(_learning.toJson()),
                          ),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('学习配置已复制')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('复制学习配置'),
                    ),
                  ],
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: SpacingTokens.sm,
                  ),
                  child: ColoredCard(
                    color: Theme.of(context).colorScheme.error,
                    child: Text(_error!),
                  ),
                ),
              FilledButton(onPressed: _apply, child: const Text('应用到课时草稿')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _collection(
    String title,
    _LearningFormKind kind,
    List<(String, String, String, Map<String, dynamic>)> rows,
  ) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextbookReviewSectionHeader(
            title: '$title · ${rows.length}',
            actionLabel: '添加$title',
            actionIcon: Icons.add,
            actionIconAlignment: IconAlignment.start,
            onAction: () => _edit(kind, null),
          ),
          const SizedBox(height: SpacingTokens.sm),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
              child: AppTile(
                flat: true,
                flatTrailingEdgeAligned: true,
                iconColor: color,
                title: row.$2,
                subtitle: row.$3,
                subtitleMaxLines: 2,
                onTap: () => _edit(kind, row.$4),
                trailingIcon: Icons.delete_outline,
                trailingTooltip: '移除${row.$2}',
                onTrailingTap: () => _remove(kind, row.$1),
              ),
            ),
        ],
      ),
    );
  }
}

Future<bool> _confirmDiscard(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('有未应用的修改'),
        content: const Text('可以继续编辑，或放弃这次修改后返回。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('放弃并返回'),
          ),
        ],
      ),
    ) ??
    false;
