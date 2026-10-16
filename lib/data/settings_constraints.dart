import 'package:poemath/domain/math_entry_kind.dart';

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
      // 口算页一级入口集合：逗号分隔的 MathEntryKind.name。
      //
      // 「至少保留一类」是跨项约束，用单 key 存整个集合才能在此单点校验；
      // 拆成多个 bool key 就只能在 UI 层拦，备份导入会绕过。未知 name 由
      // parseMathEntryKinds 丢弃，故此处接受含未知项的串（前向兼容），
      // 但要求**至少有一个已知项**且不含空项（空串/连续逗号属于脏数据）。
      'math_entry_kinds' => switch (value) {
          final String raw =>
            raw.split(',').every((part) => part.trim().isNotEmpty) &&
                parseMathEntryKinds(raw).isNotEmpty,
          _ => false,
        },
      _ => true,
    };
  }
}
