// lib/core/constants/app_constants.dart
//
// 层级：core/constants
// 职责：品牌名、版本号、slogan 等静态常量。

class AppConstants {
  const AppConstants._();

  /// 产品名（用户可见）
  static const String appName = '韵算';

  /// 英文短名
  static const String appNameEn = 'PoeMath';

  /// 版本号（build 时可覆盖）
  static const String appVersion = '0.1.0';

  /// 数据版本号（修改后首次启动会重新导入 asset 数据）
  /// 1.1.0: 作者库/公式库扩充，extended+explore 去模板赏析
  /// 1.2.0: extended 扩至 400；作者全覆盖；explore 重分层
  static const String dataVersion = '1.2.0';

  /// slogan
  static const String slogan = '读诗、算数，慢慢来';

  /// Splash 最短停留时长（毫秒）— 仅在跳过导入时生效
  static const int splashMinDurationMs = 300;
}
