import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/domain/math_textbook_editing.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_content.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_source_preview.dart';

String mathTextbookBlockLabel(MathTextbookBlockKind kind) => switch (kind) {
  MathTextbookBlockKind.text => '文字',
  MathTextbookBlockKind.formula => '公式',
  MathTextbookBlockKind.illustration => '图表 / 待补内容',
  MathTextbookBlockKind.exercise => '练习题组',
  MathTextbookBlockKind.example => '例题与讲解',
  MathTextbookBlockKind.heading => '内容标题',
  MathTextbookBlockKind.sourcePage => '整页对照',
};

class MathTextbookBlockEditorPage extends StatefulWidget {
  const MathTextbookBlockEditorPage({
    super.key,
    required this.book,
    required this.block,
    required this.startPage,
    required this.endPage,
    this.onReadingChanged,
  });
  final Textbook book;
  final MathTextbookBlock block;
  final int startPage;
  final int endPage;
  final ValueChanged<bool>? onReadingChanged;
  @override
  State<MathTextbookBlockEditorPage> createState() =>
      _MathTextbookBlockEditorPageState();
}

class _SpanDraft {
  _SpanDraft(MathTextbookSpan span)
    : text = span.text == null ? null : TextEditingController(text: span.text),
      expression = span.expression;
  final TextEditingController? text;
  MathTextbookExpression? expression;
  MathTextbookSpan get value => text == null
      ? MathTextbookSpan.math(expression!)
      : MathTextbookSpan.text(text!.text);
  void dispose() => text?.dispose();
}

class _MathTextbookBlockEditorPageState
    extends State<MathTextbookBlockEditorPage> {
  late final _spans = widget.block.spans.map(_SpanDraft.new).toList();
  late final _note = TextEditingController(text: widget.block.parentNote);
  late final _number = TextEditingController(
    text: widget.block.exerciseNumber ?? '',
  );
  late final _sources = [...widget.block.sources];
  late MathTextbookBlockKind _kind = widget.block.kind;
  late bool _sourceLayout = widget.block.sourceLayout;
  int _selectedSource = 0;
  late RangeValues _horizontal = RangeValues(
    _sources.first.left,
    _sources.first.right,
  );
  late RangeValues _vertical = RangeValues(
    _sources.first.top,
    _sources.first.bottom,
  );
  bool _changed = false;
  String? _error;

  void _markChanged(String _) {
    if (!_changed) setState(() => _changed = true);
  }

  void _selectSource(int index) => setState(() {
    _selectedSource = index;
    _horizontal = RangeValues(_sources[index].left, _sources[index].right);
    _vertical = RangeValues(_sources[index].top, _sources[index].bottom);
  });

  Future<void> _formula([_SpanDraft? draft]) async {
    final result = await showDialog<MathTextbookExpression>(
      context: context,
      builder: (_) => MathTextbookExpressionDialog(initial: draft?.expression),
    );
    if (!mounted || result == null) return;
    assertParentAccess(context);
    setState(() {
      if (draft == null) {
        _spans.add(_SpanDraft(MathTextbookSpan.math(result)));
      } else {
        draft.expression = result;
      }
      _changed = true;
    });
  }

  void _applyRegion({bool fullPage = false}) {
    final previous = _sources[_selectedSource];
    if (!fullPage &&
        (_horizontal.end - _horizontal.start < .002 ||
            _vertical.end - _vertical.start < .002)) {
      setState(() => _error = '所选区域太小，请保留完整内容');
      return;
    }
    setState(() {
      _sources[_selectedSource] = MathTextbookRegion(
        page: previous.page,
        printedPage: previous.printedPage,
        left: fullPage ? 0 : _horizontal.start,
        right: fullPage ? 1 : _horizontal.end,
        top: fullPage ? 0 : _vertical.start,
        bottom: fullPage ? 1 : _vertical.end,
      );
      _changed = true;
      _error = null;
    });
    _selectSource(_selectedSource);
  }

  Future<void> _readSource() async {
    widget.onReadingChanged?.call(true);
    try {
      await context.push(
        AppRoutes.textbookReadOf(widget.book.pdfSha256),
        extra: _sources[_selectedSource].page,
      );
    } finally {
      widget.onReadingChanged?.call(false);
    }
  }

  void _save() {
    try {
      assertParentAccess(context);
      final block = MathTextbookBlock.fromJson(
        MathTextbookBlock(
          id: widget.block.id,
          kind: _kind,
          spans: _spans.map((s) => s.value).where((s) => s.text != '').toList(),
          sources: _sources,
          warnings: widget.block.warnings,
          exerciseNumber: _number.text.trim().isEmpty
              ? null
              : _number.text.trim(),
          parentNote: _note.text.trim(),
          sourceLayout: _sourceLayout,
        ).toJson(),
      );
      Navigator.pop(context, block);
    } on Object catch (error) {
      setState(
        () => _error = error is FormatException
            ? error.message.toString()
            : '无法应用修改，请重新打开后重试',
      );
    }
  }

  Future<void> _leave() async {
    if (_changed) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('放弃这处修改？'),
          content: const Text('返回后保留修改前的内容。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('继续修改'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('放弃修改'),
            ),
          ],
        ),
      );
      if (!mounted || discard != true) return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    for (final span in _spans) {
      span.dispose();
    }
    _note.dispose();
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = _sources[_selectedSource];
    return PopScope<MathTextbookBlock>(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('对照并修改内容'),
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
              MathTextbookSourcePreview(book: widget.book, source: source),
              const SizedBox(height: SpacingTokens.sm),
              TextButton.icon(
                onPressed: _readSource,
                icon: const Icon(Icons.menu_book_outlined),
                label: Text('打开原书 PDF 第 ${source.page} 页'),
              ),
              ExpansionTile(
                title: const Text('调整原书对照范围'),
                children: [
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    itemHeight: null,
                    key: ValueKey('source-$_selectedSource-${_sources.length}'),
                    initialValue: _selectedSource,
                    decoration: const InputDecoration(labelText: '来源区域'),
                    items: [
                      for (var i = 0; i < _sources.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            '区域 ${i + 1} · PDF 第 ${_sources[i].page} 页',
                          ),
                        ),
                    ],
                    onChanged: (index) {
                      if (index != null) _selectSource(index);
                    },
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  const Text('左右边界'),
                  RangeSlider(
                    values: _horizontal,
                    divisions: 100,
                    labels: RangeLabels(
                      '${(_horizontal.start * 100).round()}%',
                      '${(_horizontal.end * 100).round()}%',
                    ),
                    onChanged: (values) => setState(() => _horizontal = values),
                  ),
                  const Text('上下边界'),
                  RangeSlider(
                    values: _vertical,
                    divisions: 100,
                    labels: RangeLabels(
                      '${(_vertical.start * 100).round()}%',
                      '${(_vertical.end * 100).round()}%',
                    ),
                    onChanged: (values) => setState(() => _vertical = values),
                  ),
                  Wrap(
                    spacing: SpacingTokens.sm,
                    children: [
                      TextButton(
                        onPressed: _applyRegion,
                        child: const Text('应用对照范围'),
                      ),
                      TextButton(
                        onPressed: () => _applyRegion(fullPage: true),
                        child: const Text('恢复整页范围'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: SpacingTokens.md),
              DropdownButtonFormField<MathTextbookBlockKind>(
                isExpanded: true,
                itemHeight: null,
                initialValue: _kind,
                decoration: const InputDecoration(labelText: '内容类型'),
                items: [
                  for (final kind in MathTextbookBlockKind.values.where(
                    (k) =>
                        k != MathTextbookBlockKind.sourcePage ||
                        widget.block.kind == k,
                  ))
                    DropdownMenuItem(
                      value: kind,
                      child: Text(mathTextbookBlockLabel(kind)),
                    ),
                ],
                onChanged: widget.block.kind == MathTextbookBlockKind.sourcePage
                    ? null
                    : (kind) => setState(() {
                        _kind = kind!;
                        _changed = true;
                      }),
              ),
              const SizedBox(height: SpacingTokens.md),
              AppTile(
                icon: Icons.auto_stories_outlined,
                iconColor: theme.colorScheme.primary,
                title: '保留原书图文排版',
                subtitle: '开启后先显示完整原图，文字可展开查看。',
                trailing: Switch(
                  value: _sourceLayout,
                  onChanged: (value) => setState(() {
                    _sourceLayout = value;
                    _changed = true;
                  }),
                ),
              ),
              const SizedBox(height: SpacingTokens.md),
              TextField(
                controller: _number,
                maxLength: 40,
                decoration: const InputDecoration(labelText: '题号（选填）'),
                onChanged: _markChanged,
              ),
              for (var i = 0; i < _spans.length; i++) ...[
                ColoredCard(
                  key: ObjectKey(_spans[i]),
                  color: theme.colorScheme.primary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppTile(
                        flat: true,
                        iconColor: theme.colorScheme.primary,
                        title:
                            '${_spans[i].text == null ? '公式' : '文字'}段 ${i + 1}',
                        subtitle: '',
                        trailing: PopupMenuButton<String>(
                          tooltip: '调整片段顺序',
                          itemBuilder: (_) => [
                            if (i > 0)
                              const PopupMenuItem(
                                value: 'up',
                                child: Text('上移'),
                              ),
                            if (i < _spans.length - 1)
                              const PopupMenuItem(
                                value: 'down',
                                child: Text('下移'),
                              ),
                            const PopupMenuItem(
                              value: 'remove',
                              child: Text('移除此片段'),
                            ),
                          ],
                          onSelected: (action) => setState(() {
                            final span = _spans.removeAt(i);
                            if (action == 'remove') {
                              span.dispose();
                            } else {
                              _spans.insert(
                                action == 'up' ? i - 1 : i + 1,
                                span,
                              );
                            }
                            _changed = true;
                          }),
                        ),
                      ),
                      if (_spans[i].text != null)
                        TextField(
                          controller: _spans[i].text,
                          minLines: 2,
                          maxLines: null,
                          maxLength: 20000,
                          decoration: const InputDecoration(labelText: '文字内容'),
                          onChanged: _markChanged,
                        )
                      else ...[
                        MathTextbookContent(
                          key: ValueKey('math-span-$i'),
                          spans: [_spans[i].value],
                        ),
                        TextButton(
                          onPressed: () => _formula(_spans[i]),
                          child: const Text('修改公式'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: SpacingTokens.sm),
              ],
              Wrap(
                spacing: SpacingTokens.sm,
                runSpacing: SpacingTokens.sm,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _spans.add(_SpanDraft(const MathTextbookSpan.text('')));
                      _changed = true;
                    }),
                    icon: const Icon(Icons.text_fields),
                    label: const Text('添加文字'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _formula,
                    icon: const Icon(Icons.functions),
                    label: const Text('添加公式'),
                  ),
                ],
              ),
              const SizedBox(height: SpacingTokens.md),
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: null,
                maxLength: 5000,
                decoration: const InputDecoration(
                  labelText: '家长补充说明',
                  hintText: '图表含义、未识别内容或需要孩子注意的地方',
                ),
                onChanged: _markChanged,
              ),
              if (widget.block.warnings.isNotEmpty) ...[
                const SizedBox(height: SpacingTokens.sm),
                Text('整理时的待核提示：${widget.block.warnings.join('；')}'),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: SpacingTokens.sm,
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: SpacingTokens.md),
              FilledButton(onPressed: _save, child: const Text('应用修改')),
              const SizedBox(height: SpacingTokens.sm),
              const Text('应用后返回课时，点击“保存草稿”写入本机。'),
            ],
          ),
        ),
      ),
    );
  }
}

class MathTextbookExpressionDialog extends StatefulWidget {
  const MathTextbookExpressionDialog({super.key, this.initial});
  final MathTextbookExpression? initial;
  @override
  State<MathTextbookExpressionDialog> createState() =>
      _MathTextbookExpressionDialogState();
}

class _MathTextbookExpressionDialogState
    extends State<MathTextbookExpressionDialog> {
  List<String> get _initialRows => switch (widget.initial) {
    MathTextbookVerticalAddition(:final rows) => rows,
    MathTextbookVerticalArithmetic(:final rows) => rows,
    _ => const [],
  };
  late bool _vertical = _initialRows.isNotEmpty;
  late String _operation = switch (widget.initial) {
    MathTextbookVerticalArithmetic(:final operation) => operation,
    _ => '+',
  };
  late final _input = TextEditingController(
    text: _vertical ? '' : widget.initial?.readable ?? '',
  );
  late final _rows = [
    for (var i = 0; i < 3; i++)
      TextEditingController(text: _initialRows.isEmpty ? '' : _initialRows[i]),
  ];
  late final _carries = [
    for (var i = 0; i < 12; i++)
      TextEditingController(
        text: widget.initial is MathTextbookVerticalAddition
            ? (widget.initial as MathTextbookVerticalAddition).carries
                      .where((c) => c.columnFromRight == i)
                      .firstOrNull
                      ?.value
                      .toString() ??
                  ''
            : '',
      ),
  ];
  late final _annotations = [
    if (widget.initial case MathTextbookVerticalArithmetic(:final annotations))
      for (final annotation in annotations)
        _VerticalAnnotationInput(annotation),
  ];
  String? _error;
  bool get _showCarries =>
      _operation == '+' &&
      widget.initial is! MathTextbookVerticalArithmetic &&
      _annotations.isEmpty;
  int get _width => _rows
      .map((r) => r.text.length)
      .fold(1, (a, b) => a > b ? a : b)
      .clamp(1, 12);
  MathTextbookExpression _value() {
    if (!_vertical) return parseMathTextbookExpression(_input.text);
    final rows = _rows.map((r) => r.text).toList();
    final carries = [
      if (_showCarries)
        for (var i = 0; i < _width; i++)
          if (_carries[i].text.trim().isNotEmpty)
            MathTextbookCarry(int.tryParse(_carries[i].text.trim()) ?? -1, i),
    ];
    final completeAddition =
        _showCarries &&
        rows.every((r) => RegExp(r'^ *\d+$').hasMatch(r)) &&
        !rows.last.startsWith(' ') &&
        rows.last.length == _width;
    return MathTextbookExpression.fromJson(
      (completeAddition
              ? MathTextbookVerticalAddition(
                  rows.map((r) => r.trim()).toList(),
                  carries,
                )
              : MathTextbookVerticalArithmetic(
                  rows,
                  operation: _operation,
                  annotations: [
                    for (final carry in carries)
                      MathTextbookVerticalAnnotation(
                        value: '${carry.value}',
                        row: 2,
                        columnFromRight: carry.columnFromRight,
                      ),
                    for (final input in _annotations)
                      if (input.value.text.trim().isNotEmpty) input.annotation,
                  ],
                ))
          .toJson(),
    );
  }

  void _addAnnotation() => setState(() {
    if (_showCarries) {
      for (var i = 0; i < _width; i++) {
        if (_carries[i].text.trim().isNotEmpty) {
          _annotations.add(
            _VerticalAnnotationInput(
              MathTextbookVerticalAnnotation(
                value: _carries[i].text.trim(),
                row: 2,
                columnFromRight: i,
              ),
            ),
          );
          _carries[i].clear();
        }
      }
    }
    _annotations.add(
      _VerticalAnnotationInput(
        const MathTextbookVerticalAnnotation(
          value: '',
          row: 0,
          columnFromRight: 0,
        ),
      ),
    );
    _error = null;
  });
  @override
  void dispose() {
    _input.dispose();
    for (final field in [..._rows, ..._carries]) {
      field.dispose();
    }
    for (final input in _annotations) {
      input.value.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    MathTextbookExpression? preview;
    try {
      preview = _value();
    } on FormatException {
      /* 留给输入与保存校验。 */
    }
    return AlertDialog(
      title: const Text('填写公式'),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<bool>(
                isExpanded: true,
                itemHeight: null,
                initialValue: _vertical,
                decoration: const InputDecoration(labelText: '公式形式'),
                items: const [
                  DropdownMenuItem(value: false, child: Text('横式 / 分数 / 上标')),
                  DropdownMenuItem(value: true, child: Text('竖式')),
                ],
                onChanged: (value) => setState(() {
                  _vertical = value!;
                  _error = null;
                }),
              ),
              const SizedBox(height: SpacingTokens.md),
              if (!_vertical) ...[
                const Text('示例：1/4、2又1/3、cm^2、7/3 = 7 ÷ 3。'),
                TextField(
                  controller: _input,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 2048,
                  decoration: const InputDecoration(labelText: '算式'),
                  onChanged: (_) => setState(() => _error = null),
                ),
              ] else ...[
                DropdownButtonFormField<String>(
                  initialValue: _operation,
                  isExpanded: true,
                  itemHeight: null,
                  decoration: const InputDecoration(labelText: '运算'),
                  items: const [
                    DropdownMenuItem(value: '+', child: Text('加法 ＋')),
                    DropdownMenuItem(value: '-', child: Text('减法 −')),
                    DropdownMenuItem(value: '×', child: Text('乘法 ×')),
                  ],
                  onChanged: (value) => setState(() {
                    _operation = value!;
                    _error = null;
                  }),
                ),
                const SizedBox(height: SpacingTokens.sm),
                const Text('按原书数位对齐，空位用空格保留；横线下可以留空。'),
                for (var i = 0; i < 3; i++)
                  TextField(
                    controller: _rows[i],
                    maxLength: 12,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      labelText: const ['第一行', '第二行', '横线下的结果'][i],
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                if (_showCarries) ...[
                  const Text('进位写在原书对应数位；没有进位时留空。'),
                  for (var i = 0; i < _width; i++)
                    TextField(
                      controller: _carries[i],
                      maxLength: 1,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                            '${i == 0
                                ? '个位'
                                : i == 1
                                ? '十位'
                                : i == 2
                                ? '百位'
                                : '右起第 ${i + 1} 位'}进位',
                      ),
                      onChanged: (_) => setState(() => _error = null),
                    ),
                ],
                for (final input in _annotations)
                  Padding(
                    padding: const EdgeInsets.only(top: SpacingTokens.sm),
                    child: ColoredCard(
                      key: ObjectKey(input),
                      color: Theme.of(context).colorScheme.primary,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Expanded(child: Text('进位 / 借位标注')),
                              IconButton(
                                tooltip: '移除标注',
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(() {
                                  _annotations.remove(input);
                                  input.value.dispose();
                                  _error = null;
                                }),
                              ),
                            ],
                          ),
                          TextField(
                            controller: input.value,
                            maxLength: 2,
                            decoration: const InputDecoration(
                              labelText: '标注数字或圆点',
                            ),
                            onChanged: (_) => setState(() => _error = null),
                          ),
                          DropdownButtonFormField<int>(
                            initialValue: input.row,
                            isExpanded: true,
                            itemHeight: null,
                            decoration: const InputDecoration(labelText: '位置'),
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('第一行上方')),
                              DropdownMenuItem(value: 1, child: Text('第二行上方')),
                              DropdownMenuItem(value: 2, child: Text('横线上方')),
                            ],
                            onChanged: (value) => setState(() {
                              input.row = value!;
                              _error = null;
                            }),
                          ),
                          DropdownButtonFormField<int>(
                            initialValue: input.columnFromRight < _width
                                ? input.columnFromRight
                                : null,
                            isExpanded: true,
                            itemHeight: null,
                            decoration: const InputDecoration(labelText: '数位'),
                            items: [
                              for (var column = 0; column < _width; column++)
                                DropdownMenuItem(
                                  value: column,
                                  child: Text('右起第 ${column + 1} 列'),
                                ),
                            ],
                            onChanged: (value) => setState(() {
                              input.columnFromRight = value!;
                              _error = null;
                            }),
                          ),
                          DropdownButtonFormField<int>(
                            initialValue: input.level,
                            isExpanded: true,
                            itemHeight: null,
                            decoration: const InputDecoration(
                              labelText: '上下层次',
                            ),
                            items: [
                              for (var level = 0; level < 4; level++)
                                DropdownMenuItem(
                                  value: level,
                                  child: Text('从上往下第 ${level + 1} 层'),
                                ),
                            ],
                            onChanged: (value) => setState(() {
                              input.level = value!;
                              _error = null;
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                TextButton.icon(
                  onPressed: _annotations.length >= 36 ? null : _addAnnotation,
                  icon: const Icon(Icons.add),
                  label: const Text('添加标注'),
                ),
              ],
              if (preview != null) ...[
                const SizedBox(height: SpacingTokens.md),
                const Text('排版预览'),
                const SizedBox(height: SpacingTokens.sm),
                MathTextbookContent(spans: [MathTextbookSpan.math(preview)]),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            try {
              Navigator.pop(context, _value());
            } on FormatException catch (error) {
              setState(() => _error = error.message.toString());
            }
          },
          child: const Text('使用此公式'),
        ),
      ],
    );
  }
}

class _VerticalAnnotationInput {
  _VerticalAnnotationInput(MathTextbookVerticalAnnotation annotation)
    : value = TextEditingController(text: annotation.value),
      row = annotation.row,
      columnFromRight = annotation.columnFromRight,
      level = annotation.level;
  final TextEditingController value;
  int row;
  int columnFromRight;
  int level;
  MathTextbookVerticalAnnotation get annotation =>
      MathTextbookVerticalAnnotation(
        value: value.text.trim(),
        row: row,
        columnFromRight: columnFromRight,
        level: level,
      );
}
