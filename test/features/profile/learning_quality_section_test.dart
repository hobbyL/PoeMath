import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/domain/learning_quality.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/features/math/math_practice_request.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/profile/providers/learning_quality_providers.dart';
import 'package:poemath/features/profile/widgets/learning_quality_section.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

void main() {
  testWidgets('报告显示分子分母、小样本和历史未知；建议一次性专项不改模式偏好', (tester) async {
    const report = LearningQualityReport(
        skills: [
          SkillQuality(
              skill: MathSkill.additionCarry,
              grade: 4,
              semester: '下',
              difficulty: DifficultyLevel.medium,
              total: 5,
              correct: 2,
              previousTotal: 5,
              previousCorrect: 4,),
          SkillQuality(
              skill: MathSkill.subtractionBorrow,
              grade: 4,
              semester: '下',
              difficulty: DifficultyLevel.medium,
              total: 2,
              correct: 1,
              previousTotal: 0,
              previousCorrect: 0,),
        ],
        unknownMathTotal: 8,
        classifiedMathTotal: 7,
        newPoems: 1,
        poemPracticeCount: 3,
        completedReviews: 1,
        poemHistoryUnknown: true,
        newlyMasteredPoems: 2,
        masteryHistoryUnknown: true,
        poemModes: [
          PoemModeQuality(
              mode: LearningActivityType.poemQuiz,
              practices: 1,
              successful: 8,
              total: 10,),
          PoemModeQuality(
              mode: LearningActivityType.poemDictation,
              practices: 1,
              successful: 2,
              total: 4,),
          PoemModeQuality(
              mode: LearningActivityType.readAlong,
              practices: 1,
              successful: 3,
              total: 4,),
          PoemModeQuality(
              mode: LearningActivityType.poemRecitation,
              practices: 1,
              successful: 0,
              total: 0,),
        ],);
    final container = ProviderContainer(overrides: [
      learningQualityProvider(7).overrideWithValue(report),
      mathPracticeModeProvider.overrideWith((ref) => ProblemMode.compare),
    ],);
    addTearDown(container.dispose);
    MathPracticeRequest? captured;
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
                  body: SingleChildScrollView(
                child: LearningQualitySection(days: 7),
              ),),),
      GoRoute(
          path: AppRoutes.mathPractice,
          builder: (_, __) {
            captured ??= container.read(nextMathPracticeRequestProvider);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              container
                  .read(nextMathPracticeRequestProvider.notifier)
                  .consume();
            });
            return const Scaffold(body: Text('专项练习'));
          },),
    ],);
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,),
        ),),);
    await tester.pumpAndSettle();
    expect(find.textContaining('2/5 题正确'), findsOneWidget);
    expect(find.textContaining('历史或挑战未分类 8 题'), findsOneWidget);
    expect(find.textContaining('小样本（少于 5 题）'), findsOneWidget);
    expect(find.text('新增掌握 2 首'), findsOneWidget);
    expect(find.textContaining('测试 8/10 题正确'), findsOneWidget);
    expect(find.textContaining('听写 2/4 句通过'), findsOneWidget);
    expect(find.textContaining('跟读 3/4 句内容匹配达标'), findsOneWidget);
    expect(find.textContaining('背诵完成 1 次'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final action = find.text('进位加法 · 再练 5 题');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(captured?.skillId, 'addition_carry');
    expect(captured?.count, 5);
    expect(captured?.grade, 4);
    expect(captured?.semester, '下');
    expect(container.read(mathPracticeModeProvider), ProblemMode.compare);
    expect(container.read(nextMathPracticeRequestProvider), isNull);
  });
}
