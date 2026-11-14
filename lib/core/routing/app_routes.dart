// lib/core/routing/app_routes.dart
//
// 层级：core/routing
// 职责：集中定义全站路由常量与构造器。禁止在业务代码中散写字符串路径。

/// 路由常量表。
class AppRoutes {
  const AppRoutes._();

  // ============ Shell 顶层 tab 路由 ============
  static const String home = '/';
  static const String chineseTab = '/chinese';
  static const String poemTab = '/poem';
  static const String mathTab = '/math';
  static const String studyHub = '/study';
  static const String profile = '/profile';

  static String chineseSectionOf(String section) =>
      Uri(path: chineseTab, queryParameters: {'section': section}).toString();
  static String mathSectionOf(String section) =>
      Uri(path: mathTab, queryParameters: {'section': section}).toString();

  // ============ 诗词模块 ============
  static const String poemDetail = '/poem/detail/:id';
  static const String poemRecite = '/poem/recite/:id';
  static const String poemQuiz = '/poem/quiz/:id';
  static const String poemReview = '/poem/review';
  static const String poemFavorites = '/poem/favorites';
  static const String poemLearningPath = '/poem/path';
  static const String poemReciteMode = '/poem/recite-mode/:id';
  static const String poemReadAlong = '/poem/read-along/:id';
  static const String poemDictation = '/poem/dictation/:id';

  // ============ 语文教材 ============
  static const String textbookShelf = '/textbook';
  static const String textbookDetail = '/textbook/detail/:id';
  static const String textbookRead = '/textbook/read/:id';
  static const String textbookReview = '/textbook/review/:id';
  static const String textbookContent = '/textbook/content/:id/:section';
  static const String textbookRecognitionPractice =
      '/textbook/recognition/:id/:lesson/practice';
  static const String textbookRecognitionPrepare =
      '/textbook/recognition/:id/:lesson/prepare';
  static const String textbookRecognitionCheck =
      '/textbook/recognition/:id/:lesson/check';
  static const String textbookWriting = '/textbook/writing/:id/:lesson';
  static const String textbookDictation = '/textbook/dictation/:id/:lesson';
  static const String textbookManagement = '/profile/settings/books';
  static const String textbookManageDetail = '/profile/settings/books/:id';
  static const String mathTextbookReview = '/profile/settings/books/:id/math';
  static const String mathTextbookLesson =
      '/profile/settings/books/:id/math/:lesson';
  static const String mathTextbookBook = '/math/textbook/:id';
  static const String mathTextbookStudy = '/math/textbook/:id/lesson/:lesson';
  static const String mathTextbookPractice =
      '/math/textbook/:id/lesson/:lesson/practice';
  static const String mathTextbookHistory = '/math/textbook/:id/history';
  static const String mathTextbookParentHistory =
      '/profile/settings/books/:id/math-history';

  // ============ 看图说话 ==========
  static const String pictureStoryPractice = '/chinese/expression/practice/:id';
  static const String pictureStoryHistory = '/chinese/expression/history';
  static const String pictureStoryRecordDetail =
      '/chinese/expression/records/:id';
  static const String pictureStoryPromptHistory =
      '/chinese/expression/history/:id';
  static const String pictureStoryManagement =
      '/profile/settings/picture-story';
  static const String pictureStoryCreate = '$pictureStoryManagement/new';
  static const String pictureStoryGenerate = '$pictureStoryManagement/generate';
  static const String pictureStoryDetail = '$pictureStoryManagement/detail/:id';
  static const String pictureStoryEdit = '$pictureStoryManagement/edit/:id';

  // ============ 口算模块 ============
  static const String mathPractice = '/math/practice';
  static const String mathChallenge = '/math/challenge';
  static const String mathMistake = '/math/mistake';
  static const String mathHistory = '/math/history';
  static const String mathSessionDetail = '/math/session';
  static const String mathMistakeDetail = '/math/mistake/detail';
  static const String challengeHistory = '/math/challenge/history';

  // ============ 应用题（AI 出题） ============
  static const String wordProblemGenerate = '/word-problem/generate';
  static const String wordProblemPreview = '/word-problem/preview';
  static const String wordProblemLibrary = '/word-problem/library';
  static const String wordProblemPractice = '/word-problem/practice';

  // ============ 公式 ============
  static const String formulaDetail = '/formula/detail/:id';

  // ============ AI 助手 ============
  static const String assistant = '/assistant';

  // ============ 启动 & 设置 ============
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String settings = '/profile/settings';
  static const String parentProtection = '/profile/settings/parent-protection';
  static const String speechRecognitionSettings =
      '/profile/settings/speech-recognition';
  static const String llmSettings = '/profile/settings/llm';
  static const String imageGenerationSettings =
      '/profile/settings/image-generation';
  static const String learningStats = '/profile/stats';
  static const String learningCalendar = '/profile/calendar';
  static const String achievements = '/profile/achievements';
  static const String about = '/profile/about';
  static const String update = '/profile/update';
  static const String weeklyReport = '/profile/weekly-report';

  // ============ 路径构造器 ============
  static String poemDetailOf(String id) => '/poem/detail/$id';
  static String poemReciteOf(String id) => '/poem/recite/$id';
  static String poemQuizOf(String id) => '/poem/quiz/$id';
  static String poemReciteModeOf(String id) => '/poem/recite-mode/$id';
  static String poemReadAlongOf(String id) => '/poem/read-along/$id';
  static String poemDictationOf(String id) => '/poem/dictation/$id';
  static String formulaDetailOf(String id) => '/formula/detail/$id';
  static String textbookDetailOf(String id) => '/textbook/detail/$id';
  static String textbookReadOf(String id) => '/textbook/read/$id';
  static String textbookReviewOf(String id) => '/textbook/review/$id';
  static String mathTextbookReviewOf(String id) =>
      '/profile/settings/books/$id/math';
  static String mathTextbookLessonOf(String id, String lesson) =>
      '/profile/settings/books/$id/math/${Uri.encodeComponent(lesson)}';
  static String mathTextbookBookOf(String id) => '/math/textbook/$id';
  static String mathTextbookStudyOf(String id, String lesson) =>
      '/math/textbook/$id/lesson/${Uri.encodeComponent(lesson)}';
  static String mathTextbookPracticeOf(
    String id,
    String lesson, {
    String? planId,
  }) => Uri(
    path: '/math/textbook/$id/lesson/$lesson/practice',
    queryParameters: planId == null ? null : {'plan': planId},
  ).toString();
  static String mathTextbookHistoryOf(String id, {bool parent = false}) =>
      parent
      ? '/profile/settings/books/$id/math-history'
      : '/math/textbook/$id/history';
  static String textbookRecognitionOf(
    String id,
    String lesson,
    String mode, {
    String? targetId,
  }) {
    if (!['practice', 'prepare', 'check'].contains(mode)) {
      throw ArgumentError.value(mode, 'mode');
    }
    final path =
        '/textbook/recognition/${Uri.encodeComponent(id)}/${Uri.encodeComponent(lesson)}/$mode';
    return targetId == null
        ? path
        : '$path?${Uri(queryParameters: {'target': targetId}).query}';
  }

  static String textbookWritingOf(String id, String lesson, String targetId) =>
      Uri(
        path:
            '/textbook/writing/${Uri.encodeComponent(id)}'
            '/${Uri.encodeComponent(lesson)}',
        queryParameters: {'target': targetId},
      ).toString();

  static String textbookDictationOf(String id, String lesson) =>
      '/textbook/dictation/${Uri.encodeComponent(id)}'
      '/${Uri.encodeComponent(lesson)}';

  static String textbookContentOf(String id, String section, List<int> pages) =>
      Uri(
        path: '/textbook/content/$id/$section',
        queryParameters: {'pages': pages.join(',')},
      ).toString();
  static String textbookManageDetailOf(String id) =>
      '/profile/settings/books/$id';
  static String pictureStoryPracticeOf(String id) =>
      '/chinese/expression/practice/${Uri.encodeComponent(id)}';
  static String pictureStoryPromptHistoryOf(String id) =>
      '/chinese/expression/history/${Uri.encodeComponent(id)}';
  static String pictureStoryRecordDetailOf(String id) =>
      '/chinese/expression/records/${Uri.encodeComponent(id)}';
  static String pictureStoryDetailOf(String id) =>
      '$pictureStoryManagement/detail/${Uri.encodeComponent(id)}';
  static String pictureStoryEditOf(String id) =>
      '$pictureStoryManagement/edit/${Uri.encodeComponent(id)}';
}
