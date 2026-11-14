part of 'math_textbook_learning_editor_page.dart';

enum _LearningFormKind { knowledge, exercise, answer, plan }

class _MathLearningFormPage extends StatefulWidget {
  const _MathLearningFormPage({
    required this.book,
    required this.lesson,
    required this.kind,
    this.initial,
  });
  final Textbook book;
  final MathTextbookLesson lesson;
  final _LearningFormKind kind;
  final Map<String, dynamic>? initial;
  @override
  State<_MathLearningFormPage> createState() => _MathLearningFormPageState();
}

class _MathLearningFormPageState extends State<_MathLearningFormPage> {
  final _controllers = <String, TextEditingController>{};
  late final Map<String, dynamic> _data;
  late Set<String> _blocks, _knowledgeIds;
  late List<MathTextbookAnswerField> _fields;
  late final String _id;
  bool _dirty = false;
  String? _error;
  List<MathTextbookPracticeItem>? _preview;
  String get _title => switch (widget.kind) {
    _LearningFormKind.knowledge => '编辑知识点',
    _LearningFormKind.exercise => '编辑题组',
    _LearningFormKind.answer => '编辑作答项',
    _LearningFormKind.plan => '设置本课巩固',
  };

  @override
  void initState() {
    super.initState();
    _data = {...?widget.initial};
    if (widget.kind == _LearningFormKind.answer) {
      _data.addAll((widget.initial?['rule'] as Map<String, dynamic>?) ?? {});
    }
    _id =
        widget.initial?['id'] as String? ??
        '${widget.kind.name}-${DateTime.now().microsecondsSinceEpoch}';
    _blocks = ((widget.initial?['blockIds'] as List?) ?? [])
        .cast<String>()
        .toSet();
    _knowledgeIds = ((widget.initial?['knowledgePointIds'] as List?) ?? [])
        .cast<String>()
        .toSet();
    _fields = ((widget.initial?['fields'] as List?) ?? [])
        .map(MathTextbookAnswerField.fromJson)
        .toList();
    _data.putIfAbsent(
      'kind',
      () => widget.kind == _LearningFormKind.answer ? 'parent' : 'engine',
    );
    _data.putIfAbsent(
      'knowledgePointId',
      () => widget.lesson.learning?.knowledgePoints.firstOrNull?.id ?? '',
    );
    _data.putIfAbsent('skillId', () => MathSkill.addition.id);
  }

  void _change(VoidCallback action) => setState(() {
    action();
    _dirty = true;
    _error = null;
    _preview = null;
  });
  TextEditingController _controller(String name, [String fallback = '']) =>
      _controllers.putIfAbsent(
        name,
        () => TextEditingController(text: _data[name]?.toString() ?? fallback),
      );
  String _text(String name, [String fallback = '']) =>
      _controller(name, fallback).text.trim();
  int _integerField(String name, String label, String fallback) {
    final value = int.tryParse(_text(name, fallback));
    if (value == null) throw FormatException('$label须为整数');
    return value;
  }

  Map<String, dynamic> _json() {
    switch (widget.kind) {
      case _LearningFormKind.knowledge:
        return MathTextbookKnowledgePoint.fromJson({
          'id': _id,
          'title': _text('title'),
          'summary': _text('summary'),
          'blockIds': _blocks.toList(),
        }).toJson();
      case _LearningFormKind.exercise:
        return MathTextbookExercise.fromJson({
          'id': _id,
          'title': _text('title'),
          'number': _text('number'),
          'note': _text('note'),
          'blockIds': _blocks.toList(),
          'knowledgePointIds': _knowledgeIds.toList(),
          'fields': _fields.map((f) => f.toJson()).toList(),
        }).toJson();
      case _LearningFormKind.answer:
        final kind = MathTextbookAnswerKind.values.byName(
          _data['kind'] as String,
        );
        return MathTextbookAnswerField.fromJson({
          'id': _id,
          'label': _text('label'),
          'rule': {
            'kind': kind.name,
            'expected':
                kind == MathTextbookAnswerKind.parent ||
                    kind == MathTextbookAnswerKind.choice
                ? ''
                : _text('expected'),
            'form':
                kind == MathTextbookAnswerKind.number ||
                    kind == MathTextbookAnswerKind.expression
                ? _data['form'] ?? 'any'
                : 'any',
            'unit':
                kind == MathTextbookAnswerKind.number ||
                    kind == MathTextbookAnswerKind.expression
                ? _data['unit'] ?? ''
                : '',
            'allowUnitConversion': _data['allowUnitConversion'] ?? false,
            'divisor': kind == MathTextbookAnswerKind.remainder
                ? _integerField('divisor', '除数', '')
                : null,
            'options': kind == MathTextbookAnswerKind.choice
                ? _text('optionsText')
                      .split('\n')
                      .map((v) => v.trim())
                      .where((v) => v.isNotEmpty)
                      .toList()
                : <String>[],
            'correctChoices': kind == MathTextbookAnswerKind.choice
                ? _text('choicesText')
                      .split('\n')
                      .map((v) => v.trim())
                      .where((v) => v.isNotEmpty)
                      .toList()
                : <String>[],
            'reference': _text('reference'),
            'answerSource': _data['answerSource'] ?? 'parent',
          },
        }).toJson();
      case _LearningFormKind.plan:
        final kind = MathTextbookPracticeKind.values.byName(
          _data['kind'] as String,
        );
        return MathTextbookPracticePlan.fromJson({
          'id': _id,
          'title': _text('title'),
          'knowledgePointId': _data['knowledgePointId'],
          'kind': kind.name,
          'skillId': kind == MathTextbookPracticeKind.engine
              ? _data['skillId']
              : null,
          'count': _integerField('count', '题数', '5'),
          'minOperand': _integerField(
            'minOperand',
            '最小数',
            kind == MathTextbookPracticeKind.engine ? '0' : '1',
          ),
          'maxOperand': _integerField('maxOperand', '最大数', '20'),
          'maxResult': _integerField('maxResult', '结果上限', '40'),
          'operators': _data['operators'] ?? ['add', 'subtract'],
          'mode': (_data['mode'] as String?)?.isEmpty == true
              ? null
              : _data['mode'],
          'allowCarry': _data['allowCarry'] ?? true,
          'allowBorrow': _data['allowBorrow'] ?? true,
          'allowRemainder': _data['allowRemainder'] ?? false,
          'allowBrackets': _data['allowBrackets'] ?? false,
          'allowNegative': _data['allowNegative'] ?? false,
          'decimalPlaces': _integerField('decimalPlaces', '小数位数', '0'),
          'maxDenominator': _integerField('maxDenominator', '分母上限', '1'),
          'unit': _data['unit'] ?? '',
          'toUnit': _data['toUnit'] ?? '',
          'pi': _text('pi', '3.14'),
          'task': kind == MathTextbookPracticeKind.dataTable
              ? _data['tableTask'] ?? _data['task'] ?? 'total'
              : _text('task'),
        }).toJson();
    }
  }

  void _save() {
    try {
      assertParentAccess(context);
      Navigator.pop(context, _json());
    } on Object catch (error) {
      setState(
        () => _error = error is FormatException
            ? error.message.toString()
            : '修改无法应用，请检查填写内容和家长授权',
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

  Future<void> _pickBlocks() async {
    final blocks = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => ParentAccessBoundary(
          child: _MathSourcePickerPage(
            book: widget.book,
            lesson: widget.lesson,
            selected: _blocks,
          ),
        ),
      ),
    );
    if (!mounted || blocks == null) return;
    _change(() => _blocks = blocks);
  }

  Future<void> _editAnswer(MathTextbookAnswerField? field) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ParentAccessBoundary(
          child: _MathLearningFormPage(
            book: widget.book,
            lesson: widget.lesson,
            kind: _LearningFormKind.answer,
            initial: field?.toJson(),
          ),
        ),
      ),
    );
    if (!mounted || result == null) return;
    final value = MathTextbookAnswerField.fromJson(result);
    _change(() {
      final index = _fields.indexWhere((f) => f.id == value.id);
      if (index < 0) {
        _fields.add(value);
      } else {
        _fields[index] = value;
      }
    });
  }

  void _generatePreview() {
    try {
      assertParentAccess(context);
      final plan = MathTextbookPracticePlan.fromJson(_json());
      setState(() {
        _preview = generateMathTextbookPractice(
          lesson: widget.lesson,
          plan: plan,
          grade: widget.book.grade,
          semester: widget.book.semester,
        );
        _error = null;
      });
    } on Object catch (error) {
      setState(
        () => _error = error is FormatException
            ? error.message.toString()
            : '当前范围无法生成题目，请调整数值、运算或题型',
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_dirty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(_title),
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
            if (widget.kind == _LearningFormKind.answer)
              ..._answerForm()
            else ...[
              _field(
                'title',
                widget.kind == _LearningFormKind.knowledge
                    ? '知识点名称'
                    : widget.kind == _LearningFormKind.exercise
                    ? '题组提示'
                    : '巩固名称',
                max: 200,
              ),
              if (widget.kind == _LearningFormKind.knowledge)
                _field('summary', '知识要点（按原书补齐）', multiline: true, max: 5000),
              if (widget.kind == _LearningFormKind.knowledge ||
                  widget.kind == _LearningFormKind.exercise)
                AppTile(
                  icon: Icons.menu_book_outlined,
                  iconColor: Theme.of(context).colorScheme.primary,
                  title: '关联原书内容',
                  subtitle: '已选择 ${_blocks.length} 处内容，可跨页关联',
                  onTap: _pickBlocks,
                ),
              if (widget.kind == _LearningFormKind.exercise) ..._exerciseForm(),
              if (widget.kind == _LearningFormKind.plan) ..._planForm(),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
                child: ColoredCard(
                  color: Theme.of(context).colorScheme.error,
                  child: Text(_error!),
                ),
              ),
            const SizedBox(height: SpacingTokens.md),
            FilledButton(onPressed: _save, child: const Text('应用这一项')),
          ],
        ),
      ),
    ),
  );

  Widget _field(
    String name,
    String label, {
    String fallback = '',
    bool multiline = false,
    bool numeric = false,
    int max = 200,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: SpacingTokens.md),
    child: TextField(
      controller: _controller(name, fallback),
      maxLength: max,
      minLines: multiline ? 3 : 1,
      maxLines: multiline ? null : 1,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(signed: true, decimal: true)
          : multiline
          ? TextInputType.multiline
          : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => _change(() {}),
    ),
  );

  Widget _dropdown(
    String name,
    String label,
    Map<String, String> items, {
    String fallback = '',
  }) {
    final value = _data[name] as String? ?? fallback;
    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.md),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$name-$value'),
        initialValue: items.containsKey(value) ? value : null,
        isExpanded: true,
        itemHeight: null,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final entry in items.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (v) => _change(() {
          _data[name] = v;
        }),
      ),
    );
  }

  Widget _toggle(
    String name,
    String title, {
    String subtitle = '',
    bool fallback = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
    child: AppTile(
      iconColor: Theme.of(context).colorScheme.primary,
      title: title,
      subtitle: subtitle,
      trailing: Switch(
        value: _data[name] as bool? ?? fallback,
        onChanged: (v) => _change(() => _data[name] = v),
      ),
    ),
  );

  List<Widget> _answerForm() {
    final kind = MathTextbookAnswerKind.values.byName(_data['kind'] as String);
    _data.putIfAbsent(
      'optionsText',
      () => ((widget.initial?['rule'] as Map?)?['options'] as List? ?? []).join(
        '\n',
      ),
    );
    _data.putIfAbsent(
      'choicesText',
      () =>
          ((widget.initial?['rule'] as Map?)?['correctChoices'] as List? ?? [])
              .join('\n'),
    );
    return [
      _field('label', '作答提示，如“第 1 空”或“纸上作图完成情况”'),
      _dropdown('kind', '核对方式', {
        for (final kind in MathTextbookAnswerKind.values)
          kind.name: mathTextbookAnswerLabel(kind),
      }),
      if (kind == MathTextbookAnswerKind.parent)
        const Text('孩子可以在纸上完成作图、测量或说明过程，并记下完成情况。家长对照原书核对，不计入自动正确率。'),
      if (kind != MathTextbookAnswerKind.parent &&
          kind != MathTextbookAnswerKind.choice)
        _field(
          'expected',
          kind == MathTextbookAnswerKind.remainder
              ? '答案（商…余数，如 3…1）'
              : kind == MathTextbookAnswerKind.expression
              ? '算式应得的数值或方程的解'
              : '确定的答案',
          max: 128,
        ),
      if (kind == MathTextbookAnswerKind.choice) ...[
        _field('optionsText', '完整选项（每行一个）', multiline: true, max: 10000),
        _field(
          'choicesText',
          '正确选项（每行一个，与上方文本完全一致）',
          multiline: true,
          max: 10000,
        ),
      ],
      if (kind == MathTextbookAnswerKind.remainder)
        _field('divisor', '除数', numeric: true, max: 16),
      if (kind == MathTextbookAnswerKind.number ||
          kind == MathTextbookAnswerKind.expression) ...[
        _dropdown('form', '教材要求的表示形式', {
          for (final form in MathTextbookNumberForm.values)
            form.name: mathTextbookFormLabel(form),
        }, fallback: 'any'),
        _dropdown('unit', '答案单位', {
          '': '不带单位',
          for (final unit in MathTextbookUnits.values.keys)
            unit: MathTextbookUnits.label(unit),
        }),
        if ((_data['unit'] as String? ?? '').isNotEmpty)
          _toggle(
            'allowUnitConversion',
            '允许同量纲单位换算',
            subtitle: '例如 1 米与 100 厘米可视为同一个量',
          ),
      ],
      _field(
        'reference',
        kind == MathTextbookAnswerKind.parent ? '家长核对要点' : '答案说明（可选）',
        multiline: true,
        max: 5000,
      ),
      _dropdown('answerSource', '答案来源', {
        'parent': '家长计算并核对',
        'source': '原书明确给出',
        'computed': '可验证的本机计算',
      }, fallback: 'parent'),
    ];
  }

  List<Widget> _exerciseForm() => [
    const SizedBox(height: SpacingTokens.md),
    _field('number', '原书题号（可选）', max: 40),
    _field('note', '题目补充说明（可选）', multiline: true, max: 5000),
    Text('关联知识点', style: Theme.of(context).textTheme.titleMedium),
    for (final k
        in widget.lesson.learning?.knowledgePoints ??
            <MathTextbookKnowledgePoint>[])
      Padding(
        padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
        child: AppTile(
          iconColor: Theme.of(context).colorScheme.primary,
          title: k.title,
          subtitle: '',
          allowTapWithTrailing: true,
          onTap: () => _change(() {
            if (!_knowledgeIds.add(k.id)) _knowledgeIds.remove(k.id);
          }),
          trailing: Checkbox(
            value: _knowledgeIds.contains(k.id),
            onChanged: (v) => _change(() {
              if (v == true) {
                _knowledgeIds.add(k.id);
              } else {
                _knowledgeIds.remove(k.id);
              }
            }),
          ),
        ),
      ),
    Text('作答项（按原书顺序排列）', style: Theme.of(context).textTheme.titleMedium),
    for (final field in _fields)
      Padding(
        padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
        child: AppTile(
          iconColor: Theme.of(context).colorScheme.primary,
          title: field.label,
          subtitle: mathTextbookAnswerLabel(field.rule.kind),
          onTap: () => _editAnswer(field),
          trailingAction: IconButton(
            tooltip: '移除${field.label}',
            onPressed: () =>
                _change(() => _fields.removeWhere((f) => f.id == field.id)),
            icon: const Icon(Icons.delete_outline),
          ),
        ),
      ),
    OutlinedButton.icon(
      onPressed: () => _editAnswer(null),
      icon: const Icon(Icons.add),
      label: const Text('添加一个作答项'),
    ),
  ];

  List<Widget> _planForm() {
    final kind = MathTextbookPracticeKind.values.byName(
      _data['kind'] as String,
    );
    return [
      _dropdown('knowledgePointId', '对应本课知识点', {
        for (final k
            in widget.lesson.learning?.knowledgePoints ??
                <MathTextbookKnowledgePoint>[])
          k.id: k.title,
      }),
      _dropdown('kind', '巩固内容', {
        for (final kind in MathTextbookPracticeKind.values)
          kind.name: mathTextbookPracticeLabel(kind),
      }),
      if (kind == MathTextbookPracticeKind.parentTask)
        _field('task', '实际任务（如画图、测量、解释方法）', multiline: true, max: 5000)
      else ...[
        _field('count', '本次题数（1～30）', fallback: '5', numeric: true, max: 2),
        _field(
          'minOperand',
          '给定数值的最小值',
          fallback: kind == MathTextbookPracticeKind.engine ? '0' : '1',
          numeric: true,
          max: 10,
        ),
        _field(
          'maxOperand',
          '给定数值的最大值',
          fallback: '20',
          numeric: true,
          max: 10,
        ),
        _field('maxResult', '结果绝对值上限', fallback: '40', numeric: true, max: 10),
      ],
      if (kind == MathTextbookPracticeKind.engine) ...[
        _dropdown('skillId', '计算知识点', {
          for (final skill in MathSkill.values) skill.id: skill.label,
        }),
        Text('允许的运算', style: Theme.of(context).textTheme.titleMedium),
        Wrap(
          spacing: SpacingTokens.sm,
          runSpacing: SpacingTokens.sm,
          children: [
            for (final op in Operator.values)
              FilterChip(
                label: Text(op.symbol),
                selected: ((_data['operators'] as List?) ?? ['add', 'subtract'])
                    .contains(op.name),
                onSelected: (v) => _change(() {
                  final ops =
                      (((_data['operators'] as List?) ?? ['add', 'subtract'])
                              .cast<String>())
                          .toSet();
                  if (v) {
                    ops.add(op.name);
                  } else {
                    ops.remove(op.name);
                  }
                  _data['operators'] = ops.toList();
                }),
              ),
          ],
        ),
        const SizedBox(height: SpacingTokens.md),
        _dropdown('mode', '题型', {
          '': '符合本课范围的题型',
          'findResult': '求结果',
          'findMissing': '填未知数',
          'compare': '比较大小',
          'chain': '连续计算',
          'withBrackets': '含括号计算',
        }),
        _toggle('allowCarry', '允许进位', fallback: true),
        _toggle('allowBorrow', '允许退位', fallback: true),
        _toggle('allowRemainder', '允许余数'),
        _toggle('allowBrackets', '允许括号'),
        _toggle('allowNegative', '允许负数'),
        _field(
          'decimalPlaces',
          '最多小数位数（0 表示不用小数）',
          fallback: '0',
          numeric: true,
          max: 1,
        ),
        _field(
          'maxDenominator',
          '分母上限（1 表示不用分数）',
          fallback: '1',
          numeric: true,
          max: 3,
        ),
      ],
      if (kind != MathTextbookPracticeKind.engine &&
          kind != MathTextbookPracticeKind.parentTask &&
          kind != MathTextbookPracticeKind.dataTable)
        _dropdown('unit', '给定量的单位', {
          '': '不带单位',
          for (final unit in MathTextbookUnits.values.keys)
            unit: MathTextbookUnits.label(unit),
        }),
      if (kind == MathTextbookPracticeKind.unitConversion)
        _dropdown('toUnit', '换算到的单位', {
          for (final unit in MathTextbookUnits.values.keys)
            unit: MathTextbookUnits.label(unit),
        }),
      if (const [
        MathTextbookPracticeKind.circlePerimeter,
        MathTextbookPracticeKind.circleArea,
        MathTextbookPracticeKind.cylinderVolume,
      ].contains(kind))
        _field('pi', '本课规定的圆周率', fallback: '3.14', numeric: true, max: 32),
      if (kind == MathTextbookPracticeKind.dataTable)
        _dropdown('tableTask', '统计方式', {
          'total': '合计',
          'mean': '平均数',
          'max': '最大值',
          'difference': '最大值与最小值的差',
        }, fallback: _data['task'] as String? ?? 'total'),
      const SizedBox(height: SpacingTokens.md),
      OutlinedButton(
        onPressed: _generatePreview,
        child: const Text('试生成并核对巩固题'),
      ),
      if (_preview != null) ...[
        for (final item in _preview!)
          Padding(
            padding: const EdgeInsets.only(top: SpacingTokens.sm),
            child: ColoredCard(
              color: Theme.of(context).colorScheme.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MathTextbookContent(spans: item.blocks.first.spans),
                  Text(
                    item.exercise.needsParent
                        ? '核对方式：家长核对'
                        : '答案：${item.exercise.fields.first.rule.expected}${MathTextbookUnits.label(item.exercise.fields.first.rule.unit)}',
                  ),
                ],
              ),
            ),
          ),
      ],
    ];
  }
}

class _MathSourcePickerPage extends StatefulWidget {
  const _MathSourcePickerPage({
    required this.book,
    required this.lesson,
    required this.selected,
  });
  final Textbook book;
  final MathTextbookLesson lesson;
  final Set<String> selected;
  @override
  State<_MathSourcePickerPage> createState() => _MathSourcePickerPageState();
}

class _MathSourcePickerPageState extends State<_MathSourcePickerPage> {
  late final _selected = {...widget.selected};
  List<String> get _missing => _selected
      .where((id) => !widget.lesson.blocks.any((block) => block.id == id))
      .toList();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('选择原书内容（${_selected.length}）'),
      actions: [
        TextButton(
          onPressed: () {
            assertParentAccess(context);
            Navigator.pop(context, _selected);
          },
          child: const Text('完成'),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView.builder(
        padding: const EdgeInsets.all(SpacingTokens.md),
        itemCount: widget.lesson.blocks.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            if (_missing.isEmpty) return const SizedBox.shrink();
            return ColoredCard(
              color: Theme.of(context).colorScheme.error,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${_missing.length} 个引用的内容块已移除，请重新选择实际来源。'),
                  TextButton(
                    onPressed: () =>
                        setState(() => _selected.removeAll(_missing)),
                    child: const Text('移除失效引用'),
                  ),
                ],
              ),
            );
          }
          final block = widget.lesson.blocks[index - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTile(
                  iconColor: Theme.of(context).colorScheme.primary,
                  title:
                      'PDF 第 ${block.sources.map((s) => s.page).toSet().join('、')} 页',
                  subtitle: block.text.isEmpty ? '原书图形或待核区域' : block.text,
                  subtitleMaxLines: 3,
                  allowTapWithTrailing: true,
                  onTap: () => setState(() {
                    if (!_selected.add(block.id)) _selected.remove(block.id);
                  }),
                  trailing: Checkbox(
                    value: _selected.contains(block.id),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(block.id);
                      } else {
                        _selected.remove(block.id);
                      }
                    }),
                  ),
                ),
                if (_selected.contains(block.id))
                  TextButton.icon(
                    onPressed: () => context.push(
                      AppRoutes.textbookReadOf(widget.book.pdfSha256),
                      extra: block.sources.first.page,
                    ),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('打开这一页原书'),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _MathLearningJsonPage extends StatefulWidget {
  const _MathLearningJsonPage();
  @override
  State<_MathLearningJsonPage> createState() => _MathLearningJsonPageState();
}

class _MathLearningJsonPageState extends State<_MathLearningJsonPage> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('导入学习配置')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(SpacingTokens.md),
        children: [
          const Text('粘贴本课学习配置。导入后请重新对照原书确认覆盖，再保存和审核。'),
          const SizedBox(height: SpacingTokens.md),
          TextField(
            controller: _text,
            minLines: 10,
            maxLines: null,
            decoration: const InputDecoration(labelText: '学习配置 JSON'),
          ),
          const SizedBox(height: SpacingTokens.md),
          FilledButton(
            onPressed: () {
              assertParentAccess(context);
              Navigator.pop(context, _text.text);
            },
            child: const Text('校验并导入'),
          ),
        ],
      ),
    ),
  );
}
