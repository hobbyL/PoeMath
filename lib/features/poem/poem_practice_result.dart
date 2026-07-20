// lib/features/poem/poem_practice_result.dart
//
// 诗词练习页面与复习调度页面之间的结果契约。

enum PoemPracticeResult {
  recitationCompleted,
  quizPassed,
  quizFailed,
  cancelled;

  bool get completesReview => this == recitationCompleted || this == quizPassed;
}
