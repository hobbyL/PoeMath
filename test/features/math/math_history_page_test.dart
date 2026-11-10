import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/repositories/math_session_repository.dart';
import 'package:poemath/features/math/math_history_page.dart';
import 'package:poemath/features/math/providers/math_providers.dart';

class _Sessions extends Mock implements MathSessionRepository {}

void main() {
  for (final width in [320.0, 600.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('口算历史在宽 $width 字号 $scale 完整显示成绩且按需构建', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = _Sessions();
        when(repo.getAll).thenReturn(
          List.generate(
            1000,
            (i) => MathSession(
              id: '$i',
              profileId: 'default',
              grade: 6,
              problemType: 'mixed',
              totalProblems: 100,
              correctCount: 100,
              durationSeconds: 1234,
              starsEarned: 3,
              semester: '下',
              difficulty: 'hard',
              startedAt: DateTime(2026, 11, 11, 18, 30),
            ),
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [mathSessionRepoProvider.overrideWithValue(repo)],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const MathHistoryPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('100%'), findsWidgets);
        expect(find.text('100/100'), findsWidgets);
        expect(find.text('20分34秒'), findsWidgets);
        expect(find.text('正确率').evaluate().length, lessThan(40));
      });
    }
  }
}
