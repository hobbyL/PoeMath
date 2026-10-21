/// 答对/答错反馈的成对声音；稳定 ID 用于设置与备份。
enum AnswerFeedbackSound {
  classic(
    'classic',
    '经典音效',
    '清脆提示音，区分答对与答错',
    'sounds/correct.wav',
    'sounds/wrong.wav',
  ),
  childVoice(
    'child_voice',
    '童趣语音',
    '可爱童声说“答对咯”“答错啦”',
    'sounds/child_correct.mp3',
    'sounds/child_wrong.mp3',
  );

  const AnswerFeedbackSound(
    this.id,
    this.label,
    this.description,
    this.correctAssetPath,
    this.wrongAssetPath,
  );

  final String id;
  final String label;
  final String description;
  final String correctAssetPath;
  final String wrongAssetPath;

  String assetPath({required bool correct}) =>
      correct ? correctAssetPath : wrongAssetPath;

  static const defaultSound = AnswerFeedbackSound.classic;
  static const settingsKey = 'answer_feedback_sound';

  static AnswerFeedbackSound? fromId(Object? id) =>
      values.where((sound) => sound.id == id).firstOrNull;
}
