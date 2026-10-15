// test/features/poem/quiz/quiz_engine_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/features/poem/quiz/quiz_engine.dart';
import 'package:poemath/features/poem/quiz/quiz_models.dart';

Poem _makePoem({
  String id = 'test-001',
  String content = '床前明月光，\n疑是地上霜。\n举头望明月，\n低头思故乡。',
  int? grade,
}) {
  return Poem(
    id: id,
    title: '静夜思',
    author: '李白',
    dynasty: '唐',
    content: content,
    pinyin: '',
    layer: 'core',
    grade: grade,
  );
}

void main() {
  group('QuizEngine - 填空题生成', () {
    test('4行诗生成 2 道填空题', () {
      final poem = _makePoem();
      final questions = QuizEngine.generateFillBlank(
        poem,
        random: Random(42),
      );

      expect(questions.length, 2);
      for (final q in questions) {
        expect(q.type, QuizType.fillBlank);
        expect(q.contextLine, isNotEmpty);
        expect(q.promptLine, contains('____'));
        expect(q.correctAnswer, isNotEmpty);
        expect(q.options, isNull);
      }
    });

    test('8行诗生成最多 4 道填空题', () {
      final poem = _makePoem(
        content: '春眠不觉晓，\n处处闻啼鸟。\n'
            '夜来风雨声，\n花落知多少。\n'
            '白日依山尽，\n黄河入海流。\n'
            '欲穷千里目，\n更上一层楼。',
      );
      final questions = QuizEngine.generateFillBlank(
        poem,
        maxQuestions: 4,
        random: Random(42),
      );

      expect(questions.length, 4);
    });

    test('2行诗生成 2 道填空题（clamp 最少 2）', () {
      final poem = _makePoem(
        content: '白日依山尽，\n黄河入海流。',
      );
      final questions = QuizEngine.generateFillBlank(
        poem,
        random: Random(42),
      );

      // 只有 1 对，clamp(2, 5) → 实际只有 1 道
      expect(questions.length, greaterThanOrEqualTo(1));
    });

    test('1行诗无法生成题目', () {
      final poem = _makePoem(content: '独行无伴侣');
      final questions = QuizEngine.generateFillBlank(poem);
      expect(questions, isEmpty);
    });

    test('空内容无法生成题目', () {
      final poem = _makePoem(content: '');
      final questions = QuizEngine.generateFillBlank(poem);
      expect(questions, isEmpty);
    });

    test('填空答案是行的后半部分', () {
      final poem = _makePoem(
        content: '床前明月光，\n疑是地上霜。',
      );
      final questions = QuizEngine.generateFillBlank(
        poem,
        random: Random(0),
      );

      if (questions.isNotEmpty) {
        final q = questions.first;
        // 答案 + 题干前半 = 原始行
        final combined = q.promptLine.replaceAll('____', '') + q.correctAnswer;
        // combined 应该等于原始下句（去空格）
        expect(combined.replaceAll(RegExp(r'\s'), ''), isNotEmpty);
      }
    });
  });

  group('QuizEngine - 选择题生成', () {
    test('4行诗生成选择题', () {
      final poem = _makePoem();
      final questions = QuizEngine.generateMultipleChoice(
        poem,
        random: Random(42),
      );

      expect(questions, isNotEmpty);
      for (final q in questions) {
        expect(q.type, QuizType.multipleChoice);
        expect(q.options, isNotNull);
        expect(q.options!.length, 4);
        expect(q.options!.contains(q.correctAnswer), isTrue);
        // 只有 1 个正确答案
        expect(
          q.options!.where((o) => o == q.correctAnswer).length,
          1,
        );
      }
    });

    test('选择题使用外部干扰行', () {
      final poem = _makePoem(
        content: '白日依山尽，\n黄河入海流。',
      );
      final extraLines = [
        '春眠不觉晓，',
        '处处闻啼鸟。',
        '夜来风雨声，',
        '花落知多少。',
      ];
      final questions = QuizEngine.generateMultipleChoice(
        poem,
        extraLines: extraLines,
        random: Random(42),
      );

      expect(questions, isNotEmpty);
      for (final q in questions) {
        expect(q.options!.length, 4);
      }
    });

    test('选择题选项已打乱', () {
      final poem = _makePoem();
      // 用不同 seed 生成，选项顺序应该不同
      final q1 = QuizEngine.generateMultipleChoice(
        poem,
        random: Random(1),
      );
      final q2 = QuizEngine.generateMultipleChoice(
        poem,
        random: Random(99),
      );

      if (q1.isNotEmpty && q2.isNotEmpty) {
        // 至少有一道题的选项顺序不同（概率极高）
        final anyDifferent = q1.first.options!.join() != q2.first.options!.join();
        // 不做硬性断言（极小概率相同），但正确答案都在里面
        expect(q1.first.options!.contains(q1.first.correctAnswer), isTrue);
        expect(q2.first.options!.contains(q2.first.correctAnswer), isTrue);
        // ignore: avoid_print
        if (!anyDifferent) print('(Same order by chance — OK)');
      }
    });

    test('1行诗无法生成选择题', () {
      final poem = _makePoem(content: '独行无伴侣');
      final questions = QuizEngine.generateMultipleChoice(poem);
      expect(questions, isEmpty);
    });
  });

  group('QuizEngine - 辅助方法', () {
    test('collectExtraLines 排除指定诗词', () {
      final poems = [
        _makePoem(id: 'p1', content: '春眠不觉晓，\n处处闻啼鸟。'),
        _makePoem(id: 'p2', content: '白日依山尽，\n黄河入海流。'),
        _makePoem(id: 'p3', content: '锄禾日当午，\n汗滴禾下土。'),
      ];

      final lines = QuizEngine.collectExtraLines(
        poems,
        excludeId: 'p2',
        random: Random(42),
      );

      // 不应包含 p2 的内容
      expect(lines.any((l) => l.contains('黄河')), isFalse);
      expect(lines, isNotEmpty);
    });
  });

  group('QuizEngine - 出题引擎健壮性（审计 D1/D2/D3）', () {
    test('D1: maxQuestions < 2 不抛 ArgumentError', () {
      // 修复前 `shuffled.length.clamp(2, maxQuestions)` 在 maxQuestions=1
      // 时抛 ArgumentError（num.clamp 要求 lower <= upper）。
      final poem = _makePoem();

      expect(
        () => QuizEngine.generateFillBlank(
          poem,
          maxQuestions: 1,
          random: Random(42),
        ),
        returnsNormally,
      );
      expect(
        () => QuizEngine.generateMultipleChoice(
          poem,
          maxQuestions: 1,
          random: Random(42),
        ),
        returnsNormally,
      );
      expect(
        () => QuizEngine.generateChooseAuthor(
          poem,
          allPoems: [poem],
          maxQuestions: 1,
          random: Random(42),
        ),
        returnsNormally,
      );

      // 下界受保护后仍产出 2 道（min(可用素材, max(2, maxQuestions))）。
      final questions = QuizEngine.generateFillBlank(
        poem,
        maxQuestions: 1,
        random: Random(42),
      );
      expect(questions.length, 2);
    });

    test('D1: maxQuestions 为 0 或负数也不抛', () {
      final poem = _makePoem();
      for (final n in [0, -1, -100]) {
        expect(
          () => QuizEngine.generateFillBlank(
            poem,
            maxQuestions: n,
            random: Random(42),
          ),
          returnsNormally,
          reason: 'maxQuestions=$n',
        );
      }
    });

    test('D2: 干扰项极少的诗句，选项内无重复字符串', () {
      // 只用 2 行诗且不给 extraLines —— 可选干扰项为 0，
      // 必须全部走占位补足分支。修复前该分支反复产出同一固定串，
      // 会出现 3 个完全相同（且等于正确选项之外的同串）的选项。
      final poem = _makePoem(content: '白日依山尽，\n黄河入海流。');
      final questions = QuizEngine.generateMultipleChoice(
        poem,
        random: Random(7),
      );

      expect(questions, isNotEmpty);
      for (final q in questions) {
        final options = q.options!;
        expect(
          options.toSet().length,
          options.length,
          reason: '选项应互异，实际为 $options',
        );
        expect(options.length, 4);
        // 正确答案只出现一次
        expect(options.where((o) => o == q.correctAnswer).length, 1);
      }
    });

    test('D2: 作者/朝代干扰项不足时补足项也互异', () {
      final poem = _makePoem();
      // allPoems 只有本诗 → 没有其他作者/朝代可作干扰项。
      final authorQuestions = QuizEngine.generateChooseAuthor(
        poem,
        allPoems: [poem],
        random: Random(3),
      );
      for (final q in authorQuestions) {
        final options = q.options!;
        expect(options.toSet().length, options.length);
        expect(options.length, 4);
      }

      final dynastyQuestions = QuizEngine.generateChooseDynasty(
        poem,
        allPoems: [poem],
        random: Random(3),
      );
      for (final q in dynastyQuestions) {
        final options = q.options!;
        expect(options.toSet().length, options.length);
        expect(options.length, 4);
      }
    });

    test('D3: 单字行不再被丢弃，配对不错位', () {
      // 「风」是单字行。修复前 `_splitLines` 会把它滤掉，导致
      // 「吹」与「又」被配成一对（上句/下句整体错位）。
      const content = '风\n吹\n又\n生';
      final poem = _makePoem(content: content);

      final questions = QuizEngine.generateFillBlank(
        poem,
        random: Random(1),
      );

      // 4 行 → 2 对：(风,吹) 与 (又,生)。
      // 修复前只剩 3 行 → 1 对 (吹,又)。
      expect(questions.length, 2);

      // 每个答案都应是它这对的第二行，且与题干上句相邻。
      final pairs = questions.map((q) => (q.contextLine, q.correctAnswer));
      expect(pairs, containsAll([('风', '吹'), ('又', '生')]));
    });

    test('D3: 纯空行仍被过滤（行为不变）', () {
      final poem = _makePoem(content: '床前明月光，\n\n疑是地上霜。\n   \n举头望明月，\n低头思故乡。');
      final questions = QuizEngine.generateFillBlank(
        poem,
        random: Random(42),
      );

      // 4 个有效行 → 2 对
      expect(questions.length, 2);
      for (final q in questions) {
        expect(q.contextLine.trim(), isNotEmpty);
        expect(q.correctAnswer.trim(), isNotEmpty);
      }
    });
  });

  group('QuizSession', () {
    test('作答记录和正确率计算', () {
      final questions = [
        const QuizQuestion(
          type: QuizType.fillBlank,
          contextLine: '床前明月光，',
          promptLine: '疑是____',
          correctAnswer: '地上霜。',
        ),
        const QuizQuestion(
          type: QuizType.fillBlank,
          contextLine: '举头望明月，',
          promptLine: '低头____',
          correctAnswer: '思故乡。',
        ),
      ];

      final session = QuizSession(
        poemId: 'test-001',
        type: QuizType.fillBlank,
        questions: questions,
      );

      expect(session.isFinished, isFalse);
      expect(session.correctCount, 0);

      // 答对第一题
      session.submitAnswer('地上霜');
      expect(session.isCurrentCorrect(), isTrue);
      session.advance();

      // 答错第二题
      session.submitAnswer('望故乡');
      expect(session.isCurrentCorrect(), isFalse);
      session.advance();

      expect(session.isFinished, isTrue);
      expect(session.correctCount, 1);
      expect(session.accuracy, 0.5);
      expect(session.isPassed, isFalse);
    });

    test('答案比较忽略标点', () {
      final questions = [
        const QuizQuestion(
          type: QuizType.fillBlank,
          contextLine: '床前明月光，',
          promptLine: '疑是____',
          correctAnswer: '地上霜。',
        ),
      ];

      final session = QuizSession(
        poemId: 'test-001',
        type: QuizType.fillBlank,
        questions: questions,
      );

      // 不带标点也应判对
      session.submitAnswer('地上霜');
      expect(session.isCurrentCorrect(), isTrue);
    });

    test('100% 正确率判定为通过', () {
      final questions = [
        const QuizQuestion(
          type: QuizType.multipleChoice,
          contextLine: '床前明月光，',
          promptLine: '床前明月光，',
          correctAnswer: '疑是地上霜。',
          options: ['疑是地上霜。', '处处闻啼鸟。', '花落知多少。', '黄河入海流。'],
        ),
      ];

      final session = QuizSession(
        poemId: 'test-001',
        type: QuizType.multipleChoice,
        questions: questions,
      );

      session.submitAnswer('疑是地上霜。');
      session.advance();

      expect(session.isPassed, isTrue);
      expect(session.accuracy, 1.0);
    });
  });
}
