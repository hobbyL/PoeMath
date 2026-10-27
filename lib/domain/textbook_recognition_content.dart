import 'dart:convert';

import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/domain/textbook_narration.dart';
import 'package:poemath/domain/textbook_pinyin.dart';

bool recognitionIsHan(int r) =>
    r == 0x3007 ||
    (r >= 0x3400 && r <= 0x4dbf) ||
    (r >= 0x4e00 && r <= 0x9fff) ||
    (r >= 0xf900 && r <= 0xfaff) ||
    (r >= 0x20000 && r <= 0x323af);

/// 保留声调；未知、轻声未明确的拼音不作为客观听音依据。
String? recognitionPronunciation(String value) {
  var text =
      value.toLowerCase().trim().replaceAll('u:', 'ü').replaceAll('v', 'ü');
  const marks = ['āáǎà', 'ēéěè', 'īíǐì', 'ōóǒò', 'ūúǔù', 'ǖǘǚǜ'];
  const bases = ['a', 'e', 'i', 'o', 'u', 'ü'];
  int? tone;
  final number = RegExp(r'[1-5]$').firstMatch(text);
  if (number != null) {
    tone = int.parse(number.group(0)!);
    text = text.substring(0, text.length - 1);
  }
  for (var b = 0; b < marks.length; b++) {
    for (var t = 0; t < 4; t++) {
      if (text.contains(marks[b][t])) {
        if (tone != null && tone != t + 1) return null;
        tone = t + 1;
        text = text.replaceAll(marks[b][t], bases[b]);
      }
    }
  }
  if (tone == null || !RegExp(r'^[a-zü]+$').hasMatch(text)) return null;
  return '$text$tone';
}

String? _recognitionPinyinIn(
  TextbookCourseParagraph node,
  String target,
) {
  final pinyin = textbookCoursePinyinForReview(node);
  var tokenIndex = 0;
  for (final rune in node.text.runes) {
    final character = String.fromCharCode(rune);
    if (character.trim().isEmpty) continue;
    if (character == target && tokenIndex < pinyin.length) {
      final candidate = pinyin[tokenIndex];
      if (recognitionPronunciation(candidate) != null) return candidate;
    }
    tokenIndex++;
  }
  return null;
}

/// 卡片展示优先使用教材注音；缺失时从本课词句的逐字注音草稿取同字读音。
///
/// 认字入口复用同一份注音；展示或听过注音本身不算认读通过。
String recognitionCardPinyin(
  TextbookCourseLesson lesson,
  TextbookCourseVocabulary target,
) {
  final direct = target.pinyin
      ?.where((token) => recognitionPronunciation(token) != null)
      .toList(growable: false);
  if (direct != null && direct.isNotEmpty) return direct.join(' ');
  for (final node in [...lesson.words, ...lesson.paragraphs]) {
    final candidate = _recognitionPinyinIn(node, target.text);
    if (candidate != null) return candidate;
  }
  return _recognitionPinyinIn(target, target.text) ?? '';
}

typedef RecognitionCardNote = ({String label, String text});

/// 仅展示课程数据中已有的相关词语；没有词语时退回含该字的课文词句。
RecognitionCardNote? recognitionCardNote(
  TextbookCourseLesson lesson,
  TextbookCourseVocabulary target,
) {
  const maxWords = 2;
  final words = <String>[];
  for (final word in lesson.words) {
    if (word.text == target.text || !word.text.contains(target.text)) continue;
    if (!words.contains(word.text)) words.add(word.text);
    if (words.length == maxWords) break;
  }
  if (words.isNotEmpty) {
    return (label: '课内词语', text: words.join('、'));
  }
  // 每个完整句独立成段，复用正文朗读的跨段整句规则；这里不能按逗号拆，
  // 否则「课文词句」会退化成半句。
  final sentences = buildTextbookNarration(
    [lesson],
    firstTarget: 1,
    target: 1,
    softLimit: 1,
    sentenceOnly: true,
  );
  for (final sentence in sentences) {
    if (sentence.text.contains(target.text)) {
      return (
        label: '课文词句',
        text: sentence.text,
      );
    }
  }
  return null;
}

class RecognitionCue {
  const RecognitionCue({
    required this.nodeId,
    required this.text,
    required this.start,
    required this.positions,
    required this.pronunciation,
  });
  final String nodeId, text, pronunciation;
  final int start;
  final List<int> positions;
  String get key => textbookTextDigest(jsonEncode(toJson()));
  Map<String, dynamic> toJson() => {
        'nodeId': nodeId,
        'text': text,
        'start': start,
        'positions': positions,
        'pronunciation': pronunciation,
      };
}

class RecognitionTarget {
  const RecognitionTarget({
    required this.node,
    required this.fingerprint,
    required this.cues,
    required this.ready,
    this.cardPinyin,
  });
  final TextbookCourseVocabulary node;
  final String fingerprint;
  final List<RecognitionCue> cues;
  final bool ready;
  final String? cardPinyin;
  String get id => node.id;
  String get text => node.text;
  String get pinyin => cardPinyin ?? node.pinyin?.first ?? '';
}

/// 直接使用认一认字卡里的生字，不要求家长审核；缺少明确注音仍可自练。
List<RecognitionTarget> recognitionTargets(
  TextbookCoursePack pack,
  TextbookCourseLesson lesson, {
  bool preview = false,
}) {
  return [
    for (final target in lesson.recognitionCharacters)
      () {
        final isCharacter = target.text.runes.length == 1 &&
            recognitionIsHan(target.text.runes.single);
        final pinyin = recognitionCardPinyin(lesson, target);
        final pronunciation = recognitionPronunciation(pinyin);
        final cues = <RecognitionCue>[];
        if (isCharacter && pronunciation != null) {
          cues.add(
            RecognitionCue(
              nodeId: target.id,
              text: target.text,
              start: 0,
              positions: const [0],
              pronunciation: pronunciation,
            ),
          );
          for (final node in [...lesson.words, ...lesson.paragraphs]) {
            if (node.sources.isEmpty || node.pinyin == null) continue;
            final runes = node.text.runes.toList();
            final tokens = <int, String>{};
            var token = 0;
            for (var r = 0; r < runes.length; r++) {
              if (String.fromCharCode(runes[r]).trim().isEmpty) continue;
              tokens[r] = node.pinyin![token++];
            }
            var start = 0;
            for (var end = 1; end <= runes.length; end++) {
              if (end != runes.length &&
                  !'。！？!?；;\n'.runes.contains(runes[end - 1])) {
                continue;
              }
              final text = String.fromCharCodes(runes.sublist(start, end));
              final positions = [
                for (var i = start; i < end; i++)
                  if (runes[i] == target.text.runes.single &&
                      recognitionPronunciation(tokens[i] ?? '') ==
                          pronunciation)
                    i - start,
              ];
              if (positions.isNotEmpty && end - start <= 40) {
                cues.add(
                  RecognitionCue(
                    nodeId: node.id,
                    text: text,
                    start: start,
                    positions: positions,
                    pronunciation: pronunciation,
                  ),
                );
              }
              start = end;
            }
          }
        }
        final relevant = {target.id, ...cues.map((c) => c.nodeId)};
        final fingerprint = textbookTextDigest(
          jsonEncode({
            'edition': pack.edition.toJson(),
            'lessonId': lesson.id,
            'lessonDigest': lesson.contentDigest,
            'lessonReview': lesson.toJson()['review'],
            'nodes': [
              for (final n in [target, ...lesson.words, ...lesson.paragraphs])
                if (relevant.contains(n.id)) n.toJson(),
            ],
            'cues': cues.map((c) => c.toJson()).toList(),
            if (pinyin != (target.pinyin?.first ?? '')) 'cardPinyin': pinyin,
          }),
        );
        final approved = {
          for (final n in [target, ...lesson.words, ...lesson.paragraphs])
            if (n.isApproved) n.id,
        };
        return RecognitionTarget(
          node: target,
          fingerprint: fingerprint,
          cues: cues
              .where(
                (c) =>
                    preview ||
                    c.nodeId == target.id ||
                    approved.contains(c.nodeId),
              )
              .toList(),
          ready: isCharacter,
          cardPinyin: pinyin,
        );
      }(),
  ];
}

String recognitionLessonFingerprint(List<RecognitionTarget> targets) =>
    textbookTextDigest(
      jsonEncode([
        for (final t in targets) [t.id, t.fingerprint, t.ready],
      ]),
    );
