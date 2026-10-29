import 'dart:math';

import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/domain/textbook_recognition_content.dart';

/// 听写只取本课会写字；课内词句用于报题，不增加听写目标。
class TextbookDictationTarget {
  const TextbookDictationTarget({
    required this.id,
    required this.text,
    required this.pinyin,
    required this.prompt,
    required this.hasContext,
  });

  final String id, text, pinyin, prompt;
  final bool hasContext;
}

List<TextbookDictationTarget> textbookDictationTargets(
  TextbookCourseLesson lesson,
) =>
    [
      for (final node in lesson.writingCharacters)
        () {
          final pinyin = recognitionCardPinyin(lesson, node);
          final pronunciation = recognitionPronunciation(pinyin);
          String? cue;
          if (pronunciation != null) {
            for (final context in [...lesson.words, ...lesson.paragraphs]) {
              cue = _contextPrompt(context, node.text, pronunciation);
              if (cue != null) break;
            }
          }
          return TextbookDictationTarget(
            id: node.id,
            text: node.text,
            pinyin: pinyin,
            // 缺少有注音的课内语境时明确降级；不虚构组词或读出拼音字母。
            prompt: cue ?? '请写：${node.text}。',
            hasContext: cue != null,
          );
        }(),
    ];

/// 非空白码点与注音对齐，标点占 token。只在目标字的读音相符时采用
/// 语境，并明确其在汉字词组中的位置，避免再孤立读一次多音字。
String? _contextPrompt(
  TextbookCourseParagraph node,
  String target,
  String pronunciation,
) {
  final pinyin = node.pinyin;
  if (pinyin == null) return null;
  final characters = <String>[];
  final tokens = <String>[];
  String? prompt() {
    if (characters.length < 2 || characters.length > 40) return null;
    for (var i = 0; i < characters.length; i++) {
      if (characters[i] == target &&
          recognitionPronunciation(tokens[i]) == pronunciation) {
        return '${characters.join()}，请写第${i + 1}个字。';
      }
    }
    return null;
  }

  var token = 0;
  for (final rune in node.text.runes) {
    final character = String.fromCharCode(rune);
    if (character.trim().isEmpty) continue;
    if (recognitionIsHan(rune)) {
      characters.add(character);
      tokens.add(token < pinyin.length ? pinyin[token] : '');
    } else {
      final found = prompt();
      if (found != null) return found;
      characters.clear();
      tokens.clear();
    }
    token++;
  }
  return prompt();
}

/// 每轮打乱一次，保持原始清单与上一轮题序不受修改。
List<TextbookDictationTarget> shuffledDictationTargets(
  Iterable<TextbookDictationTarget> targets, {
  Random? random,
}) =>
    List<TextbookDictationTarget>.of(targets)..shuffle(random);
