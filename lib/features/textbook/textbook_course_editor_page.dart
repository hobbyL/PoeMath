import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_review.dart';
import 'package:poemath/domain/textbook_pinyin.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/textbook_course_content.dart';

class TextbookCourseEditorPage extends ConsumerStatefulWidget {
  const TextbookCourseEditorPage({
    super.key,
    required this.book,
    required this.pack,
    required this.node,
    this.previous,
    this.creating = false,
    this.clearInitialText = false,
    this.pinyinHints = const [],
    this.initialText,
  });
  final Textbook book;
  final TextbookCoursePack pack;
  final TextbookCourseNode node;
  final TextbookCoursePack? previous;
  final bool creating;
  final bool clearInitialText;
  final List<String> pinyinHints;
  final String? initialText;
  @override
  ConsumerState<TextbookCourseEditorPage> createState() =>
      _TextbookCourseEditorPageState();
}

class _SourceDraft {
  _SourceDraft({int page = 1, String? printed, this.status = 'manual'})
      : page = TextEditingController(text: '$page'),
        printed = TextEditingController(text: printed ?? '');
  final TextEditingController page;
  final TextEditingController printed;
  final String status;
  void dispose() {
    page.dispose();
    printed.dispose();
  }

  Map<String, dynamic> toJson() => {
        'pdfPage': int.tryParse(page.text),
        'printedPage': printed.text.trim().isEmpty ? null : printed.text.trim(),
        'extractionStatus': status,
      };
}

class _RangeDraft {
  _RangeDraft(this.paragraphId, int first, int last)
      : first = TextEditingController(text: '$first'),
        last = TextEditingController(text: '$last');
  String paragraphId;
  final TextEditingController first;
  final TextEditingController last;
  void dispose() {
    first.dispose();
    last.dispose();
  }
}

class _TextbookCourseEditorPageState
    extends ConsumerState<TextbookCourseEditorPage> {
  final _fields = <String, TextEditingController>{};
  final _allSources = <_SourceDraft>[];
  final _sources = <_SourceDraft>[];
  final _answerSources = <_SourceDraft>[];
  final _allRanges = <_RangeDraft>[];
  final _ranges = <_RangeDraft>[];
  final _allAnswers = <TextEditingController>[];
  final _answers = <TextEditingController>[];
  late String _requirement;
  late String _origin;
  late String _answerOrigin;
  late TextbookAnswerType _answerType;
  bool _saving = false;

  TextEditingController _field(String key) =>
      _fields.putIfAbsent(key, () => TextEditingController());
  void _addSource(
    List<_SourceDraft> destination, [
    TextbookSourcePage? source,
  ]) {
    final draft = _SourceDraft(
      page: source?.pdfPage ?? 1,
      printed: source?.printedPage,
      status: source?.extractionStatus ?? 'manual',
    );
    destination.add(draft);
    _allSources.add(draft);
  }

  void _addRange(String id, int first, int last) {
    final draft = _RangeDraft(id, first, last);
    _ranges.add(draft);
    _allRanges.add(draft);
  }

  void _addAnswer([String value = '']) {
    final controller = TextEditingController(text: value);
    _answers.add(controller);
    _allAnswers.add(controller);
  }

  @override
  void initState() {
    super.initState();
    final raw = widget.node.toJson();
    for (final key in [
      'title',
      'publisher',
      'editionLabel',
      'editionNotes',
      'publicationDate',
      'editionNumber',
      'printingDate',
      'printingNumber',
      'sourceUrl',
      'text',
      'instruction',
      'prompt',
      'lessonNumber',
    ]) {
      _field(key).text = raw[key]?.toString() ?? '';
    }
    _field('pinyin').text = widget.node is TextbookCourseParagraph
        ? textbookCoursePinyinForReview(
            widget.node as TextbookCourseParagraph,
          ).join(' ')
        : '';
    if (widget.clearInitialText) {
      for (final key in ['text', 'instruction', 'prompt']) {
        _field(key).clear();
      }
    }
    if (widget.initialText != null) {
      _field(
        widget.node is TextbookCourseExercise
            ? 'prompt'
            : widget.node is TextbookCourseRecitation
                ? 'instruction'
                : 'text',
      ).text = widget.initialText!;
    }
    _requirement = raw['requirement'] as String? ?? 'reading';
    _origin = raw['origin'] as String? ?? 'textbook';
    _answerOrigin = raw['answerOrigin'] as String? ?? 'none';
    _answerType = widget.node is TextbookCourseExercise
        ? (widget.node as TextbookCourseExercise).answerType
        : TextbookAnswerType.none;
    for (final source in widget.node.sources) {
      _addSource(_sources, source);
    }
    final node = widget.node;
    if (node is TextbookCourseRecitation) {
      for (final range in node.ranges) {
        _addRange(range.paragraphId, range.start + 1, range.end);
      }
    }
    if (node is TextbookCourseExercise) {
      for (final source in node.answerSources) {
        _addSource(_answerSources, source);
      }
      for (final answer in node.answers) {
        _addAnswer(answer);
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    for (final source in _allSources) {
      source.dispose();
    }
    for (final range in _allRanges) {
      range.dispose();
    }
    for (final answer in _allAnswers) {
      answer.dispose();
    }
    super.dispose();
  }

  TextbookCourseLesson get _lesson => widget.pack.lessons.firstWhere(
        (lesson) => lesson.recitations.any((node) => node.id == widget.node.id),
      );

  Map<String, dynamic> _changes() {
    final node = widget.node;
    final result = <String, dynamic>{
      'sources': _sources.map((source) => source.toJson()).toList(),
    };
    void take(String key) {
      result[key] = _field(key).text;
    }

    if (node is TextbookCourseEdition) {
      for (final key in [
        'title',
        'publisher',
        'editionLabel',
        'editionNotes',
        'sourceUrl',
      ]) {
        take(key);
      }
      for (final key in ['publicationDate', 'printingDate']) {
        result[key] =
            _field(key).text.trim().isEmpty ? null : _field(key).text.trim();
      }
      for (final key in ['editionNumber', 'printingNumber']) {
        final value = _field(key).text.trim();
        if (value.isNotEmpty && int.tryParse(value) == null) {
          throw const FormatException('版次和印次请填写整数');
        }
        result[key] = value.isEmpty ? null : int.parse(value);
      }
    }
    if (node is TextbookCourseUnit || node is TextbookCourseLesson) {
      take('title');
    }
    if (node is TextbookCourseLesson) {
      final number = _field('lessonNumber').text.trim();
      if (number.isNotEmpty && int.tryParse(number) == null) {
        throw const FormatException('课号请填写整数');
      }
      result['lessonNumber'] = number.isEmpty ? null : int.parse(number);
    }
    if (node is TextbookCourseParagraph) {
      take('text');
      final input = _field('pinyin').text.trim();
      result['pinyin'] = input.isEmpty ? null : input.split(RegExp(r'\s+'));
      if (node is TextbookCourseVocabulary) {
        result['requirement'] = _requirement;
      }
    }
    if (node is TextbookCourseRecitation) {
      take('instruction');
      result['ranges'] = [for (final range in _ranges) _rangeJson(range)];
    }
    if (node is TextbookCourseExercise) {
      take('prompt');
      result.addAll({
        'origin': _origin,
        'answerType': _answerType.name,
        'answerOrigin': _answerOrigin,
        'answers': [for (final answer in _answers) answer.text],
        'answerSources': _answerOrigin == 'textbook'
            ? _answerSources.map((source) => source.toJson()).toList()
            : <Map<String, dynamic>>[],
      });
    }
    return result;
  }

  Map<String, dynamic> _rangeJson(_RangeDraft range) {
    final paragraph =
        _lesson.paragraphs.firstWhere((p) => p.id == range.paragraphId);
    final first = int.tryParse(range.first.text);
    final last = int.tryParse(range.last.text);
    final runes = paragraph.text.runes.toList();
    if (first == null ||
        last == null ||
        first < 1 ||
        first > last ||
        last > runes.length) {
      throw FormatException('背诵范围请填写 1–${runes.length} 内的起止字符，起点不能大于终点');
    }
    return {
      'paragraphId': paragraph.id,
      'start': first - 1,
      'end': last,
      'textSha256': textbookTextDigest(
        String.fromCharCodes(runes.sublist(first - 1, last)),
      ),
    };
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final pack =
          editTextbookCourseNode(widget.pack, widget.node.id, _changes());
      await ref
          .read(textbookCourseRepositoryProvider)
          .save(widget.book, pack, previous: widget.previous ?? widget.pack);
      if (mounted) Navigator.pop(context, pack);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '教材内容保存失败',
        tag: 'TextbookCourse',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException ? error.message : '保存失败，请重试；填写内容已保留',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _input(
    String key,
    String label, {
    String? helper,
    bool multiline = false,
    bool number = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: SpacingTokens.md),
        child: TextField(
          controller: _field(key),
          enabled: !_saving,
          minLines: multiline ? 3 : 1,
          maxLines: multiline ? null : 1,
          keyboardType: number
              ? TextInputType.number
              : multiline
                  ? TextInputType.multiline
                  : TextInputType.text,
          decoration: InputDecoration(
            labelText: label,
            helperText: helper,
            helperMaxLines: 5,
            alignLabelWithHint: multiline,
          ),
        ),
      );
  Widget _heading(String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
        child: Text(label, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _sourceFields(List<_SourceDraft> sources, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(label),
          const Text('填实际 PDF 页码；印刷页未知可留空。'),
          for (final (index, source) in sources.indexed)
            Padding(
              key: ObjectKey(source),
              padding: const EdgeInsets.only(top: SpacingTokens.sm),
              child: Column(
                children: [
                  TextField(
                    controller: source.page,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration:
                        InputDecoration(labelText: '来源 ${index + 1} · PDF 页码'),
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  TextField(
                    controller: source.printed,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: '印刷页码（选填）'),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () => setState(() => sources.remove(source)),
                      icon: const Icon(Icons.remove_circle_outline),
                      label: const Text('移除此来源'),
                    ),
                  ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed:
                _saving ? null : () => setState(() => _addSource(sources)),
            icon: const Icon(Icons.add),
            label: const Text('添加来源页'),
          ),
        ],
      );

  Widget _recitationFields() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _input('instruction', '背诵要求', multiline: true),
          const Text('起止位置从 1 开始，包含标点和空白；下方实时显示所选文字。'),
          for (final (index, range) in _ranges.indexed)
            Column(
              key: ObjectKey(range),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heading('范围 ${index + 1}'),
                DropdownButtonFormField<String>(
                  initialValue: range.paragraphId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '课文段落'),
                  items: [
                    for (final (i, paragraph) in _lesson.paragraphs.indexed)
                      DropdownMenuItem(
                        value: paragraph.id,
                        child: Text(
                          '第 ${i + 1} 段 · ${paragraph.text}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                            range.paragraphId = value!;
                            range.first.text = '1';
                            range.last.text =
                                '${_lesson.paragraphs.firstWhere((p) => p.id == value).text.runes.length}';
                          }),
                ),
                const SizedBox(height: SpacingTokens.md),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: range.first,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: '起始字符'),
                      ),
                    ),
                    const SizedBox(width: SpacingTokens.md),
                    Expanded(
                      child: TextField(
                        controller: range.last,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: '结束字符'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: SpacingTokens.sm),
                Text(_rangePreview(range)),
                TextButton.icon(
                  onPressed: _saving
                      ? null
                      : () => setState(() => _ranges.remove(range)),
                  icon: const Icon(Icons.remove_circle_outline),
                  label: const Text('移除此范围'),
                ),
              ],
            ),
          TextButton.icon(
            onPressed: _saving || _lesson.paragraphs.isEmpty
                ? null
                : () => setState(
                      () => _addRange(
                        _lesson.paragraphs.first.id,
                        1,
                        _lesson.paragraphs.first.text.runes.length,
                      ),
                    ),
            icon: const Icon(Icons.add),
            label: const Text('添加背诵范围'),
          ),
        ],
      );

  String _rangePreview(_RangeDraft range) {
    try {
      final raw = _rangeJson(range);
      final paragraph =
          _lesson.paragraphs.firstWhere((p) => p.id == range.paragraphId);
      return String.fromCharCodes(
        paragraph.text.runes
            .toList()
            .sublist(raw['start'] as int, raw['end'] as int),
      );
    } on FormatException {
      return '请填写有效范围以预览选文';
    }
  }

  Widget _exerciseFields() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _input('prompt', '题目', multiline: true),
          DropdownButtonFormField<String>(
            initialValue: _origin,
            decoration: const InputDecoration(labelText: '题目来源'),
            items: const [
              DropdownMenuItem(value: 'textbook', child: Text('原书习题')),
              DropdownMenuItem(value: 'curated', child: Text('另行编写')),
            ],
            onChanged:
                _saving ? null : (value) => setState(() => _origin = value!),
          ),
          const SizedBox(height: SpacingTokens.md),
          DropdownButtonFormField<TextbookAnswerType>(
            initialValue: _answerType,
            decoration: const InputDecoration(labelText: '答案类型'),
            items: [
              for (final entry in textbookCourseAnswerLabels.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => _answerType = value!),
          ),
          const SizedBox(height: SpacingTokens.md),
          DropdownButtonFormField<String>(
            initialValue: _answerOrigin,
            decoration: const InputDecoration(labelText: '答案来源'),
            items: const [
              DropdownMenuItem(value: 'none', child: Text('未提供答案')),
              DropdownMenuItem(value: 'textbook', child: Text('原书')),
              DropdownMenuItem(
                value: 'reviewerReference',
                child: Text('审核者参考要点'),
              ),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => _answerOrigin = value!),
          ),
          _heading('答案或参考要点'),
          for (final (i, answer) in _answers.indexed)
            Column(
              key: ObjectKey(answer),
              children: [
                TextField(
                  controller: answer,
                  enabled: !_saving,
                  minLines: 2,
                  maxLines: null,
                  decoration: InputDecoration(labelText: '答案 ${i + 1}'),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _answers.remove(answer)),
                    child: const Text('移除此答案'),
                  ),
                ),
              ],
            ),
          TextButton.icon(
            onPressed: _saving ? null : () => setState(() => _addAnswer()),
            icon: const Icon(Icons.add),
            label: const Text('添加答案'),
          ),
          if (_answerOrigin == 'textbook')
            _sourceFields(_answerSources, '答案来源页'),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.creating ? '添加内容' : '编辑内容')),
        body: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.all(SpacingTokens.md),
            children: [
              const Text('保存后，受影响的审核需要重新核对。正文修改还会使关联的背诵审核失效。'),
              const SizedBox(height: SpacingTokens.lg),
              if (widget.pinyinHints.isNotEmpty) ...[
                const Text('原书局部注音线索（请逐字对照原页补齐）'),
                SelectableText(widget.pinyinHints.join(' · ')),
                const SizedBox(height: SpacingTokens.md),
              ],
              if (node is TextbookCourseEdition) ...[
                _input('title', '书名'),
                _input('publisher', '出版社'),
                _input('editionLabel', '版本说明'),
                _input('editionNotes', '版本依据', multiline: true),
                _input(
                  'publicationDate',
                  '出版年月（选填）',
                  helper: '格式：2024-09；原书未载明时留空',
                ),
                _input('editionNumber', '版次（选填）', number: true),
                _input(
                  'printingDate',
                  '印刷年月（选填）',
                  helper: '格式：2024-09；原书未载明时留空',
                ),
                _input('printingNumber', '印次（选填）', number: true),
                _input('sourceUrl', '原书来源网址'),
              ],
              if (node is TextbookCourseUnit || node is TextbookCourseLesson)
                _input('title', '标题'),
              if (node is TextbookCourseLesson)
                _input('lessonNumber', '课号（选填）', number: true),
              if (node is TextbookCourseParagraph) ...[
                _input(
                  'text',
                  node is TextbookCourseVocabulary ? '字词内容' : '正文',
                  multiline: true,
                ),
                _input(
                  'pinyin',
                  '逐字注音',
                  multiline: true,
                  helper: '每字一个拼音，以空格分隔；标点原样占位。支持音调或数字声调，如：chūn fēng 。',
                ),
                if (node is TextbookCourseVocabulary)
                  DropdownButtonFormField<String>(
                    initialValue: _requirement,
                    decoration: const InputDecoration(labelText: '原书要求'),
                    items: [
                      for (final entry
                          in textbookCourseRequirementLabels.entries)
                        if (node.requirement == 'reading' ||
                                node.requirement == 'dictation'
                            ? ['reading', 'dictation'].contains(entry.key)
                            : node.requirement == entry.key)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _requirement = value!),
                  ),
              ],
              if (node is TextbookCourseRecitation) _recitationFields(),
              if (node is TextbookCourseExercise) _exerciseFields(),
              _sourceFields(_sources, '原书来源页'),
              const SizedBox(height: SpacingTokens.lg),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? '保存中…' : '保存修改'),
            ),
          ),
        ),
      ),
    );
  }
}
