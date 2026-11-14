import 'dart:convert';

import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/domain/math_textbook_grading.dart';
import 'package:poemath/domain/math_textbook_practice.dart';

/// 已结算自动练习的原题、规则和作答快照，可随历史备份迁移。
class MathTextbookSessionContext {
  MathTextbookSessionContext({
    required this.bookId,
    required this.bookTitle,
    required this.editionId,
    required this.lessonId,
    required this.lessonDigest,
    required this.item,
    required Map<String, String> answers,
    this.planId,
  }) : answers = Map.unmodifiable(answers);
  final String bookId, bookTitle, editionId, lessonId, lessonDigest;
  final String? planId;
  final MathTextbookPracticeItem item;
  final Map<String, String> answers;
  bool get correct =>
      gradeMathTextbookExercise(item.exercise, answers).result ==
      MathTextbookResult.correct;
  Map<String, dynamic> toJson() => {
    'v': 1,
    'bookId': bookId,
    'bookTitle': bookTitle,
    'editionId': editionId,
    'lessonId': lessonId,
    'lessonDigest': lessonDigest,
    'planId': planId,
    'item': item.toJson(),
    'answers': answers,
  };
  factory MathTextbookSessionContext.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['v'] != 1 ||
        utf8.encode(jsonEncode(value)).length > 4 * 1024 * 1024) {
      throw const FormatException('数学教材练习快照格式或容量无效');
    }
    String text(String key, {int max = 160}) {
      final raw = value[key];
      if (raw is! String || raw.trim().isEmpty || raw.length > max) {
        throw FormatException('数学教材练习快照 $key 无效');
      }
      return raw;
    }

    final bookId = text('bookId'), digest = text('lessonDigest');
    if (!Textbook.isValidId(bookId) ||
        !Textbook.isValidId(digest) ||
        value['item'] is! Map<String, dynamic> ||
        value['answers'] is! Map<String, dynamic>) {
      throw const FormatException('数学教材练习快照身份或题目无效');
    }
    final item = MathTextbookPracticeItem.fromJson(
      value['item'] as Map<String, dynamic>,
    );
    final answers = (value['answers'] as Map<String, dynamic>).map((
      key,
      answer,
    ) {
      if (answer is! String || answer.length > 10000) {
        throw const FormatException('数学教材快照作答无效');
      }
      return MapEntry(key, answer);
    });
    if (item.exercise.needsParent ||
        !mathTextbookAnswersComplete(item.exercise, answers)) {
      throw const FormatException('全局自动练习记录须为完整的自动判分题');
    }
    return MathTextbookSessionContext(
      bookId: bookId,
      bookTitle: text('bookTitle', max: 200),
      editionId: text('editionId'),
      lessonId: text('lessonId'),
      lessonDigest: digest,
      planId: value['planId'] == null ? null : text('planId'),
      item: item,
      answers: answers,
    );
  }
}
