import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/features/math/math_mistake_detail_page.dart';
import 'package:poemath/features/math/math_session_detail_page.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  late MathSession session;
  setUp(() async {
    await setUpHiveForTesting();
    session = MathSession(
      id: 'current-session',
      profileId: 'default',
      grade: 2,
      semester: '上',
      problemType: 'mixed',
      totalProblems: 4,
      correctCount: 2,
      problemsJson: jsonEncode([
        for (var i = 1; i <= 4; i++)
          ProblemRecord(
            problemText: '$i + $i = ?',
            answerText: '${i * 2}',
            userAnswer: i.isOdd ? '${i * 2}' : '0',
            isCorrect: i.isOdd,
          ).toJson(),
      ]),
    );
    final repo = MathMistakeRepository();
    await repo.recordWrong(
      problemText: '2 + 2 = ?',
      correctAnswer: '4',
      userAnswer: '0',
      problemType: 'addition',
      grade: 2,
    );
    await repo.add(
      MathMistake(
        id: 'current-session_3',
        profileId: 'default',
        problemText: '4 + 4 = ?',
        correctAnswer: '8',
        userAnswer: '0',
        problemType: 'addition',
        grade: 2,
      ),
    );
    await repo.recordWrong(
      problemText: '9 + 9 = ?',
      correctAnswer: '18',
      userAnswer: '0',
      problemType: 'addition',
      grade: 2,
    );
  });
  tearDown(tearDownHiveForTesting);

  testWidgets('真实路由只显示本轮错题，原题号可打开新旧错题记录', (tester) async {
    final router = createAppRouter(
      initialLocation: AppRoutes.mathSessionDetail,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    router.go('${AppRoutes.mathSessionDetail}?mistakesOnly=1', extra: session);
    await tester.pumpAndSettle();

    expect(find.text('1 + 1 = ?'), findsNothing);
    expect(find.text('3 + 3 = ?'), findsNothing);
    expect(find.text('9 + 9 = ?'), findsNothing);
    expect(find.text('2 + 2 = ?'), findsOneWidget);
    expect(find.text('4 + 4 = ?'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);

    await tester.tap(find.text('4 + 4 = ?'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MathMistakeDetailPage>(find.byType(MathMistakeDetailPage))
          .mistakeId,
      'current-session_3',
    );
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 + 2 = ?'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MathMistakeDetailPage>(find.byType(MathMistakeDetailPage))
          .mistakeId,
      MathMistakeRepository.problemKey(
        problemText: '2 + 2 = ?',
        correctAnswer: '4',
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('历史默认全部作答，窄屏大字可以切换筛选', (tester) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: MathSessionDetailPage(session: session),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 + 1 = ?'), findsOneWidget);
    await tester.tap(find.text('本轮错题（2）'));
    await tester.pumpAndSettle();
    expect(find.text('1 + 1 = ?'), findsNothing);
    expect(find.text('2 + 2 = ?'), findsOneWidget);
    await tester.tap(find.text('全部作答'));
    await tester.pumpAndSettle();
    expect(find.text('1 + 1 = ?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('旧记录无明细与本轮全对分别提示', (tester) async {
    session.problemsJson = null;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MathSessionDetailPage(
            session: session,
            initiallyMistakesOnly: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('该练习无题目详情记录'), findsOneWidget);
    session.problemsJson = jsonEncode([
      const ProblemRecord(
        problemText: '1 + 1 = ?',
        answerText: '2',
        userAnswer: '2',
        isCorrect: true,
      ).toJson(),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MathSessionDetailPage(
            session: session,
            initiallyMistakesOnly: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('本轮没有错题'), findsOneWidget);
  });
}
