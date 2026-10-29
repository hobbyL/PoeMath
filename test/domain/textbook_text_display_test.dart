import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/domain/textbook_text_display.dart';

void main() {
  test('诗行硬换行和空行分节保留原始 Unicode 索引，兼容CRLF', () {
    expect(
      textbookReadingLayoutForText('甲乙，\n𠀀丙。\n\n丁戊！', preserveLines: true)
          .breaks,
      {4: TextbookReadingBreak.line, 9: TextbookReadingBreak.stanza},
    );
    expect(
      textbookReadingLayoutForText('甲\r\n乙\r\n　\r\n丙', preserveLines: true)
          .breaks,
      {3: TextbookReadingBreak.line, 9: TextbookReadingBreak.stanza},
    );
    expect(
      textbookReadingLayoutForText('甲\n乙\n\n丙').breaks,
      {5: TextbookReadingBreak.stanza},
    );
  });

  test('折叠 PDF 视觉换行和中文排版空格', () {
    expect(textbookContinuousText('黑\n灰色'), '黑灰色');
    expect(textbookContinuousText('游来\n游去'), '游来游去');
    expect(textbookContinuousText('黑 灰色'), '黑灰色');
    expect(textbookContinuousText('池塘里有一群小蝌蚪，\n大大的脑袋。'), '池塘里有一群小蝌蚪，大大的脑袋。');
  });

  test('保留英文单词间距和中英混排间距', () {
    expect(textbookContinuousText('Hello   world'), 'Hello world');
    expect(textbookContinuousText('PDF 第 6 页'), 'PDF 第 6 页');
  });

  test('中文标点两侧不保留多余空白', () {
    expect(textbookContinuousText('看 ， 那 边 。'), '看，那边。');
  });
}
