import 'dart:async';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/math_textbook_generation_service.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/math_textbook_course_repository.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_textbook_progress.dart';
import 'package:poemath/data/repositories/math_textbook_learning_repository.dart';
import 'package:poemath/domain/math_textbook_progress.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

final mathTextbookRepositoryProvider = Provider<MathTextbookCourseRepository>(
  (ref) => MathTextbookCourseRepository(),
);

final mathTextbookProfileProvider = StreamProvider<String>((ref) async* {
  yield ProfileScope.currentId;
  yield* ProfileScope.changes;
});

final mathTextbookLearningRepositoryProvider = Provider.autoDispose
    .family<MathTextbookLearningRepository?, String>((ref, id) {
      ref.watch(mathTextbookProfileProvider);
      final book = ref
          .watch(textbookLocalListProvider)
          .where((b) => b.pdfSha256 == id && b.subject == TextbookSubject.math)
          .firstOrNull;
      if (book == null) return null;
      return MathTextbookLearningRepository(
        book: book,
        courses: ref.watch(mathTextbookRepositoryProvider),
        findBook: ref.watch(textbookRepositoryProvider).find,
      );
    });

final _mathTextbookProgressChangesProvider = StreamProvider.autoDispose
    .family<void, String>(
      (ref, key) => HiveBoxes.settings.watch(key: key).map((_) {}),
    );

final mathTextbookProgressProvider = FutureProvider.autoDispose
    .family<MathTextbookProgress?, String>((ref, id) async {
      final repository = ref.watch(mathTextbookLearningRepositoryProvider(id));
      if (repository == null) return null;
      ref.watch(_mathTextbookProgressChangesProvider(repository.key));
      await ref.watch(mathTextbookCourseProvider(id).future);
      return repository.load();
    });

final mathTextbookCourseProvider = FutureProvider.autoDispose
    .family<MathTextbookCourse?, String>((ref, id) async {
      final book = ref
          .watch(textbookLocalListProvider)
          .where((b) => b.pdfSha256 == id && b.subject == TextbookSubject.math)
          .firstOrNull;
      if (book == null) return null;
      return ref.watch(mathTextbookRepositoryProvider).load(book);
    });

typedef MathTextbookBookLearning = ({
  MathTextbookCourse? course,
  Map<String, MathTextbookLessonProgress> lessons,
});

// Only immutable course/progress snapshots enter the worker, never providers
// or repositories. A lesson summary is calculated once for the entire list.
Future<Map<String, MathTextbookLessonProgress>> _summarizeCourse(
  List<MathTextbookLesson> lessons,
  String bookId,
  MathTextbookProgress progress,
) => Isolate.run(
  () => {
    for (final lesson in lessons)
      lesson.id: mathTextbookLessonProgress(lesson, bookId, progress),
  },
  debugName: 'math-textbook-book-progress',
);

final mathTextbookBookLearningProvider = FutureProvider.autoDispose
    .family<MathTextbookBookLearning, String>((ref, id) async {
      final courseFuture = ref.watch(mathTextbookCourseProvider(id).future);
      final progressFuture = ref.watch(mathTextbookProgressProvider(id).future);
      final course = await courseFuture;
      final progress = await progressFuture;
      if (course == null || progress == null) {
        return (
          course: null,
          lessons: const <String, MathTextbookLessonProgress>{},
        );
      }
      return (
        course: course,
        lessons: await _summarizeCourse(
          course.lessons,
          id,
          MathTextbookProgress(
            profileId: progress.profileId,
            bookId: progress.bookId,
            editionId: progress.editionId,
            readLessons: progress.readLessons,
            targets: progress.targets,
          ),
        ),
      );
    });

final mathTextbookGenerationServiceProvider =
    Provider<MathTextbookGenerationService>(
      (ref) => MathTextbookGenerationService(
        ref.watch(mathTextbookRepositoryProvider),
        ref.watch(textbookFileServiceProvider),
      ),
    );

final mathTextbookGenerationProvider =
    StateNotifierProvider<
      MathTextbookGenerationController,
      Map<String, MathTextbookGenerationState>
    >(
      (ref) => MathTextbookGenerationController(
        ref.watch(mathTextbookGenerationServiceProvider),
        (id) => ref.invalidate(mathTextbookCourseProvider(id)),
      ),
    );

class MathTextbookGenerationState {
  const MathTextbookGenerationState({
    required this.running,
    required this.message,
    this.completed = 0,
    this.total = 0,
    this.wholeBook = false,
    this.failed = false,
  });
  final bool running;
  final String message;
  final int completed;
  final int total;
  final bool wholeBook;
  final bool failed;
}

/// 一次只运行一份数学原书整理；离页或锁定后旧任务不能继续写入。
class MathTextbookGenerationController
    extends StateNotifier<Map<String, MathTextbookGenerationState>> {
  MathTextbookGenerationController(this.service, this.changed) : super({});
  final MathTextbookGenerationService service;
  final void Function(String id) changed;
  TextbookDraftToken? _token;
  String? _activeId;
  Future<void>? _active;
  bool _disposed = false;

  void cancel(String id) {
    if (_activeId == id) _token?.cancel();
  }

  void pause(String id) => cancel(id);

  Future<void> stop(String id) async {
    if (_activeId != id) return;
    _token?.cancel();
    await _active;
  }

  Future<void> start({
    required Textbook book,
    required String title,
    required int startPage,
    required int endPage,
    required void Function() authorize,
    bool wholeBook = false,
    bool refresh = false,
  }) {
    if (_disposed) return Future.value();
    if (_activeId == book.pdfSha256 && _active != null) return _active!;
    final previous = _active;
    _token?.cancel();
    final token = TextbookDraftToken();
    _token = token;
    _activeId = book.pdfSha256;
    state = {
      ...state,
      book.pdfSha256: MathTextbookGenerationState(
        running: true,
        message: '正在打开原书…',
        wholeBook: wholeBook,
      ),
    };
    late final Future<void> future;
    future = Future<void>.microtask(() async {
      try {
        await previous;
        token.check();
        if (wholeBook) {
          await service.generateBook(
            book: book,
            token: token,
            authorize: authorize,
            refresh: refresh,
            onSaved: () {
              if (!_disposed) changed(book.pdfSha256);
            },
            onStatus: (message) {
              if (!_disposed) {
                final previous = state[book.pdfSha256];
                state = {
                  ...state,
                  book.pdfSha256: MathTextbookGenerationState(
                    running: true,
                    message: message,
                    completed: previous?.completed ?? 0,
                    total: previous?.total ?? 0,
                    wholeBook: true,
                  ),
                };
              }
            },
            onProgress: (_, __) {},
            onLessonProgress: (completed, total) {
              if (!_disposed) {
                state = {
                  ...state,
                  book.pdfSha256: MathTextbookGenerationState(
                    running: true,
                    message: '已保存 $completed/$total 课，继续整理…',
                    completed: completed,
                    total: total,
                    wholeBook: true,
                  ),
                };
              }
            },
          );
        } else {
          await service.generate(
            book: book,
            title: title,
            startPage: startPage,
            endPage: endPage,
            token: token,
            authorize: authorize,
            onProgress: (completed, total) {
              if (_disposed) return;
              state = {
                ...state,
                book.pdfSha256: MathTextbookGenerationState(
                  running: true,
                  message: '已读取 $completed / $total 页，正在整理…',
                  completed: completed,
                  total: total,
                ),
              };
            },
          );
        }
        if (!_disposed) {
          changed(book.pdfSha256);
          _finish(
            book.pdfSha256,
            wholeBook ? '全书草稿已逐课保存，请对照原书补齐内容并审核' : '整课草稿已保存，请对照原书审核',
          );
        }
      } on TextbookDraftCancelled {
        _finish(book.pdfSha256, '已暂停整理，已保存的课时保留，可继续整理');
      } on ParentAccessDenied {
        _finish(book.pdfSha256, '家长授权已结束，请重新打开后整理', failed: true);
      } on Object catch (error, stackTrace) {
        AppLogger.e(
          '数学整课整理失败',
          tag: 'MathTextbook',
          error: error,
          stackTrace: stackTrace,
        );
        _finish(
          book.pdfSha256,
          error is FormatException
              ? error.message.toString()
              : '整理失败，已有草稿保留，请重试',
          failed: true,
        );
      } finally {
        if (identical(_active, future)) {
          _active = null;
          _activeId = null;
          _token = null;
        }
      }
    });
    _active = future;
    return future;
  }

  Future<void> startBook({
    required Textbook book,
    required void Function() authorize,
    bool refresh = false,
  }) => start(
    book: book,
    title: '全书整理',
    startPage: 1,
    endPage: book.pageCount,
    authorize: authorize,
    wholeBook: true,
    refresh: refresh,
  );

  void _finish(String id, String message, {bool failed = false}) {
    if (_disposed) return;
    state = {
      ...state,
      id: MathTextbookGenerationState(
        running: false,
        message: message,
        completed: state[id]?.completed ?? 0,
        total: state[id]?.total ?? 0,
        wholeBook: state[id]?.wholeBook ?? false,
        failed: failed,
      ),
    };
  }

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    super.dispose();
  }
}
