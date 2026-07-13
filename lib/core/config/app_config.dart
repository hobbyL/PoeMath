// lib/core/config/app_config.dart
//
// 层级：core/config
// 职责：编译期注入的应用配置（通过 --dart-define）。

/// 编译期配置常量。
///
/// 构建时通过 `--dart-define=KEY=VALUE` 注入，例如：
/// ```bash
/// flutter build apk --dart-define=UPDATE_CHECK_URL=https://cdn.example.com/latest.json
/// ```
class AppConfig {
  const AppConfig._();

  /// 更新检查 URL，指向 OSS 上的 latest.json。
  static const updateCheckUrl = String.fromEnvironment('UPDATE_CHECK_URL');

  /// 是否配置了更新检查 URL。
  static bool get hasUpdateCheckUrl => updateCheckUrl.trim().isNotEmpty;
}
