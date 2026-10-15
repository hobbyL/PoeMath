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
    final count = _boundedCount(shuffled.length, maxQuestions);

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
    final count = _boundedCount(shuffled.length, maxQuestions);

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

  /// 生成"选作者"题目。
  ///
  /// 给出某首诗的一句，从 4 个诗人中选正确作者。
  /// [allPoems] 用于采集干扰项作者。
  static List<QuizQuestion> generateChooseAuthor(
    Poem poem, {
    required List<Poem> allPoems,
    int maxQuestions = 5,
    Random? random,
  }) {
    final r = random ?? Random();
    final lines = _splitLines(poem.content);
    if (lines.isEmpty) return [];

    // 收集其他作者作为干扰项
    final otherAuthors = <String>{};
    for (final p in allPoems) {
      if (p.author != poem.author) {
        otherAuthors.add(p.author);
      }
    }

    final shuffledLines = List<String>.from(lines)..shuffle(r);
    final count = _boundedCount(shuffledLines.length, maxQuestions);

    return shuffledLines.take(count).map((line) {
      final distractors = _pickStringDistractors(
        correct: poem.author,
        candidates: otherAuthors,
        count: 3,
        random: r,
        fallbackPrefix: '佚名',
      );
      final options = [poem.author, ...distractors]..shuffle(r);

      return QuizQuestion(
        type: QuizType.chooseAuthor,
        contextLine: '「$line」',
        promptLine: '这句诗的作者是谁？',
        correctAnswer: poem.author,
        options: options,
      );
    }).toList();
  }

  /// 生成"选朝代"题目。
  ///
  /// 给出诗题 + 作者，从 4 个朝代中选正确朝代。
  /// [allPoems] 用于采集干扰项朝代。
  static List<QuizQuestion> generateChooseDynasty(
    Poem poem, {
    required List<Poem> allPoems,
    int maxQuestions = 3,
    Random? random,
  }) {
    final r = random ?? Random();

    // 收集其他朝代作为干扰项
    final otherDynasties = <String>{};
    for (final p in allPoems) {
      if (p.dynasty != poem.dynasty) {
        otherDynasties.add(p.dynasty);
      }
    }

    // 朝代题只需 1-3 道（一首诗只有一个朝代）
    final count = maxQuestions.clamp(1, 3);
    final lines = _splitLines(poem.content);
    final shuffledLines = List<String>.from(lines)..shuffle(r);

    return List.generate(count.clamp(0, shuffledLines.length), (i) {
      final contextLine = shuffledLines[i];
      final distractors = _pickStringDistractors(
        correct: poem.dynasty,
        candidates: otherDynasties,
        count: 3,
        random: r,
        fallbackPrefix: '朝',
      );
      final options = [poem.dynasty, ...distractors]..shuffle(r);

      return QuizQuestion(
        type: QuizType.chooseDynasty,
        contextLine: '《${poem.title}》 ${poem.author}\n「$contextLine」',
        promptLine: '这首诗的朝代是？',
        correctAnswer: poem.dynasty,
        options: options,
      );
    });
  }

  /// 从候选字符串中选择干扰项。
  static List<String> _pickStringDistractors({
    required String correct,
    required Set<String> candidates,
    required int count,
    required Random random,
    required String fallbackPrefix,
  }) {
    final pool = candidates.where((c) => c != correct).toList()..shuffle(random);
    final result = pool.take(count).toList();

    // 不足时补充占位项
    if (result.length < count) {
      result.addAll(
        _buildFallbacks(
          prefix: fallbackPrefix,
          needed: count - result.length,
          exclude: {...result, correct},
        ),
      );
    }
    return result;
  }

  /// 生成 [needed] 个互不相同、且不与 [exclude] 相撞的占位字符串。
  ///
  /// 一次性生成而非「循环 add 直到够数」：后者在候选与占位项重合时可能
  /// 反复产出同一个串（旧 `_pickDistractors` 的固定文案分支就是这个形态），
  /// 要么死循环、要么产出重复选项。此处同时跳过 `exclude` 中的值。
  static List<String> _buildFallbacks({
    required String prefix,
    required int needed,
    required Set<String> exclude,
  }) {
    if (needed <= 0) return const [];

    final result = <String>[];
    var idx = 1;
    while (result.length < needed) {
      final candidate = '$prefix$idx';
      if (!exclude.contains(candidate) && !result.contains(candidate)) {
        result.add(candidate);
      }
      idx++;
    }
    return result;
  }

  // ============ 内部方法 ============

  /// 题目数量：至少 2 道，至多 [maxQuestions] 道，且不超过可用素材数。
  ///
  /// 不用 `available.clamp(2, maxQuestions)` —— `num.clamp` 在
  /// `lower > upper` 时抛 `ArgumentError`，即 `maxQuestions < 2` 会直接崩。
  /// 当前调用方恰好都不触发，但这是悬着的坑。
  static int _boundedCount(int available, int maxQuestions) {
    return min(available, max(2, maxQuestions));
  }

  /// 将诗词正文按行拆分，过滤空行和纯标点行。
  ///
  /// **不再丢弃单字行**：`_splitLines` 的结果决定 `_buildPairs` 的配对，
  /// 少一行就会让其后所有行整体错位（上句配到下句、题干与答案不再对应）。
  /// 单字行（如某些词的领字）由 `_createBlank` 的 `chars.length <= 2`
  /// 分支按「整行挖空」处理，`_buildPairs` 也只按索引配对、对行长无假设。
  static List<String> _splitLines(String content) {
    return content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
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

    // 不足时补充变形行（复用占位生成，保证互异且不与正确答案重合）
    final result = List<String>.from(candidates);
    final firstChar = String.fromCharCode(correctAnswer.runes.first);
    result.addAll(
      _buildFallbacks(
        prefix: '$firstChar…… (无此句) ',
        needed: count - result.length,
        exclude: {...candidates, correctAnswer, contextLine},
      ),
    );
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
