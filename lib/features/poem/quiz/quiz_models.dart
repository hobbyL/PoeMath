// lib/features/poem/quiz/quiz_models.dart
//
// 诗词测试题目模型。纯会话模型，不持久化。

/// 测试题型。
enum QuizType {
  fillBlank('填空测试'),
  multipleChoice('选择题'),
  chooseAuthor('选作者'),
  chooseDynasty('选朝代');

  const QuizType(this.label);
  final String label;

  /// 是否为选择类题型（4 选 1）。
  bool get isChoice =>
      this == multipleChoice || this == chooseAuthor || this == chooseDynasty;
}

/// 一道测试题。
class QuizQuestion {
  const QuizQuestion({
    required this.type,
    required this.contextLine,
    required this.promptLine,
    required this.correctAnswer,
    this.options,
  });

  /// 题型。
  final QuizType type;

  /// 上下文提示（上一句）。
  final String contextLine;

  /// 题干（填空题带 ____ 的行；选择题为完整上句）。
  final String promptLine;

  /// 正确答案。
  final String correctAnswer;

  /// 选择题选项（含正确答案，已打乱），填空题为 null。
  final List<String>? options;
}

/// 一次测试会话。
class QuizSession {
  QuizSession({
    required this.poemId,
    required this.type,
    required this.questions,
  }) : userAnswers = List.filled(questions.length, null),
       _stopwatch = Stopwatch()..start();

  final String poemId;
  final QuizType type;
  final List<QuizQuestion> questions;

  /// 用户作答记录，null 表示未作答。
  final List<String?> userAnswers;

  final Stopwatch _stopwatch;

  /// 当前题目索引。
  int currentIndex = 0;

  /// 是否已完成全部题目。
  bool get isFinished => currentIndex >= questions.length;

  /// 当前题目。
  QuizQuestion get currentQuestion => questions[currentIndex];

  /// 正确题数。
  int get correctCount {
    var count = 0;
    for (var i = 0; i < questions.length; i++) {
      final answer = userAnswers[i];
      if (answer != null && _isCorrect(i)) count++;
    }
    return count;
  }

  /// 正确率。
  double get accuracy =>
      questions.isEmpty ? 0.0 : correctCount / questions.length;

  /// 是否通过（正确率 ≥ 80%）。
  bool get isPassed => accuracy >= 0.8;

  /// 用时（秒）。
  int get elapsedSeconds => _stopwatch.elapsed.inSeconds;

  /// 停止计时。
  void stop() => _stopwatch.stop();

  /// 提交当前题答案。
  void submitAnswer(String answer) {
    if (isFinished) return;
    userAnswers[currentIndex] = answer;
  }

  /// 当前题是否回答正确。
  bool isCurrentCorrect() => _isCorrect(currentIndex);

  /// 前进到下一题。
  void advance() {
    if (currentIndex < questions.length) {
      currentIndex++;
    }
    if (isFinished) stop();
  }

  bool _isCorrect(int index) {
    final answer = userAnswers[index];
    if (answer == null) return false;
    final correct = questions[index].correctAnswer;
    return _normalize(answer) == _normalize(correct);
  }

  /// 去标点、空格后比较。
  static String _normalize(String s) {
    return s
        .replaceAll(RegExp('[\\s\\p{P}]', unicode: true), '')
        .trim();
  }
}
