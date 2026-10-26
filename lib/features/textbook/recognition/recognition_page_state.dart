import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/tts/narration_audio_cache.dart';
import 'package:poemath/core/services/tts/narration_session.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_recognition_progress.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/textbook_recognition_repository.dart';
import 'package:poemath/domain/textbook_recognition_content.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/recognition/recognition_providers.dart';

abstract class RecognitionPage extends ConsumerStatefulWidget {
  const RecognitionPage({
    super.key,
    required this.bookId,
    required this.lessonId,
    this.routeObserver,
  });
  final String bookId, lessonId;
  final RouteObserver<ModalRoute<dynamic>>? routeObserver;
}

/// 三个页面共用加载、写入失败重试及自己拥有的短音频生命周期。
abstract class RecognitionPageState<W extends RecognitionPage>
    extends ConsumerState<W> with WidgetsBindingObserver, RouteAware {
  Textbook? book;
  TextbookCoursePack? pack;
  TextbookCourseLesson? lesson;
  RecognitionProgress? progress;
  TextbookRecognitionRepository? repository;
  List<RecognitionTarget> targets = const [];
  late final TtsService tts;
  late final NarrationAudioCache cache;
  NarrationSession? audioSession;
  NarrationStatus? audioStatus;
  NarrationAudioIdentity? heardIdentity;
  bool heard = false, busy = false, loading = true;
  String? heardText, _audioText;
  String? error, audioError;
  ModalRoute<dynamic>? _route;
  StreamSubscription<dynamic>? _restore;
  StreamSubscription<String>? _profileChanges;
  bool _scopeInvalid = false;
  String _profile = '';
  int _loadId = 0;
  bool _disposed = false;
  Future<void> Function()? _retry;
  String get fingerprint => recognitionLessonFingerprint(targets);
  bool get current =>
      mounted &&
      !_disposed &&
      !_scopeInvalid &&
      _profile == ProfileScope.currentId;

  @override
  void initState() {
    super.initState();
    _profile = ProfileScope.currentId;
    _profileChanges = ProfileScope.changes.listen((_) {
      _scopeInvalid = true;
      unawaited(stopAudio());
      if (mounted) {
        setState(() {
          error = '档案已切换，请重新进入认一认';
          _retry = null;
        });
      }
    });
    tts = ref.read(ttsServiceProvider);
    cache = ref.read(textbookFileServiceProvider).narrationCache;
    WidgetsBinding.instance.addObserver(this);
    _restore = HiveBoxes.meta.watch(key: 'practice_draft_epoch').listen((_) {
      _scopeInvalid = true;
      unawaited(stopAudio());
      if (mounted) {
        setState(() {
          error = '学习数据已恢复，请重新进入认一认';
          _retry = null;
        });
      }
    });
    unawaited(reload());
  }

  Future<void> reload() async {
    final generation = ++_loadId;
    final courses = ref.read(textbookCourseRepositoryProvider);
    final books = ref.read(textbookListProvider);
    final box = ref.read(textbookRecognitionBoxProvider);
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final b = books.where((b) => b.pdfSha256 == widget.bookId).firstOrNull;
      if (b == null) throw StateError('找不到这本教材');
      final p = await courses.load(b);
      final l = p?.lessons.where((l) => l.id == widget.lessonId).firstOrNull;
      if (p == null || l == null) throw StateError('找不到这课的生字内容');
      final repo = TextbookRecognitionRepository(
        book: b,
        editionId: p.edition.id,
        courses: courses,
        box: box,
      );
      final saved = await repo.load();
      if (!current || generation != _loadId) return;
      setState(() {
        book = b;
        pack = p;
        lesson = l;
        targets = recognitionTargets(p, l);
        repository = repo;
        progress = saved;
        loading = false;
        _retry = null;
      });
      await onLoaded();
    } on Object catch (e) {
      if (current && generation == _loadId) {
        setState(() {
          loading = false;
          error = message(e);
          _retry = reload;
        });
      }
    }
  }

  Future<void> onLoaded() async {}
  String message(Object e) => e is FormatException
      ? e.message
      : e is StateError
          ? e.message.toString()
          : '保存或读取失败，请重试';
  Future<void> runWrite(
    Future<RecognitionProgress> Function() action, {
    VoidCallback? success,
  }) async {
    if (busy || !current) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await action();
      if (current) {
        setState(() {
          progress = value;
          _retry = null;
          success?.call();
        });
      }
    } on Object catch (e) {
      if (current) {
        setState(() {
          error = message(e);
          _retry = () => runWrite(action, success: success);
        });
      }
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  void playAudio(
    String text, {
    NarrationAudioIdentity? requiredIdentity,
    VoidCallback? rejected,
  }) {
    if (!current) return;
    final status = audioStatus;
    if (_audioText == text && status == NarrationStatus.paused) {
      unawaited(audioSession?.resume());
      return;
    }
    if (_audioText == text &&
        (status == NarrationStatus.playing ||
            status == NarrationStatus.preparing ||
            status == NarrationStatus.buffering)) {
      unawaited(audioSession?.pause());
      return;
    }
    var started = false;
    setState(() {
      heard = false;
      heardText = null;
      _audioText = text;
      heardIdentity = null;
      audioError = null;
    });
    try {
      final session = tts.startNarration(
        [text],
        bookId: widget.bookId,
        cache: cache,
        onAudioReady: (_, identity, id) {
          if (!current || audioSession?.sessionId != id) return;
          if (requiredIdentity != null &&
              requiredIdentity.signature != identity.signature) {
            unawaited(audioSession!.cancel());
            setState(() {
              audioError = '音色或音频已变化，这道听音题先跳过。请家长重新试听确认。';
            });
            rejected?.call();
          } else {
            heardIdentity = identity;
          }
        },
        onSegmentStart: (_, id) {
          if (current && audioSession?.sessionId == id) started = true;
        },
        onState: (state, id) {
          if (!current || audioSession?.sessionId != id) return;
          setState(() {
            audioStatus = state.status;
            if (state.status == NarrationStatus.completed &&
                started &&
                heardIdentity != null) {
              heard = true;
              heardText = text;
            }
            if (state.status == NarrationStatus.failed) {
              audioError = state.message ?? '语音播放失败，可以重试';
            }
          });
        },
      );
      audioSession = session;
      audioStatus = NarrationStatus.preparing;
    } on Object {
      setState(() => audioError = '语音暂时不可用，可以重试');
    }
  }

  Future<void> stopAudio() async {
    final old = audioSession;
    audioSession = null;
    if (mounted && !_disposed) {
      setState(() {
        audioStatus = null;
        heard = false;
        heardText = null;
        _audioText = null;
        heardIdentity = null;
      });
    }
    try {
      if (old != null && old.sessionId == tts.currentSessionId) {
        await tts.stop();
      } else {
        await old?.cancel();
      }
    } on Object {/* 退出不阻塞，旧身份已失效。 */}
  }

  Widget audioButton(
    String text, {
    NarrationAudioIdentity? requiredIdentity,
    String label = '听示范',
    bool iconOnly = false,
    bool enabled = true,
    IconData icon = Icons.volume_up_outlined,
  }) {
    final paused = _audioText == text && audioStatus == NarrationStatus.paused;
    final active = _audioText == text &&
        [
          NarrationStatus.playing,
          NarrationStatus.preparing,
          NarrationStatus.buffering,
        ].contains(audioStatus);
    final VoidCallback? onPressed = busy || !enabled
        ? null
        : () => playAudio(text, requiredIdentity: requiredIdentity);
    final buttonIcon = Icon(
      paused
          ? Icons.play_arrow
          : active
              ? Icons.pause
              : icon,
    );
    final buttonLabel = paused
        ? '继续播放'
        : active
            ? '暂停'
            : label;
    if (iconOnly) {
      return IconButton(
        onPressed: onPressed,
        tooltip: buttonLabel,
        constraints: const BoxConstraints(
          minWidth: SpacingTokens.minTapTarget,
          minHeight: SpacingTokens.minTapTarget,
        ),
        icon: buttonIcon,
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: buttonIcon,
      label: Text(buttonLabel),
    );
  }

  bool get showNavigationBar => true;

  Widget frame(String title, List<Widget> children, {bool compact = false}) =>
      Scaffold(
        appBar: showNavigationBar ? AppBar(title: Text(title)) : null,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: EdgeInsets.fromLTRB(
                          SpacingTokens.md,
                          showNavigationBar
                              ? SpacingTokens.md
                              : compact && error == null && audioError == null
                                  ? SpacingTokens.xl
                                  : kToolbarHeight + SpacingTokens.md,
                          SpacingTokens.md,
                          SpacingTokens.md,
                        ),
                        children: [
                          if (error != null)
                            ColoredCard(
                              color: Theme.of(context).colorScheme.error,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(error!),
                                  if (_retry != null)
                                    TextButton(
                                      onPressed: busy ? null : _retry,
                                      child: const Text('重试'),
                                    ),
                                ],
                              ),
                            ),
                          if (audioError != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: SpacingTokens.md,
                              ),
                              child: Text(audioError!),
                            ),
                          if (lesson != null) ...children,
                          if (busy)
                            const Padding(
                              padding: EdgeInsets.all(SpacingTokens.md),
                              child: LinearProgressIndicator(),
                            ),
                        ],
                      ),
              ),
              if (!showNavigationBar)
                const PositionedDirectional(
                  top: 0,
                  start: 0,
                  child: SizedBox(
                    width: kToolbarHeight,
                    height: kToolbarHeight,
                    child: BackButton(),
                  ),
                ),
            ],
          ),
        ),
      );
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
  void didUpdateWidget(covariant W oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId != widget.bookId ||
        oldWidget.lessonId != widget.lessonId) {
      unawaited(stopAudio());
      unawaited(reload());
    }
  }

  @override
  void didPushNext() => unawaited(stopAudio());
  @override
  void didPop() => unawaited(stopAudio());
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        state != AppLifecycleState.inactive) {
      unawaited(stopAudio());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _loadId++;
    widget.routeObserver?.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_restore?.cancel());
    unawaited(_profileChanges?.cancel());
    unawaited(stopAudio());
    super.dispose();
  }
}
