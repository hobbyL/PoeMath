import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/domain/textbook_lesson_content.dart';
import 'package:poemath/domain/textbook_narration.dart';
import 'package:poemath/core/services/tts/narration_session.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/textbook_course_content.dart';

/// 当前原书页对应的只读内容；待审核内容可查看，不改审核或学习记录。
class TextbookLessonContentPage extends ConsumerStatefulWidget {
  const TextbookLessonContentPage({
    super.key,
    required this.bookId,
    required this.section,
    required this.pages,
    this.routeObserver,
  });

  final String bookId;
  final TextbookContentSection? section;
  final List<int> pages;
  final RouteObserver<ModalRoute<dynamic>>? routeObserver;

  @override
  ConsumerState<TextbookLessonContentPage> createState() =>
      _TextbookLessonContentPageState();
}

class _TextbookLessonContentPageState
    extends ConsumerState<TextbookLessonContentPage>
    with WidgetsBindingObserver, RouteAware {
  String get bookId => widget.bookId;
  TextbookContentSection? get section => widget.section;
  List<int> get pages => widget.pages;
  late final TtsService _tts;
  NarrationSession? _session;
  NarrationState? _state;
  int _activeSessionId = -1;
  TextbookNarrationSegment? _segment;
  List<TextbookCourseLesson> _lessons = [];
  final _scroll = ScrollController();
  final _lessonKeys = <String, GlobalKey>{};
  final _wordKey = GlobalKey();
  ModalRoute<dynamic>? _route;
  bool _leaving = false;
  bool _changingControl = false;

  @override
  void initState() {
    super.initState();
    _tts = ref.read(ttsServiceProvider);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      widget.routeObserver?.unsubscribe(this);
      _route = route;
      if (route != null) widget.routeObserver?.subscribe(this, route);
    }
  }

  @override
  void didUpdateWidget(covariant TextbookLessonContentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId != bookId ||
        oldWidget.section != section ||
        !listEquals(oldWidget.pages, pages)) {
      unawaited(_stop());
      _lessonKeys.clear();
    }
  }

  @override
  void didPushNext() {
    unawaited(_stop());
  }

  @override
  void didPop() {
    unawaited(_stop());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_stop());
    }
  }

  @override
  void dispose() {
    _leaving = true;
    widget.routeObserver?.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stop());
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _stop() async {
    final session = _session;
    final ownsService =
        session != null && _activeSessionId == _tts.currentSessionId;
    _session = null;
    _activeSessionId = -1;
    if (mounted && !_leaving) {
      setState(() {
        _state = null;
        _segment = null;
      });
    }
    try {
      if (ownsService) {
        await _tts.stop();
      } else {
        await session?.cancel();
      }
    } on Object {/* 导航退出仍完成，播放器 dispose 与会话身份负责兜底。 */}
  }

  void _start(List<TextbookCourseLesson> lessons) {
    final plan = buildTextbookNarration(lessons);
    if (plan.isEmpty) return;
    try {
      final cache = ref.read(textbookFileServiceProvider).narrationCache;
      final session = _tts.startNarration(
        plan.map((segment) => segment.text).toList(),
        bookId: bookId,
        cache: cache,
        onState: (state, id) {
          if (!mounted || _leaving || id != _activeSessionId) return;
          setState(() {
            _state = state;
            if (state.status == NarrationStatus.completed ||
                state.status == NarrationStatus.stopped) {
              _segment = null;
              _session = null;
              _activeSessionId = -1;
            }
          });
        },
        onSegmentStart: (index, id) {
          if (!mounted || _leaving || id != _activeSessionId) return;
          setState(() => _segment = plan[index]);
          unawaited(_reveal(plan[index], id));
        },
      );
      _session = session;
      _activeSessionId = session.sessionId;
      setState(() {
        _segment = null;
        _state = const NarrationState(NarrationStatus.preparing, 0);
      });
    } on Object {
      if (!mounted || _leaving) return;
      setState(() => _state = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('朗读暂时不可用，请稍后重试。')));
    }
  }

  Future<void> _control() async {
    if (_changingControl) return;
    _changingControl = true;
    try {
      final session = _session;
      if (session == null) {
        _start(_lessons);
      } else if (_state?.status == NarrationStatus.failed) {
        session.retry();
      } else if (_state?.status == NarrationStatus.paused) {
        await session.resume();
      } else {
        await session.pause();
      }
    } on Object {
      if (mounted && !_leaving) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('语音操作失败，可停止后重试。')));
      }
    } finally {
      _changingControl = false;
    }
  }

  Future<void> _reveal(TextbookNarrationSegment segment, int sessionId) async {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    bool current() =>
        mounted &&
        !_leaving &&
        sessionId == _activeSessionId &&
        identical(segment, _segment);
    await WidgetsBinding.instance.endOfFrame;
    for (var step = 0; step < 200 && current(); step++) {
      final word = _wordKey.currentContext;
      if (word != null) {
        if (!word.mounted) return;
        await Scrollable.ensureVisible(
          word,
          alignment: 0.25,
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
        );
        return;
      }
      if (!_scroll.hasClients) return;
      final target =
          _lessons.indexWhere((lesson) => lesson.id == segment.lessonId);
      final mountedIndices = [
        for (final (index, lesson) in _lessons.indexed)
          if (_lessonKeys[lesson.id]?.currentContext != null) index,
      ];
      final direction =
          mountedIndices.isNotEmpty && target < mountedIndices.first ? -1 : 1;
      final position = _scroll.position;
      final next = (position.pixels + direction * position.viewportDimension)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (next == position.pixels) return;
      _scroll.jumpTo(next);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  String _rangeText(
    TextbookCourseLesson lesson,
    TextbookRecitationRange range,
  ) {
    final paragraph = lesson.paragraphs
        .firstWhere((paragraph) => paragraph.id == range.paragraphId);
    return String.fromCharCodes(
      paragraph.text.runes.toList().sublist(range.start, range.end),
    );
  }

  String _emptyLabel(
    TextbookCourseLesson lesson,
    TextbookContentSection section,
  ) {
    if (lesson.coverage[section.category] == TextbookCoverage.notApplicable) {
      return switch (section) {
        TextbookContentSection.reading => '原书未要求本课阅读课文。',
        TextbookContentSection.recognition => '原书未要求本课会认字。',
        TextbookContentSection.recitation => '原书未要求本课背诵。',
        TextbookContentSection.writing => '原书未要求本课会写字。',
      };
    }
    return '本课尚未整理${textbookCourseCategoryLabels[section.category]}。';
  }

  Widget _recitations(BuildContext context, TextbookCourseLesson lesson) {
    final style = Theme.of(context).textTheme.titleSmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, recitation) in lesson.recitations.indexed) ...[
          if (index > 0) const SizedBox(height: SpacingTokens.lg),
          Text(recitation.instruction, style: style),
          for (final range in recitation.ranges) ...[
            const SizedBox(height: SpacingTokens.md),
            SelectableText(
              '　　${_rangeText(lesson, range).trimLeft()}',
              style: style,
            ),
          ],
        ],
      ],
    );
  }

  Widget _lesson(
    BuildContext context,
    TextbookCourseLesson lesson,
    TextbookContentSection section, {
    required bool showTitle,
  }) {
    final theme = Theme.of(context);
    final targets = section.targets(lesson);
    return KeyedSubtree(
      key: _lessonKeys.putIfAbsent(lesson.id, GlobalKey.new),
      child: ColoredCard(
        key: ValueKey('textbook-content-${lesson.id}'),
        color: theme.colorScheme.primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showTitle) ...[
              Text(
                lesson.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: SpacingTokens.md),
            ],
            if (targets.isEmpty)
              Text(
                _emptyLabel(lesson, section),
                style: theme.textTheme.titleSmall,
              )
            else
              switch (section) {
                TextbookContentSection.reading =>
                  TextbookCourseParagraphsContent(
                    paragraphs: lesson.paragraphs,
                    activeRanges: _segment?.lessonId == lesson.id
                        ? _segment!.spans
                        : const [],
                    activeStartKey:
                        _segment?.lessonId == lesson.id ? _wordKey : null,
                  ),
                TextbookContentSection.recognition =>
                  TextbookCourseVocabularyContent(
                    vocabulary: lesson.recognitionCharacters,
                  ),
                TextbookContentSection.recitation =>
                  _recitations(context, lesson),
                TextbookContentSection.writing =>
                  TextbookCourseVocabularyContent(
                    vocabulary: lesson.writingCharacters,
                  ),
              },
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = section;
    final course = ref.watch(textbookCourseProvider(bookId));
    final pack = course.valueOrNull;
    final lessons = pack == null
        ? const <TextbookCourseLesson>[]
        : textbookLessonsForPages(pack, pages);
    _lessons = lessons;
    final title = selected == null
        ? '课文内容'
        : lessons.length == 1
            ? '${selected.label}·${lessons.single.title}'
            : selected.label;
    return Scaffold(
      bottomNavigationBar: _session == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(SpacingTokens.md),
                child: Row(
                  children: [
                    if (_state?.status == NarrationStatus.preparing ||
                        _state?.status == NarrationStatus.buffering) ...[
                      const SizedBox(
                        width: SpacingTokens.md,
                        height: SpacingTokens.md,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: SpacingTokens.sm),
                    ],
                    Expanded(
                      child: Text(
                        switch (_state?.status) {
                          NarrationStatus.preparing => '正在准备朗读…',
                          NarrationStatus.buffering => '正在准备下一段…',
                          NarrationStatus.paused => '已暂停',
                          NarrationStatus.failed =>
                            _state?.message ?? '朗读遇到问题，请重试',
                          _ => '正在朗读',
                        },
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (selected == TextbookContentSection.reading &&
              lessons.any((lesson) => lesson.paragraphs.isNotEmpty)) ...[
            IconButton(
              tooltip: _session == null
                  ? '朗读课文'
                  : _state?.status == NarrationStatus.paused
                      ? '继续朗读'
                      : _state?.status == NarrationStatus.failed
                          ? '重试朗读'
                          : '暂停朗读',
              onPressed: _control,
              icon: Icon(
                _session == null
                    ? Icons.volume_up_outlined
                    : _state?.status == NarrationStatus.paused
                        ? Icons.play_arrow_rounded
                        : _state?.status == NarrationStatus.failed
                            ? Icons.refresh_rounded
                            : Icons.pause_rounded,
              ),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: selected == null
            ? const Center(child: Text('找不到这类课文内容。'))
            : course.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('课文内容加载失败，请重试。'),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(textbookCourseProvider(bookId)),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
                data: (pack) {
                  if (lessons.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(SpacingTokens.md),
                        child: Text('当前页暂无对应课目，请翻到课文页后再查看。'),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.all(SpacingTokens.md),
                    itemCount: lessons.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: SpacingTokens.md),
                    itemBuilder: (context, index) => _lesson(
                      context,
                      lessons[index],
                      selected,
                      showTitle: lessons.length > 1,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
