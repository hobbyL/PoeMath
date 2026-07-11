// lib/core/constants/app_constants.dart
//
// 层级：core/constants
// 职责：品牌名、版本号、slogan 等静态常量。

class AppConstants {
  const AppConstants._();

  /// 产品名（用户可见）
  static const String appName = '诗算宝';

  /// 英文短名
  static const String appNameEn = 'PoeMath';

  /// 版本号（build 时可覆盖）
  static const String appVersion = '0.1.0';

  /// slogan
  static const String slogan = '读诗、算数，慢慢来';

  /// Splash 停留时长（毫秒）
  static const int splashDurationMs = 300;
}
