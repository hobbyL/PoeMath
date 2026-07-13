// lib/core/routing/app_router.dart
//
// 层级：core/routing
// 职责：基于 go_router 构造 Navigator 2.0 语义的应用路由器；
//       通过 Provider 暴露以便 ConsumerWidget 消费。
// 依赖：go_router / AppRoutes / MainShell / SplashPage / 各 Tab 页面。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/config/app_config.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/update/android_update_installer.dart';
import 'package:poemath/core/services/update/update_client.dart';
import 'package:poemath/features/formula/formula_detail_page.dart';
import 'package:poemath/features/formula/study_hub_page.dart';
import 'package:poemath/features/home/home_page.dart';
import 'package:poemath/features/math/math_mistake_page.dart';
import 'package:poemath/features/math/math_practice_page.dart';
import 'package:poemath/features/math/math_tab_page.dart';
import 'package:poemath/features/poem/poem_detail_page.dart';
import 'package:poemath/features/poem/poem_quiz_page.dart';
import 'package:poemath/features/poem/poem_recite_page.dart';
import 'package:poemath/features/poem/poem_review_page.dart';
import 'package:poemath/features/poem/quiz/quiz_models.dart';
import 'package:poemath/features/poem/poem_tab_page.dart';
import 'package:poemath/features/profile/profile_page.dart';
import 'package:poemath/features/profile/settings_page.dart';
import 'package:poemath/features/profile/update_page.dart';
import 'package:poemath/features/shell/main_shell.dart';
import 'package:poemath/features/shell/splash_page.dart';

/// `Provider<GoRouter>`：整个应用共享一份 GoRouter 实例。
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashPage(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const HomePage(),
          ),
          GoRoute(
            path: AppRoutes.poemTab,
            builder: (context, state) => const PoemTabPage(),
          ),
          GoRoute(
            path: AppRoutes.studyHub,
            builder: (context, state) => const StudyHubPage(),
          ),
          GoRoute(
            path: AppRoutes.mathTab,
            builder: (context, state) => const MathTabPage(),
          ),
          GoRoute(
            path: AppRoutes.profile,
            builder: (context, state) => const ProfilePage(),
          ),
        ],
      ),
      // ============ 诗词详情（非 Shell 子路由，全屏） ============
      GoRoute(
        path: AppRoutes.poemDetail,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return PoemDetailPage(poemId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.poemRecite,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return PoemRecitePage(poemId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.poemQuiz,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final typeStr = state.uri.queryParameters['type'] ?? 'fill';
          final quizType = typeStr == 'choice'
              ? QuizType.multipleChoice
              : QuizType.fillBlank;
          return PoemQuizPage(poemId: id, quizType: quizType);
        },
      ),
      GoRoute(
        path: AppRoutes.poemReview,
        builder: (context, state) => const PoemReviewPage(),
      ),
      // ============ 口算练习（非 Shell 子路由，全屏） ============
      GoRoute(
        path: AppRoutes.mathPractice,
        builder: (context, state) => const MathPracticePage(),
      ),
      GoRoute(
        path: AppRoutes.mathMistake,
        builder: (context, state) => const MathMistakePage(),
      ),
      // ============ 公式详情（非 Shell 子路由，全屏） ============
      GoRoute(
        path: AppRoutes.formulaDetail,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return FormulaDetailPage(formulaId: id);
        },
      ),
      // ============ 设置（非 Shell 子路由，全屏） ============
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsPage(),
      ),
      // ============ 检查更新（非 Shell 子路由，全屏） ============
      GoRoute(
        path: AppRoutes.update,
        builder: (context, state) => UpdatePage(
          updateClient: UpdateClient(updateUrl: AppConfig.updateCheckUrl),
          updateInstaller: AndroidUpdateInstaller(),
        ),
      ),
    ],
  );
});
