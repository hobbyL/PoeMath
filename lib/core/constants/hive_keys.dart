// lib/core/constants/hive_keys.dart
//
// 层级：core/constants
// 职责：Hive Box 名称常量。Phase 0 只声明占位，Phase 2 填内容。

class HiveKeys {
  const HiveKeys._();

  // ============ Phase 2 会启用的 Box 名 ============
  /// 用户配置 / 首选项 Box
  static const String settingsBox = 'settings';

  /// 诗词内容缓存 Box
  static const String poemBox = 'poem';

  /// 收藏 Box
  static const String favoriteBox = 'favorite';

  /// 学习进度 Box
  static const String progressBox = 'progress';

  /// 错题本 Box
  static const String mistakeBox = 'mistake';
}
