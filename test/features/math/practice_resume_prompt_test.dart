import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/features/math/math_practice_page.dart';
import 'package:poemath/features/math/word_problem/word_problem_practice_page.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  for (final kind in ['math', 'word']) {
    testWidgets('$kind 续练选择框按系统返回时取消进入，原草稿完整保留', (tester) async {
      final drafts = PracticeDraftRepository();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () => context.push('/practice'),
                child: const Text('开始练习'),
              ),
            ),
          ),
          GoRoute(
            path: '/practice',
            builder: (_, __) => kind == 'math'
                ? const MathPracticePage()
                : const WordProblemPracticePage(problems: []),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.runAsync(() async {
        await drafts.save(kind, {
          'sessionId': 'preserve-on-back',
          'input': '42',
          'problems': <Object>[],
          'records': <Object>[],
        });
        await tester.pumpWidget(
          ProviderScope(child: MaterialApp.router(routerConfig: router)),
        );
      });
      final original = drafts.get(kind);
      await tester.runAsync(() async {
        await tester.tap(find.text('开始练习'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('继续上次'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.binding.handlePopRoute();
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(drafts.get(kind), original);
      expect(HiveBoxes.mathSessions.isEmpty, isTrue);
      expect(HiveBoxes.userStats.isEmpty, isTrue);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
    });
  }
}
