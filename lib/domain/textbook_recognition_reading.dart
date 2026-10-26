import 'package:lpinyin/lpinyin.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/domain/textbook_recognition_content.dart';

enum RecognitionReadingOutcome {
  matched,
  needsPractice,
  needsContext,
  inconclusive,
}

Set<String> _readings(String character) => PinyinHelper.convertToPinyinArray(
      character,
      PinyinFormat.WITH_TONE_NUMBER,
    ).map(recognitionPronunciation).whereType<String>().toSet();

bool recognitionReadingNeedsContext(String character) =>
    _readings(character).length > 1;

/// ASR 文本只提供本次认读匹配证据，不提供实际音频声调或发音质量分。
/// 多音字仅采用词典明确覆盖该位置的词组读音，不采用默认首读音。
RecognitionReadingOutcome matchRecognitionReading({
  required String target,
  required String pinyin,
  required String transcript,
  Iterable<TextbookCourseParagraph> contexts = const [],
}) {
  final expected = recognitionPronunciation(pinyin);
  if (expected == null ||
      target.runes.length != 1 ||
      !recognitionIsHan(target.runes.single)) {
    return RecognitionReadingOutcome.inconclusive;
  }
  final characters = <String>[];
  var ended = false;
  for (final rune in transcript.trim().runes) {
    final character = String.fromCharCode(rune);
    if (recognitionIsHan(rune)) {
      // Do not invent a word by joining separate speech segments.
      if (ended) return RecognitionReadingOutcome.inconclusive;
      characters.add(character);
    } else if (RegExp(r'^[\s，。！？、；：,.!?;:「」“”"\x27]$').hasMatch(character)) {
      if (characters.isNotEmpty) ended = true;
    } else {
      return RecognitionReadingOutcome.inconclusive;
    }
  }
  if (characters.isEmpty || characters.length > 4) {
    return RecognitionReadingOutcome.inconclusive;
  }
  if (characters.length == 1) {
    final recognized = characters.single;
    final readings = _readings(recognized);
    if (readings.isEmpty) return RecognitionReadingOutcome.inconclusive;
    if (readings.length > 1) {
      return readings.contains(expected)
          ? RecognitionReadingOutcome.needsContext
          : RecognitionReadingOutcome.needsPractice;
    }
    return readings.single == expected
        ? RecognitionReadingOutcome.matched
        : RecognitionReadingOutcome.needsPractice;
  }
  if (!characters.contains(target)) {
    return RecognitionReadingOutcome.inconclusive;
  }
  final readings = _readings(target);
  if (readings.isEmpty) return RecognitionReadingOutcome.inconclusive;
  if (readings.length == 1 && characters.every((c) => c == target)) {
    return readings.single == expected
        ? RecognitionReadingOutcome.matched
        : RecognitionReadingOutcome.inconclusive;
  }
  // Course annotations can resolve ordinary words absent from lpinyin's
  // small phrase dictionary. Conflicting occurrences never choose a default.
  final annotated = <String>{};
  for (final context in contexts) {
    final tokens = context.pinyin;
    if (tokens == null) continue;
    final runes = context.text.runes
        .where((r) => String.fromCharCode(r).trim().isNotEmpty)
        .toList();
    if (runes.length != tokens.length) continue;
    for (var start = 0; start + characters.length <= runes.length; start++) {
      if (String.fromCharCodes(
            runes.sublist(start, start + characters.length),
          ) !=
          characters.join()) {
        continue;
      }
      for (var offset = 0; offset < characters.length; offset++) {
        if (characters[offset] != target) continue;
        final pronunciation = recognitionPronunciation(tokens[start + offset]);
        if (pronunciation == null) {
          return RecognitionReadingOutcome.inconclusive;
        }
        annotated.add(pronunciation);
      }
    }
  }
  if (annotated.length > 1) return RecognitionReadingOutcome.inconclusive;
  if (annotated.isNotEmpty) {
    return annotated.single == expected
        ? RecognitionReadingOutcome.matched
        : RecognitionReadingOutcome.needsPractice;
  }
  final observed = <String>[];
  for (var index = 0; index < characters.length;) {
    final suffix = characters.sublist(index).join();
    final phrase = PinyinHelper.convertToMultiPinyin(
      suffix,
      ' ',
      PinyinFormat.WITH_TONE_NUMBER,
    );
    if (phrase?.word == null) {
      if (characters[index] == target) {
        return RecognitionReadingOutcome.needsContext;
      }
      index++;
      continue;
    }
    final length = phrase!.word!.runes.length;
    final tokens = phrase.pinyin!.trim().split(RegExp(r'\s+'));
    if (length != tokens.length) return RecognitionReadingOutcome.inconclusive;
    for (var offset = 0; offset < length; offset++) {
      if (characters[index + offset] == target) {
        final pronunciation = recognitionPronunciation(tokens[offset]);
        if (pronunciation == null) {
          return RecognitionReadingOutcome.inconclusive;
        }
        observed.add(pronunciation);
      }
    }
    index += length;
  }
  if (observed.isEmpty || observed.toSet().length != 1) {
    return RecognitionReadingOutcome.inconclusive;
  }
  return observed.first == expected
      ? RecognitionReadingOutcome.matched
      : RecognitionReadingOutcome.needsPractice;
}
