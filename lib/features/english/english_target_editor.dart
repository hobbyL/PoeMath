import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/features/english/english_audio.dart';
import 'package:poemath/features/english/english_providers.dart';
import 'package:poemath/features/english/english_widgets.dart';

class EnglishTargetEditor extends ConsumerStatefulWidget {
  const EnglishTargetEditor({
    super.key,
    required this.bookId,
    required this.lessonId,
    required this.targetId,
  });
  final String bookId, lessonId, targetId;
  @override
  ConsumerState<EnglishTargetEditor> createState() =>
      _EnglishTargetEditorState();
}

class _EnglishTargetEditorState extends ConsumerState<EnglishTargetEditor>
    with WidgetsBindingObserver {
  final _text = TextEditingController(),
      _meaning = TextEditingController(),
      _options = TextEditingController(),
      _answers = TextEditingController(),
      _page = TextEditingController(),
      _printed = TextEditingController(),
      _left = TextEditingController(text: '0'),
      _top = TextEditingController(text: '0'),
      _right = TextEditingController(text: '1'),
      _bottom = TextEditingController(text: '1');
  EnglishTargetKind _kind = EnglishTargetKind.vocabulary;
  EnglishExerciseKind _exercise = EnglishExerciseKind.oral;
  bool _approved = false,
      _spelling = false,
      _case = false,
      _picture = false,
      _pictureReviewed = false,
      _saving = false;
  String? _heardFingerprint, _heardVoice;
  EnglishTarget? _original;
  EnglishCourse? _base;
  int _position = 0;
  final _profileRevision = ProfileScope.revision;
  late final EnglishAudio _audio;
  late final _audioKey = englishAudioKey(widget.bookId);
  @override
  void initState() {
    super.initState();
    _audio = ref.read(englishAudioProvider(_audioKey));
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_audio.stop());
  }

  void _init(EnglishCourse course, EnglishLesson lesson) {
    if (_base != null) return;
    _base = course;
    _original = course.target(widget.lessonId, widget.targetId);
    final t = _original;
    _position = t == null ? lesson.targets.length : lesson.targets.indexOf(t);
    _page.text = '${t?.sources.first.page ?? lesson.startPage}';
    if (t == null) return;
    _text.text = t.text;
    _meaning.text = t.meaning;
    _options.text = t.options.join('\n');
    _answers.text = t.answers.join('\n');
    _kind = t.kind;
    _exercise = t.exerciseKind;
    _approved = t.approved;
    _spelling = t.spellingEnabled;
    _case = t.caseSensitive;
    _picture = t.picture != null;
    _pictureReviewed = t.pictureReviewed;
    final source = t.picture ?? t.sources.first;
    _printed.text = source.printedPage ?? '';
    _left.text = '${source.left}';
    _top.text = '${source.top}';
    _right.text = '${source.right}';
    _bottom.text = '${source.bottom}';
  }

  Future<void> _pickKind() async {
    final selected = await showModalBottomSheet<EnglishTargetKind>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: SpacingTokens.md),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SpacingTokens.md,
                ),
                child: Text(
                  '选择内容类型',
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetContext).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: SpacingTokens.sm),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.sm,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final kind in EnglishTargetKind.values)
                        AppTile(
                          flat: true,
                          flatTrailingEdgeAligned: true,
                          selected: kind == _kind,
                          iconColor: Theme.of(sheetContext).colorScheme.primary,
                          trailingIcon: kind == _kind
                              ? Icons.check_rounded
                              : Icons.chevron_right,
                          title: kind.label,
                          subtitle: '',
                          onTap: () => Navigator.pop(sheetContext, kind),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: SpacingTokens.md),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted || selected == _kind) return;
    setState(() => _kind = selected);
  }

  EnglishTarget _draft(Textbook book) {
    final page = int.tryParse(_page.text) ?? 0;
    if (page < 1 || page > book.pageCount) {
      throw const FormatException('来源页码超出原书范围');
    }
    final source = EnglishSource.fromJson({
      'page': page,
      'printedPage': _printed.text.trim().isEmpty ? null : _printed.text.trim(),
      'left': double.tryParse(_left.text),
      'top': double.tryParse(_top.text),
      'right': double.tryParse(_right.text),
      'bottom': double.tryParse(_bottom.text),
    });
    List<String> lines(String s) =>
        s.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final oldSources = _original?.sources ?? [];
    return EnglishTarget.fromJson(
      EnglishTarget(
        id: widget.targetId,
        kind: _kind,
        text: _text.text.trim(),
        meaning: _meaning.text.trim(),
        role: _original?.role ?? '',
        sources: [source, ...oldSources.skip(1)],
        origin: _original?.origin ?? 'parent',
        options: lines(_options.text),
        answers: lines(_answers.text),
        exerciseKind: _exercise,
        caseSensitive: _case,
        spellingEnabled: _spelling,
        picture: _picture ? source : null,
        pictureReviewed: _picture && _pictureReviewed,
        reviewDigest: _original?.reviewDigest,
        audioReview: _original?.audioReview,
      ).toJson(),
    );
  }

  void _check(void Function() authorized) {
    assertParentAccess(context);
    authorized();
    if (ProfileScope.revision != _profileRevision ||
        ref.read(englishBookProvider(widget.bookId)) == null) {
      throw StateError('档案或课本已变化');
    }
  }

  Future<void> _save(Textbook book, EnglishLesson lesson) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      assertParentAccess(context);
      final authorized = ParentAccessService.instance.captureAuthorization();
      var target = _draft(book);
      if (_approved) {
        target = target.approve(
          voiceKey: target.fingerprint == _heardFingerprint
              ? _heardVoice
              : null,
        );
      } else {
        target = target.change({'reviewDigest': null, 'audioReview': null});
      }
      final targets = [...lesson.targets]
        ..removeWhere((t) => t.id == widget.targetId);
      targets.insert(_position.clamp(0, targets.length), target);
      await ref
          .read(englishCourseRepositoryProvider)
          .saveLesson(
            book,
            lesson.change({'targets': targets.map((t) => t.toJson()).toList()}),
            expectedRevision: _base!.revision,
            check: () => _check(authorized),
          );
      ref.invalidate(englishCourseProvider(widget.bookId));
      if (mounted) context.pop();
    } on Object catch (e) {
      if (mounted) englishMessage(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _listen(Textbook book) async {
    try {
      final draft = _draft(book), voice = ref.read(englishVoiceProvider);
      if (await _audio.speak(draft.text, voice) &&
          mounted &&
          _draft(book).fingerprint == draft.fingerprint &&
          voice != null) {
        setState(() {
          _heardFingerprint = draft.fingerprint;
          _heardVoice = englishVoiceKey(voice);
        });
      }
    } on Object catch (e) {
      if (mounted) englishMessage(context, e);
    }
  }

  @override
  void dispose() {
    unawaited(_audio.stop());
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [
      _text,
      _meaning,
      _options,
      _answers,
      _page,
      _printed,
      _left,
      _top,
      _right,
      _bottom,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audio = ref.watch(englishAudioProvider(_audioKey));
    ref.watch(englishVoiceProvider);
    final currentBook = ref.watch(englishBookProvider(widget.bookId));
    final currentCourse = ref
        .watch(englishCourseProvider(widget.bookId))
        .valueOrNull;
    final currentLesson = currentCourse?.lesson(widget.lessonId);
    if (currentCourse?.target(widget.lessonId, widget.targetId)?.isAiPhrase ==
        true) {
      return AppScaffold(
        appBar: AppBar(title: const Text('拓展短语'), centerTitle: true),
        body: const AppEmptyState(
          icon: Icons.translate_outlined,
          title: '请从单词与短语中学习',
        ),
      );
    }
    return AppScaffold(
      appBar: AppBar(title: const Text('编辑英语内容')),
      bottomNavigationBar: currentBook == null || currentLesson == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(SpacingTokens.md),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : audio.busy
                            ? () => audio.stop()
                            : () => _listen(currentBook),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(
                            0,
                            SpacingTokens.minTapTarget,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: SpacingTokens.xs,
                          ),
                        ),
                        icon: Icon(
                          audio.busy ? Icons.stop : Icons.volume_up_outlined,
                        ),
                        label: AutoFitLine(
                          child: Text(
                            audio.busy ? '停止试听' : '试听当前声音',
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: SpacingTokens.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving
                            ? null
                            : () => _save(currentBook, currentLesson),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(
                            0,
                            SpacingTokens.minTapTarget,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: SpacingTokens.xs,
                          ),
                        ),
                        child: AutoFitLine(
                          child: Text(
                            _saving ? '正在保存…' : '保存并返回课时',
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: SafeArea(
        top: false,
        child: EnglishCourseBody(
          bookId: widget.bookId,
          builder: (book, course) {
            final lesson = (_base ?? course).lesson(widget.lessonId);
            if (lesson == null) {
              return const AppEmptyState(icon: Icons.edit_note, title: '课时已移除');
            }
            if (course.target(widget.lessonId, widget.targetId)?.isAiPhrase ==
                true) {
              return const AppEmptyState(
                icon: Icons.translate_outlined,
                title: '请从单词与短语中学习',
              );
            }
            _init(course, lesson);
            return ListView(
              padding: const EdgeInsets.all(SpacingTokens.md),
              children: [
                InkWell(
                  key: const ValueKey('english-content-type-selector'),
                  onTap: _pickKind,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '内容类型',
                      suffixIcon: Icon(Icons.arrow_drop_down),
                    ),
                    child: Text(_kind.label),
                  ),
                ),
                _field(_text, '英文 / 活动题干', lines: 3),
                _field(_meaning, '中文含义（可选）', lines: 2),
                if (_kind == EnglishTargetKind.vocabulary)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _spelling,
                    title: const Text('允许拼写练习'),
                    onChanged: (v) => setState(() => _spelling = v!),
                  ),
                if (_kind == EnglishTargetKind.exercise) ...[
                  DropdownButtonFormField<EnglishExerciseKind>(
                    initialValue: _exercise,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '核对方式'),
                    items: const [
                      DropdownMenuItem(
                        value: EnglishExerciseKind.choice,
                        child: Text('选择题'),
                      ),
                      DropdownMenuItem(
                        value: EnglishExerciseKind.fillBlank,
                        child: Text('填空题'),
                      ),
                      DropdownMenuItem(
                        value: EnglishExerciseKind.oral,
                        child: Text('开放题 · 家长核对'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _exercise = v!),
                  ),
                  if (_exercise == EnglishExerciseKind.choice)
                    _field(_options, '选项（每行一个）', lines: 4),
                  if (_exercise != EnglishExerciseKind.oral)
                    _field(_answers, '允许的答案（每行一种）', lines: 3),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _case,
                    title: const Text('答案区分大小写'),
                    onChanged: (v) => setState(() => _case = v!),
                  ),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _approved,
                  title: const Text('已对照原书核对内容与答案'),
                  subtitle: Text(
                    '保存后向孩子开放，未勾选则保存为草稿。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  onChanged: (v) => setState(() => _approved = v!),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    int lines = 1,
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
    child: TextField(
      controller: c,
      maxLines: lines,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: lines > 1,
      ),
    ),
  );
}
