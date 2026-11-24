import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/data/models/textbook.dart';

/// 人工内容不进入派生缓存；所有改稿和学习校验共用串行锁。
class EnglishCourseRepository {
  EnglishCourseRepository({Future<Directory> Function()? directoryProvider})
    : _directory = directoryProvider ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directory;
  Future<void> _tail = Future.value();
  static const maxBytes = 16 * 1024 * 1024;

  Future<T> _serial<T>(Future<T> Function() action) {
    final work = _tail.then((_) => action());
    _tail = work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return work;
  }

  Future<File> _file(Textbook book) async {
    if (!Textbook.isValidId(book.pdfSha256) ||
        book.subject != TextbookSubject.english) {
      throw const FormatException('英语教材身份无效');
    }
    return File(
      '${(await _directory()).path}/textbooks/english-courses/${book.pdfSha256}.json',
    );
  }

  Future<EnglishCourse?> _load(Textbook book) async {
    final f = await _file(book);
    if (!await f.exists()) return null;
    if (await f.length() > maxBytes) throw const FormatException('英语课程文件过大');
    final chunks = <int>[];
    await for (final chunk in f.openRead()) {
      if (chunks.length + chunk.length > maxBytes) {
        throw const FormatException('英语课程文件过大');
      }
      chunks.addAll(chunk);
    }
    final course = EnglishCourse.fromJson(jsonDecode(utf8.decode(chunks)));
    course.matchBook(book);
    return course;
  }

  Future<EnglishCourse?> load(Textbook book) => _serial(() => _load(book));
  Future<T> withCurrent<T>(
    Textbook book,
    Future<T> Function(EnglishCourse?) action,
  ) => _serial(() async => action(await _load(book)));
  Future<void> drain() => _serial(() async {});

  Future<void> clear(Textbook book, {required void Function() check}) =>
      _serial(() async {
        check();
        final file = await _file(book);
        check();
        if (await file.exists()) {
          check();
          await file.delete();
        }
      });

  Future<EnglishCourse> _write(
    Textbook book,
    EnglishCourse next,
    void Function() check,
  ) async {
    check();
    final validated = EnglishCourse.fromJson(next.toJson());
    validated.matchBook(book);
    final bytes = utf8.encode(jsonEncode(validated.toJson()));
    if (bytes.length > maxBytes) throw const FormatException('英语课程文件过大');
    final file = await _file(book);
    await file.parent.create(recursive: true);
    check();
    final temporary = File('${file.path}.pending');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      check();
      await temporary.rename(file.path);
      return validated;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<EnglishCourse> seed(
    Textbook book,
    EnglishCourse outline, {
    required void Function() check,
  }) => _serial(() async {
    check();
    final old = await _load(book);
    if (old == null) return _write(book, outline, check);
    final merged = [
      for (final plan in outline.lessons) old.lesson(plan.id) ?? plan,
      ...old.lessons.where((l) => outline.lesson(l.id) == null),
    ];
    return _write(
      book,
      old.change({
        'lessons': merged.map((l) => l.toJson()).toList(),
        'coverage': outline.toJson()['coverage'],
        'parserVersion': outline.parserVersion,
        'revision': old.revision + 1,
      }),
      check,
    );
  });

  Future<EnglishCourse> saveGenerated(
    Textbook book,
    EnglishLesson lesson, {
    required void Function() check,
  }) => _serial(() async {
    check();
    final course = await _load(book);
    if (course == null) throw const FormatException('请先整理课程目录');
    final old = course.lesson(lesson.id);
    final protected = old != null && (old.edited || old.approvedCount > 0);
    final lessons = [...course.lessons],
        pending = [...course.pending]..removeWhere((l) => l.id == lesson.id);
    if (protected) {
      pending.add(lesson);
    } else {
      final index = lessons.indexWhere((l) => l.id == lesson.id);
      if (index < 0) {
        lessons.add(lesson);
      } else {
        lessons[index] = lesson;
      }
    }
    return _write(
      book,
      course.change({
        'lessons': lessons.map((l) => l.toJson()).toList(),
        'pending': pending.map((l) => l.toJson()).toList(),
        'revision': course.revision + 1,
      }),
      check,
    );
  });

  Future<EnglishCourse> saveLesson(
    Textbook book,
    EnglishLesson lesson, {
    required int expectedRevision,
    required void Function() check,
    bool adopt = false,
  }) => _serial(() async {
    check();
    final course = await _load(book);
    if (course == null ||
        course.revision != expectedRevision ||
        course.lesson(lesson.id) == null) {
      throw const FormatException('课程已变化，请返回重新打开，当前修改仍保留');
    }
    final next = lesson.change({'edited': true, 'prepared': true});
    return _write(
      book,
      course.change({
        'lessons': course.lessons
            .map((l) => (l.id == lesson.id ? next : l).toJson())
            .toList(),
        'pending': course.pending
            .where((l) => !adopt || l.id != lesson.id)
            .map((l) => l.toJson())
            .toList(),
        'revision': course.revision + 1,
      }),
      check,
    );
  });
}
