// lib/core/constants/hive_keys.dart
//
// 层级：core/constants
// 职责：Hive Box 名称常量与 MetaBox key 常量。

class HiveKeys {
  const HiveKeys._();

  // ============ Box 名称 ============

  /// 诗词数据 Box
  static const String poemBox = 'poems';

  /// 作者数据 Box
  static const String authorBox = 'authors';

  /// 公式数据 Box
  static const String formulaBox = 'formulas';

  /// 诗词学习进度 Box
  static const String progressBox = 'poem_progress';

  /// 诗词收藏 Box
  static const String poemFavoriteBox = 'poem_favorites';

  /// 复习调度 Box
  static const String reviewBox = 'review_schedules';

  /// 口算错题 Box
  static const String mistakeBox = 'math_mistakes';

  /// 口算练习会话 Box
  static const String mathSessionBox = 'math_sessions';

  /// 公式收藏 Box
  static const String formulaFavoriteBox = 'formula_favorites';

  /// 成就 Box
  static const String achievementBox = 'achievements';

  /// 打卡 Box
  static const String checkInBox = 'check_ins';

  /// 用户统计 Box
  static const String userStatsBox = 'user_stats';

  /// 挑战记录 Box
  static const String challengeRecordBox = 'challenge_records';

  /// 逐次学习活动事件 Box
  static const String learningActivityBox = 'learning_activities';

  /// LLM 应用题 Box
  static const String llmProblemBox = 'llm_problems';

  /// AI 助手会话 Box
  static const String conversationBox = 'assistant_conversations';

  /// AI 助手消息 Box
  static const String messageBox = 'assistant_messages';

  /// 设置 Box（KV 存储）
  static const String settingsBox = 'settings';

  /// 元数据 Box（data_version 等全局状态）
  static const String metaBox = 'meta';

  // ============ MetaBox Keys ============

  /// 数据版本号（用于判断是否需要重新导入）
  static const String metaDataVersion = 'data_version';

  /// 首次启动标记
  static const String metaFirstLaunch = 'first_launch';

  /// 活跃 profile ID
  static const String metaActiveProfileId = 'active_profile_id';

  /// 错题 key 迁移完成标记
  static const String metaMistakeKeyMigrated = 'mistake_key_migrated';

  /// 「Hive 加密密钥丢失，已重建空数据」标记。
  ///
  /// 由 `HiveEncryptionKeyResolver` 在降级路径写入，UI 读一次并展示
  /// 一次性提示后清除。
  ///
  /// **只登记在 `HiveKeys`，不要登记进 `backup_service.dart` 的
  /// `_settingsValueType`**：这是本机状态，不该随备份迁移 —— 在另一台
  /// 设备上「上次密钥丢失过」是无关信息，甚至会让用户误以为新设备也丢了数据。
  static const String metaHiveKeyRecovered = 'hive_key_recovered';
}
