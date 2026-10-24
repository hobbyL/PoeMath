import 'package:lpinyin/lpinyin.dart';
import 'package:poemath/data/models/textbook_course.dart';

final RegExp _validPinyin = RegExp(
  r'^[a-züāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜêńňǹḿ]+[1-5]?$',
);

bool _isHan(int rune) =>
    rune == 0x3007 ||
    (rune >= 0x3400 && rune <= 0x4dbf) ||
    (rune >= 0x4e00 && rune <= 0x9fff) ||
    (rune >= 0xf900 && rune <= 0xfaff) ||
    (rune >= 0x20000 && rune <= 0x323af);

/// 为审核界面生成逐字、带声调的拼音草稿。
///
/// 连续汉字按词组交给 lpinyin，以便使用其多音词词典；空白不占 token，
/// 标点和其他字符原样占位。无法识别的生僻字显示 `?`，保存时仍会被课程
/// 模型校验拦截，审核者可以在编辑页补正。
List<String> generateTextbookPinyin(String text) {
  final characters = text.runes.map(String.fromCharCode).toList();
  final tokens = <String>[];
  var index = 0;
  while (index < characters.length) {
    final character = characters[index];
    if (character.trim().isEmpty) {
      index++;
      continue;
    }
    if (!_isHan(character.runes.single)) {
      tokens.add(character);
      index++;
      continue;
    }

    final phrase = <String>[];
    while (
        index < characters.length && _isHan(characters[index].runes.single)) {
      phrase.add(characters[index]);
      index++;
    }
    final generated = PinyinHelper.getPinyinE(
      phrase.join(),
      separator: ' ',
      defPinyin: '?',
      format: PinyinFormat.WITH_TONE_MARK,
    ).trim().split(RegExp(r'\s+'));
    if (generated.length == phrase.length &&
        generated.every(_validPinyin.hasMatch)) {
      tokens.addAll(generated);
      continue;
    }
    for (final han in phrase) {
      final candidates = PinyinHelper.convertToPinyinArray(
        han,
        PinyinFormat.WITH_TONE_MARK,
      );
      tokens.add(candidates.isEmpty ? '?' : candidates.first);
    }
  }
  return List.unmodifiable(tokens);
}

/// 原书有完整注音时优先使用；否则提供可在编辑页修正的自动草稿。
List<String> textbookCoursePinyinForReview(TextbookCourseParagraph node) =>
    node.pinyin ?? generateTextbookPinyin(node.text);
