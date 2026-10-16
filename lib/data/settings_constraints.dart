/// UI、备份导入与历史读取共用的普通设置范围。
class SettingsConstraints {
  const SettingsConstraints._();

  static bool accepts(String key, Object value) {
    final range = switch (key) {
      'selected_grade' => (1, 6),
      'math_batch_size' => (1, 100),
      'daily_poem_goal' => (1, 10),
      'daily_math_goal' => (1, 100),
      'reminder_hour' => (0, 23),
      'reminder_minute' => (0, 59),
      _ => null,
    };
    if (range != null) {
      return value is int && value >= range.$1 && value <= range.$2;
    }
    return switch (key) {
      'tts_speed' =>
        value is num && value.isFinite && value >= 0.1 && value <= 1.0,
      'theme_mode' => const ['system', 'light', 'dark'].contains(value),
      'active_subject' => const ['poem', 'math'].contains(value),
      'selected_semester' => const ['上', '下'].contains(value),
      'math_difficulty' => const ['easy', 'medium', 'hard'].contains(value),
      'math_practice_mode' => const [
          'findResult',
          'findMissing',
          'compare',
          'vertical',
          'chain',
          'withBrackets',
        ].contains(value),
      _ => true,
    };
  }
}
