import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/textbook_course_generation_service.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_catalog.dart';

class TextbookGenerationController
    extends StateNotifier<Map<String, TextbookGenerationProgress>> {
  TextbookGenerationController(this.service, this.changed) : super({});
  final TextbookCourseGenerationService service;
  final void Function(String) changed;
  String? _activeId;
  Future<void>? _active;
  TextbookDraftToken? _token;
  bool _disposed = false;
  void pause(String id) {
    if (_activeId == id) _token?.cancel();
  }

  Future<void> stop(String id) async {
    if (_activeId != id) return;
    _token?.cancel();
    await _active;
  }

  Future<void> start(
    Textbook book,
    TextbookCatalogEntry entry,
    String path, {
    bool refresh = false,
    String? lessonId,
  }) {
    if (_disposed) return Future.value();
    if (_activeId == book.pdfSha256 && _active != null) return _active!;
    final previous = _active;
    _token?.cancel();
    _activeId = book.pdfSha256;
    final token = TextbookDraftToken();
    _token = token;
    // Reserve synchronously so rapid taps share one task, including PDF opening.
    late final Future<void> future;
    future = Future<void>.microtask(() async {
      try {
        await previous;
        if (_disposed || token.cancelled) return;
        await service.run(
          book,
          entry,
          path,
          token,
          (progress) {
            if (!_disposed) state = {...state, book.pdfSha256: progress};
          },
          () {
            if (!_disposed) changed(book.pdfSha256);
          },
          refresh: refresh,
          lessonId: lessonId,
        );
      } on Object catch (error, stackTrace) {
        AppLogger.e(
          '原书课程整理失败',
          tag: 'TextbookCourse',
          error: error,
          stackTrace: stackTrace,
        );
        if (!_disposed) {
          state = {
            ...state,
            book.pdfSha256: TextbookGenerationProgress(
              'failed',
              state[book.pdfSha256]?.done ?? 0,
              state[book.pdfSha256]?.total ?? 0,
              error is FormatException
                  ? error.message.toString()
                  : '整理失败，已保存的内容保留，请重试',
            ),
          };
        }
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

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    super.dispose();
  }
}
