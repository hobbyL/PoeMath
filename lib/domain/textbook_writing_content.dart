import 'dart:convert';

import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/domain/textbook_recognition_content.dart';

/// 写一写单字目标：教材会写字 + 字级内容指纹。
///
/// 指纹包含笔顺数据可用性（[hasStrokeData]）：资产覆盖变化后旧进度失效，
/// 与认一认的指纹失效语义一致（课程内容/审核变化 → 指纹变化 → 重进）。
class WritingTarget {
  const WritingTarget({
    required this.node,
    required this.fingerprint,
    required this.cardPinyin,
    required this.hasStrokeData,
  });

  final TextbookCourseVocabulary node;
  final String fingerprint;

  /// 卡片展示注音；与认一认同源（教材注音优先，缺失时从课内词句取同字读音）。
  final String cardPinyin;

  /// 该字是否有笔顺数据（无则练习页降级，AC6）。
  final bool hasStrokeData;

  String get id => node.id;
  String get text => node.text;
  String get pinyin => cardPinyin;
}

/// 字级指纹：教材版本 + 课目 + 目标内容（含审核）+ 笔顺数据可用性。
String writingTargetFingerprint({
  required TextbookCoursePack pack,
  required TextbookCourseLesson lesson,
  required TextbookCourseVocabulary target,
  required bool hasStrokeData,
}) =>
    textbookTextDigest(
      jsonEncode({
        'edition': pack.edition.toJson(),
        'lessonId': lesson.id,
        'target': target.toJson(),
        'hasStrokeData': hasStrokeData,
      }),
    );

/// 从课程包构建一课的全部写字目标。
///
/// [hasStrokeData] 须传入已加载笔顺资产的同步查询（hasStrokeDataSync），
/// 保证指纹与练习页降级判定使用同一份事实。
List<WritingTarget> writingTargets(
  TextbookCoursePack pack,
  TextbookCourseLesson lesson, {
  required bool Function(String character) hasStrokeData,
}) =>
    [
      for (final target in lesson.writingCharacters)
        () {
          final available = hasStrokeData(target.text);
          return WritingTarget(
            node: target,
            fingerprint: writingTargetFingerprint(
              pack: pack,
              lesson: lesson,
              target: target,
              hasStrokeData: available,
            ),
            cardPinyin: recognitionCardPinyin(lesson, target),
            hasStrokeData: available,
          );
        }(),
    ];

/// 课级指纹：全部写字目标的 [id, 指纹, 笔顺数据可用性] 摘要。
String writingLessonFingerprint(List<WritingTarget> targets) =>
    textbookTextDigest(
      jsonEncode([
        for (final target in targets)
          [target.id, target.fingerprint, target.hasStrokeData],
      ]),
    );
