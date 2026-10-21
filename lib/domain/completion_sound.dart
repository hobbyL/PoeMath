/// 用户可选的练习完成提示音；稳定 ID 用于设置存储与备份。
enum CompletionSound {
  arcade('arcade', '经典电玩', '像素游戏音色，轻快上行', 'sounds/completion_arcade.wav'),
  pizzicato(
    'pizzicato',
    '轻快拨弦',
    '短促拨弦，清脆收尾',
    'sounds/completion_pizzicato.wav',
  ),
  steelDrum(
    'steel_drum',
    '明亮钢鼓',
    '明亮钢鼓，自然尾音',
    'sounds/completion_steel_drum.wav',
  ),
  ensemble(
    'ensemble',
    '过关小合奏',
    '上行旋律与和声，庆祝过关',
    'sounds/completion_ensemble.wav',
  );

  const CompletionSound(this.id, this.label, this.description, this.assetPath);

  final String id;
  final String label;
  final String description;
  final String assetPath;

  static const defaultSound = CompletionSound.ensemble;
  static const settingsKey = 'completion_sound';

  static CompletionSound? fromId(Object? id) =>
      values.where((sound) => sound.id == id).firstOrNull;
}
