import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/domain/textbook_pinyin.dart';

void main() {
  test('为连续中文生成逐字带调拼音，并保留标点占位', () {
    expect(
      generateTextbookPinyin('小青蛙。\n春风'),
      ['xiǎo', 'qīng', 'wā', '。', 'chūn', 'fēng'],
    );
  });
}
