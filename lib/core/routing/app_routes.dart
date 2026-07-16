// lib/core/routing/app_routes.dart
//
// 层级：core/routing
// 职责：集中定义全站路由常量与构造器。禁止在业务代码中散写字符串路径。

/// 路由常量表。
class AppRoutes {
  const AppRoutes._();

  // ============ Shell 顶层 tab 路由 ============
  static const String home = '/';
  static const String poemTab = '/poem';
  static const String mathTab = '/math';
  static const String studyHub = '/study';
  static const String profile = '/profile';

  // ============ 诗词模块 ============
  static const String poemDetail = '/poem/detail/:id';
  static const String poemRecite = '/poem/recite/:id';
  static const String poemQuiz = '/poem/quiz/:id';
  static const String poemReview = '/poem/review';
  static const String poemFavorites = '/poem/favorites';

  // ============ 口算模块 ============
  static const String mathPractice = '/math/practice';
  static const String mathMistake = '/math/mistake';
  static const String mathHistory = '/math/history';
  static const String mathSessionDetail = '/math/session';
  static const String mathMistakeDetail = '/math/mistake/detail';

  // ============ 公式 ============
  static const String formulaDetail = '/formula/detail/:id';

  // ============ 启动 & 设置 ============
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String settings = '/profile/settings';
  static const String learningStats = '/profile/stats';
  static const String achievements = '/profile/achievements';
  static const String about = '/profile/about';
  static const String update = '/profile/update';

  // ============ 路径构造器 ============
  static String poemDetailOf(String id) => '/poem/detail/$id';
  static String poemReciteOf(String id) => '/poem/recite/$id';
  static String poemQuizOf(String id) => '/poem/quiz/$id';
  static String formulaDetailOf(String id) => '/formula/detail/$id';
}
