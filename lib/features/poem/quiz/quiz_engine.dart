// lib/features/poem/quiz/quiz_engine.dart
//
// 诗词测试引擎：从诗词内容自动生成填空题和选择题。
// 纯 Dart，无 Flutter 依赖。

import 'dart:math';

import 'package:poemath/data/models/poem.dart';
import 'package:poemath/features/poem/quiz/quiz_models.dart';

/// 诗词测试引擎。
class QuizEngine {
  const QuizEngine._();

  /// 生成填空题。
  ///
  /// 将诗词按行配对（上下句），挖去下句的后半部分作为答案。
  /// [maxQuestions] 最大题目数，默认 5。
  static List<QuizQuestion> generateFillBlank(
    Poem poem, {
    int maxQuestions = 5,
    Random? random,
  }) {
    final r = random ?? Random();
    final lines = _splitLines(poem.content);
    if (lines.length < 2) return [];

    final pairs = _buildPairs(lines);
    if (pairs.isEmpty) return [];

    // 随机打乱后取 maxQuestions 道
    final shuffled = List<_LinePair>.from(pairs)..shuffle(r);
    final count = shuffled.length.clamp(2, maxQuestions);

    return shuffled.take(count).map((pair) {
      final blankResult = _createBlank(pair.line, r);
      return QuizQuestion(
        type: QuizType.fillBlank,
        contextLine: pair.context,
        promptLine: blankResult.prompt,
        correctAnswer: blankResult.answer,
      );
    }).toList();
  }

  /// 生成选择题。
  ///
  /// 以上句为题干，下句为正确答案，从同诗/其他诗选干扰项。
  /// [extraLines] 额外的干扰项候选行（来自同年级/同作者诗词）。
  /// [maxQuestions] 最大题目数，默认 5。
  static List<QuizQuestion> generateMultipleChoice(
    Poem poem, {
    List<String> extraLines = const [],
    int maxQuestions = 5,
    Random? random,
  }) {
    final r = random ?? Random();
    final lines = _splitLines(poem.content);
    if (lines.length < 2) return [];

    final pairs = _buildPairs(lines);
    if (pairs.isEmpty) return [];

    // 收集所有可用干扰项（本诗其他行 + 外部行）
    final allLines = <String>{...lines, ...extraLines};

    final shuffled = List<_LinePair>.from(pairs)..shuffle(r);
    final count = shuffled.length.clamp(2, maxQuestions);

    return shuffled.take(count).map((pair) {
      final distractors = _pickDistractors(
        correctAnswer: pair.line,
        allLines: allLines,
        contextLine: pair.context,
        count: 3,
        random: r,
      );

      final options = [pair.line, ...distractors]..shuffle(r);

      return QuizQuestion(
        type: QuizType.multipleChoice,
        contextLine: pair.context,
        promptLine: pair.context,
        correctAnswer: pair.line,
        options: options,
      );
    }).toList();
  }

  /// 从多首诗中收集额外干扰行。
  static List<String> collectExtraLines(
    List<Poem> poems, {
    String? excludeId,
    int maxLines = 20,
    Random? random,
  }) {
    final r = random ?? Random();
    final lines = <String>[];
    for (final poem in poems) {
      if (poem.id == excludeId) continue;
      lines.addAll(_splitLines(poem.content));
    }
    lines.shuffle(r);
    return lines.take(maxLines).toList();
  }

  // ============ 内部方法 ============

  /// 将诗词正文按行拆分，过滤空行和纯标点行。
  static List<String> _splitLines(String content) {
    return content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && l.length > 1)
        .toList();
  }

  /// 将行配对为上下句组合。
  /// 偶数行为上句（context），奇数行为下句（line）。
  static List<_LinePair> _buildPairs(List<String> lines) {
    final pairs = <_LinePair>[];
    for (var i = 0; i < lines.length - 1; i += 2) {
      pairs.add(_LinePair(context: lines[i], line: lines[i + 1]));
    }
    // 如果行数为奇数，最后一行用倒数第二行作为 context
    if (lines.length.isOdd && lines.length >= 3) {
      pairs.add(
        _LinePair(context: lines[lines.length - 2], line: lines.last),
      );
    }
    return pairs;
  }

  /// 在一行中创建填空：截取后半部分作为答案。
  static _BlankResult _createBlank(String line, Random random) {
    final chars = line.runes.map(String.fromCharCode).toList();
    if (chars.length <= 2) {
      // 极短行：整行挖空
      return _BlankResult(prompt: '____', answer: line);
    }

    // 挖后半部分（从中间位置开始）
    final splitPos = chars.length ~/ 2;
    final promptPart = chars.sublist(0, splitPos).join();
    final answerPart = chars.sublist(splitPos).join();

    return _BlankResult(
      prompt: '${promptPart}____',
      answer: answerPart,
    );
  }

  /// 从候选行中选择干扰项。
  static List<String> _pickDistractors({
    required String correctAnswer,
    required Set<String> allLines,
    required String contextLine,
    required int count,
    required Random random,
  }) {
    final candidates = allLines
        .where((l) => l != correctAnswer && l != contextLine)
        .toList()
      ..shuffle(random);

    if (candidates.length >= count) {
      return candidates.sublist(0, count);
    }

    // 不足时补充变形行
    final result = List<String>.from(candidates);
    while (result.length < count) {
      final firstChar = String.fromCharCode(correctAnswer.runes.first);
      result.add('$firstChar…… (无此句)');
    }
    return result;
  }
}

/// 上下句配对。
class _LinePair {
  const _LinePair({required this.context, required this.line});

  /// 上句（题干/上下文）。
  final String context;

  /// 下句（正确答案 / 被挖空的行）。
  final String line;
}

/// 填空结果。
class _BlankResult {
  const _BlankResult({required this.prompt, required this.answer});

  /// 带 ____ 的题干。
  final String prompt;

  /// 正确答案。
  final String answer;
}
