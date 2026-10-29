import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/domain/textbook_pinyin_font.dart';

void main() {
  test('还原教材拼音字体的 ASCII 大写编码', () {
    // 例词来自人教版二年级上册《小蝌蚪找妈妈》PDF 文本层。
    expect(decodeTextbookPinyinFont('chI'), 'chí');
    expect(decodeTextbookPinyinFont('tWng'), 'táng');
    expect(decodeTextbookPinyinFont('lJ'), 'lǐ');
    expect(decodeTextbookPinyinFont('yGu'), 'yǒu');
    expect(decodeTextbookPinyinFont('qPn'), 'qún');
    expect(decodeTextbookPinyinFont('xiAo'), 'xiǎo');
    expect(decodeTextbookPinyinFont('xUng'), 'xīng');
    expect(decodeTextbookPinyinFont('yuF'), 'yuè');
    expect(decodeTextbookPinyinFont('lC'), 'lǜ');
    expect(decodeTextbookPinyinFont('lV'), 'lǚ');
  });

  test('字体未定义的大写字形不冒充拼音', () {
    expect(decodeTextbookPinyinFont('lX'), isNull);
    expect(decodeTextbookPinyinFont('lB'), isNull);
  });

  test('已解码注音通过课程模型校验，原始大写编码不通过', () {
    expect(isTextbookPinyin('chí'), isTrue);
    expect(isTextbookPinyin('xiǎo'), isTrue);
    expect(isTextbookPinyin('chI'), isFalse);
  });
}
