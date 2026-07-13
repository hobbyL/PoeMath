// lib/core/routing/app_routes.dart
//
// 层级：core/routing
// 职责：集中定义全站路由常量与构造器。禁止在业务代码中散写字符串路径。

/// 路由常量表。Phase 0 只挂接前 5 个 Shell 子路由 + Splash；
/// 诗词/口算/公式的详细路由字符串已声明，Phase 4-6 逐步绑定 builder。
class AppRoutes {
  const AppRoutes._();

  // ============ Shell 顶层 tab 路由 ============
  static const String home = '/';
  static const String poemTab = '/poem';
  static const String mathTab = '/math';
  static const String studyHub = '/study';
  static const String profile = '/profile';

  // ============ 诗词模块（Phase 4） ============
  static const String poemList = '/poem/list';
  static const String poemDetail = '/poem/detail/:id';
  static const String poemRecite = '/poem/recite/:id';
  static const String poemQuiz = '/poem/quiz/:id';
  static const String poemReview = '/poem/review';

  // ============ 口算模块（Phase 5） ============
  static const String mathHub = '/math/hub';
  static const String mathPractice = '/math/practice';
  static const String mathMistake = '/math/mistake';

  // ============ 公式（Phase 6） ============
  static const String formulaList = '/formula/list';
  static const String formulaDetail = '/formula/detail/:id';

  // ============ 启动 & 设置 ============
  static const String splash = '/splash';
  static const String settings = '/profile/settings';
  static const String update = '/profile/update';

  // ============ 路径构造器 ============
  static String poemDetailOf(String id) => '/poem/detail/$id';
  static String poemReciteOf(String id) => '/poem/recite/$id';
  static String poemQuizOf(String id) => '/poem/quiz/$id';
  static String formulaDetailOf(String id) => '/formula/detail/$id';
}
