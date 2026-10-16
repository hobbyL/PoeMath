import 'dart:convert';

/// 作答快照的唯一编解码入口。旧活动没有明细，不能据总分补造错句。
class PoemPracticeDetails {
  const PoemPracticeDetails({
    required this.mode,
    required this.lines,
    this.targeted = false,
    this.score,
    this.rawAnswer,
  });

  final String mode;
  final List<PoemLineResult> lines;
  final bool targeted;
  final double? score;
  final String? rawAnswer;

  String encode() => jsonEncode(toJson());

  Map<String, dynamic> toJson() => {
        'v': 1,
        'mode': mode,
        'targeted': targeted,
        'score': score,
        'rawAnswer': rawAnswer,
        'lines': lines.map((line) => line.toJson()).toList(),
      };

  static PoemPracticeDetails? decode(String? json) {
    if (json == null) return null;
    final value = jsonDecode(json);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('诗词作答明细必须是对象');
    }
    return PoemPracticeDetails.fromJson(value);
  }

  factory PoemPracticeDetails.fromJson(Map<String, dynamic> json) {
    final score = json['score'];
    if (json['v'] != 1 ||
        json['mode'] is! String ||
        (json['mode'] as String).isEmpty ||
        json['targeted'] is! bool ||
        json['lines'] is! List ||
        (score != null &&
            (score is! num || !score.isFinite || score < 0 || score > 1)) ||
        (json['rawAnswer'] != null && json['rawAnswer'] is! String)) {
      throw const FormatException('无效的诗词作答明细');
    }
    return PoemPracticeDetails(
      mode: json['mode'] as String,
      targeted: json['targeted'] as bool,
      score: (score as num?)?.toDouble(),
      rawAnswer: json['rawAnswer'] as String?,
      lines: (json['lines'] as List<dynamic>).map((value) {
        if (value is! Map<String, dynamic>) {
          throw const FormatException('无效的诗句作答');
        }
        return PoemLineResult.fromJson(value);
      }).toList(),
    );
  }
}

class PoemLineResult {
  const PoemLineResult({
    required this.lineIndex,
    required this.lineText,
    required this.expected,
    required this.answer,
    required this.passed,
    this.wholeLine = true,
    this.hintUsed = false,
    this.wrongAttempts = 0,
    this.wrongAnswers = const [],
  });

  final int lineIndex;
  final String lineText;
  final String expected;
  final String answer;
  final bool passed;
  final bool wholeLine;
  final bool hintUsed;
  final int wrongAttempts;
  final List<String> wrongAnswers;

  Map<String, dynamic> toJson() => {
        'lineIndex': lineIndex,
        'lineText': lineText,
        'expected': expected,
        'answer': answer,
        'passed': passed,
        'wholeLine': wholeLine,
        'hintUsed': hintUsed,
        'wrongAttempts': wrongAttempts,
        'wrongAnswers': wrongAnswers,
      };

  factory PoemLineResult.fromJson(Map<String, dynamic> json) {
    if (json['lineIndex'] is! int ||
        (json['lineIndex'] as int) < 0 ||
        json['lineText'] is! String ||
        json['expected'] is! String ||
        json['answer'] is! String ||
        json['passed'] is! bool ||
        json['wholeLine'] is! bool ||
        json['hintUsed'] is! bool ||
        json['wrongAttempts'] is! int ||
        (json['wrongAttempts'] as int) < 0 ||
        json['wrongAnswers'] is! List ||
        !(json['wrongAnswers'] as List<dynamic>)
            .every((value) => value is String)) {
      throw const FormatException('无效的诗句作答');
    }
    return PoemLineResult(
      lineIndex: json['lineIndex'] as int,
      lineText: json['lineText'] as String,
      expected: json['expected'] as String,
      answer: json['answer'] as String,
      passed: json['passed'] as bool,
      wholeLine: json['wholeLine'] as bool,
      hintUsed: json['hintUsed'] as bool,
      wrongAttempts: json['wrongAttempts'] as int,
      wrongAnswers: (json['wrongAnswers'] as List<dynamic>).cast<String>(),
    );
  }
}

/// 所有练习共用非空行编号；保留纯标点行的位置，避免索引移位。
List<String> poemPracticeLines(String content) => content
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList();

String normalizePoemAnswer(String text) =>
    text.replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '');

/// 仅完整逐句听写通过可清除旧错句；部分填空答对不证明整句已掌握。
List<PoemLineResult> unresolvedPoemLines(
  Iterable<PoemPracticeDetails> history,
) {
  final unresolved = <int, PoemLineResult>{};
  for (final details in history) {
    for (final line in details.lines) {
      if (!line.passed || line.hintUsed || line.wrongAttempts > 0) {
        unresolved[line.lineIndex] = line;
      } else if (line.wholeLine && details.mode == 'dictation') {
        unresolved.remove(line.lineIndex);
      }
    }
  }
  return unresolved.values.toList()
    ..sort((a, b) => a.lineIndex.compareTo(b.lineIndex));
}
