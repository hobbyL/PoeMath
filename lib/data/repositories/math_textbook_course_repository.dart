import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart'
    show textbookContentDigest;
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/domain/math_textbook_content_organizer.dart';

MathTextbookCourse _decodeCourse(Uint8List bytes) {
  final course = MathTextbookCourse.fromJson(jsonDecode(utf8.decode(bytes)));
  final retained = course.outline?.retainedLessonIds.toSet() ?? <String>{};
  final lessons = [
    for (final lesson in course.lessons)
      retained.contains(lesson.id)
          ? lesson
          : resolveMathTextbookLearningSections(lesson),
  ];
  final pendingLessons = [
    for (final lesson in course.pendingLessons)
      retained.contains(lesson.id)
          ? lesson
          : resolveMathTextbookLearningSections(lesson),
  ];
  if (lessons.indexed.every(
        (entry) => identical(entry.$2, course.lessons[entry.$1]),
      ) &&
      pendingLessons.indexed.every(
        (entry) => identical(entry.$2, course.pendingLessons[entry.$1]),
      )) {
    return course;
  }
  // Read-time compatibility never rewrites the authored file/edit revision.
  // withCurrentCourse uses this same decoder when starting/submitting practice.
  return MathTextbookCourse(
    pdfSha256: course.pdfSha256,
    pageCount: course.pageCount,
    fileSize: course.fileSize,
    grade: course.grade,
    semester: course.semester,
    revision: course.revision,
    lessons: lessons,
    pendingLessons: pendingLessons,
    outline: course.outline,
  );
}

// Keep this closure outside the repository so it cannot capture the IO queue.
Future<MathTextbookCourse> _decodeLargeCourse(Uint8List bytes) => Isolate.run(
  () => _decodeCourse(bytes),
  debugName: 'math-textbook-course-decode',
);

Future<MathTextbookCourse> _decodePreparedCourse(Object? data) => Isolate.run(
  () => MathTextbookCourse.fromJson(data),
  debugName: 'math-textbook-prepared-course',
);

/// 数学人工草稿独立于语文课程和派生缓存；重新整理产生待采纳版本。
class MathTextbookCourseRepository {
  MathTextbookCourseRepository({
    Future<Directory> Function()? directoryProvider,
    TextbookFileService? files,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _files =
           files ?? TextbookFileService(directoryProvider: directoryProvider);
  final Future<Directory> Function() _directoryProvider;
  final TextbookFileService _files;
  TextbookContentCache contentCache(Textbook book) => _files.contentCache(book);
  static const maxBytes = TextbookCourseRepository.maxBytes;
  Future<void> _tail = Future.value();
  final _epochs = <String, int>{};
  // Keep only the most recently read book. Every hit still checks the source
  // bytes and the shared clear epoch, including reads made before grading.
  ({
    TextbookContentCache cache,
    int revision,
    String key,
    MathTextbookCourse course,
  })?
  _prepared;

  int generation(String id) => _epochs[id] ?? 0;
  void invalidate(String id) {
    _epochs.update(id, (value) => value + 1, ifAbsent: () => 1);
  }

  void checkGeneration(String id, int generation) {
    if (this.generation(id) != generation) {
      throw const FormatException('本书整理已失效，请重新打开');
    }
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<File> _file(Textbook book) async {
    if (!Textbook.isValidId(book.pdfSha256)) {
      throw const FormatException('教材身份无效');
    }
    return File(
      '${(await _directoryProvider()).path}/textbooks/math-courses/${book.pdfSha256}.json',
    );
  }

  Future<MathTextbookCourse?> _load(Textbook book) async {
    final cache = contentCache(book);
    final cacheRevision = cache.revision;
    final file = await _file(book);
    if (!await file.exists()) return null;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const FormatException('数学课程草稿超过 16 MB');
      }
      bytes.add(chunk);
    }
    final data = bytes.takeBytes();
    if (cache.revision != cacheRevision) throw StateError('原书缓存已失效');
    final key = textbookContentDigest({
      'kind': 'math-course',
      // Decoded course compatibility projections change independently from
      // the authored file digest. Bump this when read-time repair rules change.
      'version': 2,
      'source': sha256.convert(data).toString(),
    });
    final previous = _prepared;
    if (previous != null &&
        identical(previous.cache, cache) &&
        previous.revision == cacheRevision &&
        previous.key == key) {
      previous.course.matchBook(book);
      return previous.course;
    }
    // Validating thousands of blocks must not block the reading transition.
    final course = await cache.mathData<MathTextbookCourse>(
      key,
      decode: _decodePreparedCourse,
      encode: (course) => course.toJson(),
      load: () async => data.length >= 64 * 1024
          ? await _decodeLargeCourse(data)
          : _decodeCourse(data),
    );
    course.matchBook(book);
    _prepared = (
      cache: cache,
      revision: cacheRevision,
      key: key,
      course: course,
    );
    return course;
  }

  Future<MathTextbookCourse?> load(Textbook book) => _serial(() => _load(book));

  /// 审核状态检查与学习写入共用课程锁，避免校验后被改稿或移除。
  Future<T> withCurrentCourse<T>(
    Textbook book,
    Future<T> Function(MathTextbookCourse? course) action,
  ) => _serial(() async => action(await _load(book)));

  Future<void> drain() => _serial(() async {});

  Future<MathTextbookCourse> saveOutline(
    Textbook book,
    MathTextbookCourseOutline outline, {
    required int generation,
    required void Function() authorize,
  }) => _serial(() async {
    void check() {
      authorize();
      checkGeneration(book.pdfSha256, generation);
    }

    check();
    final current = await _load(book) ?? MathTextbookCourse.forBook(book);
    final currentIds = outline.ranges.map((range) => range.lessonId).toSet();
    final savedIds = current.lessons.map((lesson) => lesson.id).toSet();
    final retained = {
      ...?current.outline?.retainedLessonIds,
      ...outline.retainedLessonIds,
      ...?current.outline?.ranges
          .map((range) => range.lessonId)
          .where(savedIds.contains),
    }..removeWhere(currentIds.contains);
    final next = current.replace(
      outline: MathTextbookCourseOutline.fromJson({
        ...outline.toJson(),
        'retainedLessonIds': retained.toList(),
      }),
    );
    await _write(book, next, check);
    return next;
  });

  Future<MathTextbookCourse> removeLesson(
    Textbook book,
    String lessonId, {
    required int expectedRevision,
    required void Function() authorize,
  }) => _serial(() async {
    authorize();
    final current = await _load(book);
    if (current == null || current.revision != expectedRevision) {
      throw StateError('课时已更新，请重新打开后移除');
    }
    invalidate(book.pdfSha256);
    final epoch = generation(book.pdfSha256);
    final next = current.replace(
      lessons: current.lessons.where((l) => l.id != lessonId).toList(),
      pendingLessons: current.pendingLessons
          .where((l) => l.id != lessonId)
          .toList(),
      outline: current.outline == null
          ? null
          : MathTextbookCourseOutline.fromJson({
              ...current.outline!.toJson(),
              if (current.outline!.completedLessonIds != null)
                'completedLessonIds': current.outline!.completedLessonIds!
                    .where((id) => id != lessonId)
                    .toList(),
              'retainedLessonIds': current.outline!.retainedLessonIds
                  .where((id) => id != lessonId)
                  .toList(),
            }),
    );
    await _write(book, next, () {
      authorize();
      checkGeneration(book.pdfSha256, epoch);
    });
    return next;
  });

  /// Record completion only after a whole lesson (or its comparison draft) saved.
  Future<MathTextbookCourse> completeRange(
    Textbook book,
    String lessonId, {
    required int generation,
    required void Function() authorize,
  }) => _serial(() async {
    void check() {
      authorize();
      checkGeneration(book.pdfSha256, generation);
    }

    check();
    final current = await _load(book);
    final outline = current?.outline;
    if (current == null ||
        outline == null ||
        !outline.ranges.any((range) => range.lessonId == lessonId) ||
        !current.lessons.any(
          (lesson) =>
              lesson.id == lessonId &&
              outline.ranges.any(
                (range) =>
                    range.lessonId == lessonId &&
                    lesson.startPage == range.startPage &&
                    lesson.endPage == range.endPage,
              ),
        )) {
      throw const FormatException('课时尚未完整保存，不能标为已整理');
    }
    final completed = {...?outline.completedLessonIds, lessonId};
    if (completed.length == outline.completedLessonIds?.length) return current;
    final next = current.replace(
      outline: outline.withCompleted(
        outline.ranges.map((range) => range.lessonId).where(completed.contains),
      ),
    );
    await _write(book, next, check);
    return next;
  });

  Future<void> _write(
    Textbook book,
    MathTextbookCourse course,
    void Function() check,
  ) async {
    final validated = MathTextbookCourse.fromJson(course.toJson());
    validated.matchBook(book);
    final bytes = utf8.encode(jsonEncode(validated.toJson()));
    if (bytes.length > maxBytes) throw const FormatException('数学课程草稿超过 16 MB');
    check();
    final file = await _file(book);
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      check();
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } on Object catch (error, stackTrace) {
          AppLogger.e(
            '数学草稿临时文件清理失败',
            tag: 'MathTextbook',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }
  }

  Future<MathTextbookCourse> saveGenerated(
    Textbook book,
    MathTextbookLesson lesson, {
    required int generation,
    required void Function() authorize,
    String? unmodifiedLegacyDigest,
    String? unmodifiedPreviousDigest,
  }) => _serial(() async {
    void check() {
      authorize();
      checkGeneration(book.pdfSha256, generation);
    }

    check();
    final current = await _load(book) ?? MathTextbookCourse.forBook(book);
    check();
    final previous = current.lessons
        .where((l) => l.id == lesson.id)
        .firstOrNull;
    final previousDigest = previous?.contentDigest(book.pdfSha256);
    final MathTextbookCourse next;
    if (previous == null) {
      next = current.replace(lessons: [...current.lessons, lesson]);
    } else if (previousDigest == lesson.contentDigest(book.pdfSha256)) {
      return current;
    } else if (previous.review == null &&
        (previousDigest == unmodifiedLegacyDigest ||
            previousDigest == unmodifiedPreviousDigest)) {
      // Only a byte-for-content reproduction of the old automatic draft can
      // take this path. Parent edits anywhere, not just the summary, prevent it.
      next = current.replace(
        lessons: [
          for (final item in current.lessons)
            item.id == lesson.id ? lesson : item,
        ],
        pendingLessons: current.pendingLessons
            .where((item) => item.id != lesson.id)
            .toList(),
      );
    } else {
      next = current.replace(
        pendingLessons: [
          ...current.pendingLessons.where((l) => l.id != lesson.id),
          lesson.edit(),
        ],
      );
    }
    await _write(book, next, check);
    return next;
  });

  Future<MathTextbookCourse> saveLesson(
    Textbook book,
    MathTextbookLesson lesson, {
    required int expectedRevision,
    required int generation,
    required void Function() authorize,
  }) => _serial(() async {
    void check() {
      authorize();
      checkGeneration(book.pdfSha256, generation);
    }

    check();
    final current = await _load(book);
    if (current == null ||
        current.revision != expectedRevision ||
        !current.lessons.any((l) => l.id == lesson.id)) {
      throw const FormatException('课时已更新或移除，请重新打开后再保存');
    }
    final next = current.replace(
      lessons: [
        for (final value in current.lessons)
          value.id == lesson.id ? lesson : value,
      ],
    );
    await _write(book, next, check);
    return next;
  });

  Future<MathTextbookCourse> acceptPending(
    Textbook book,
    String lessonId, {
    required int expectedRevision,
    required int generation,
    required void Function() authorize,
  }) => _serial(() async {
    void check() {
      authorize();
      checkGeneration(book.pdfSha256, generation);
    }

    check();
    final current = await _load(book);
    if (current == null || current.revision != expectedRevision) {
      throw const FormatException('课时已更新，请重新打开后再采纳');
    }
    final replacement = current.pendingLessons
        .where((l) => l.id == lessonId)
        .firstOrNull;
    if (replacement == null) throw const FormatException('没有待采纳的整理结果');
    final next = current.replace(
      lessons: [
        for (final lesson in current.lessons)
          lesson.id == lessonId ? replacement.edit() : lesson,
      ],
      pendingLessons: current.pendingLessons
          .where((l) => l.id != lessonId)
          .toList(),
    );
    await _write(book, next, check);
    return next;
  });

  Future<void> clear(Textbook book) {
    invalidate(book.pdfSha256);
    return _serial(() async {
      final file = await _file(book);
      if (await file.exists()) await file.delete();
    });
  }
}
