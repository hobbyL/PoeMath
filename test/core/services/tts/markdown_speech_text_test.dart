// test/core/services/tts/markdown_speech_text_test.dart
//
// markdownToSpeechText 单元测试：Markdown + LaTeX → 朗读用纯文本。
// 覆盖：markdown 符号清洗（标题/列表/引用/强调/链接/代码块/表格）、
// LaTeX 常用命令的中文口语转换（分数/根号/乘除/比较/百分号/角度/上标）、
// 嵌套分数展开与未识别命令的兜底。

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/tts/markdown_speech_text.dart';

void main() {
  group('markdown 符号清洗', () {
    test('纯文本原样保留（仅折叠空白）', () {
      expect(markdownToSpeechText('你好，我是 AI 助手。'), '你好，我是 AI 助手。');
    });

    test('标题井号与强调星号被剥离', () {
      const input = '## 小标题\n**加粗**与*斜体*和__下划线__';
      expect(markdownToSpeechText(input), '小标题\n加粗与斜体和下划线');
    });

    test('有序与无序列表符号被剥离', () {
      const input = '- 第一项\n* 第二项\n1. 第三项\n2、第四项';
      expect(
        markdownToSpeechText(input),
        '第一项\n第二项\n第三项\n第四项',
      );
    });

    test('引用符号与水平分割线被剥离', () {
      const input = '> 引用内容\n---\n正文';
      expect(markdownToSpeechText(input), '引用内容\n正文');
    });

    test('链接保留文字、丢弃地址；图片整体移除', () {
      const input = '详情见[官网](https://example.com)哦\n![插图](http://a.png) 描述';
      expect(markdownToSpeechText(input), '详情见官网哦\n描述');
    });

    test('代码块整块移除，行内代码去反引号', () {
      const input = '看代码：\n```dart\nprint(1);\n```\n运行 `flutter test` 即可';
      expect(markdownToSpeechText(input), '看代码：\n运行 flutter test 即可');
    });

    test('表格分隔行丢弃，数据行的竖线换空格', () {
      const input = '| 项 | 值 |\n| --- | --- |\n| 半径 | 5 |';
      expect(markdownToSpeechText(input), '项 值\n半径 5');
    });
  });

  group('LaTeX 中文口语转换', () {
    test('分数：分母在前（\\frac{1}{2} → 2分之1）', () {
      expect(markdownToSpeechText(r'结果是 $\frac{1}{2}$ 哦'), '结果是 2分之1 哦');
    });

    test('嵌套分数最多展开三层', () {
      expect(
        markdownToSpeechText(r'$\frac{1}{\frac{1}{2}}$'),
        '2分之1分之1',
      );
    });

    test('四则运算命令', () {
      expect(
        markdownToSpeechText(r'$3 \times 4 = 12$，$12 \div 4 = 3$'),
        '3 乘以 4 = 12，12 除以 4 = 3',
      );
    });

    test('比较命令（\\leq 优先于 \\le，不被前缀误吃）', () {
      expect(
        markdownToSpeechText(r'$x \leq 5$ 且 $y \le 3$'),
        'x 小于等于 5 且 y 小于等于 3',
      );
    });

    test('百分号前置重排：50\\% → 百分之50', () {
      expect(markdownToSpeechText(r'$50\%$ 的同学'), '百分之50 的同学');
    });

    test('角度：90^\\circ → 90度', () {
      expect(markdownToSpeechText(r'$90^\circ$ 是直角'), '90度 是直角');
    });

    test('上标：平方/立方/n 次方', () {
      expect(
        markdownToSpeechText(r'$x^{2} + x^{3} = 0$，$2^{10}$'),
        'x的平方 + x的立方 = 0，2的10次方',
      );
    });

    test('根号', () {
      expect(markdownToSpeechText(r'$\sqrt{16} = 4$'), '根号16 = 4');
    });

    test(r'块级公式 $$…$$ 与 \[…\] / \(…\) 定界符', () {
      expect(
        markdownToSpeechText(r'$$x = 1$$ 结束 \[y = 2\] 后 \(z = 3\)'),
        'x = 1 结束 y = 2 后 z = 3',
      );
    });

    test('未识别命令去命令名、保留参数文本', () {
      expect(markdownToSpeechText(r'$l = 5\text{厘米}$'), 'l = 5 厘米');
    });

    test('圆周率', () {
      expect(
        markdownToSpeechText(r'周长是 $2\pi r$'),
        '周长是 2圆周率 r',
      );
    });
  });

  group('混合典型回答', () {
    test('标题 + 加粗 + 分数 + 代码块的完整回答', () {
      const input = r'''### 解题步骤
**第一步**：通分，$\frac{1}{2} = \frac{2}{4}$。
- 第二步：相加
```
1 + 1 = 2
```
所以答案是 $\frac{3}{4}$。''';
      const expected = '解题步骤\n'
          '第一步：通分，2分之1 = 4分之2。\n'
          '第二步：相加\n'
          '所以答案是 4分之3。';
      expect(markdownToSpeechText(input), expected);
    });

    test('全代码块回答清洗后为空（调用方据此提示无可朗读内容）', () {
      expect(markdownToSpeechText('```\nprint(1);\n```'), '');
    });
  });
}
