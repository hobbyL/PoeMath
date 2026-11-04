import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/features/home/textbook_resume_section.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/textbook_fixture.dart';

void main() {
  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
  });
  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForTesting();
  });

  testWidgets('续读随页码、档案和删除更新，缺文件进入原课本详情', (tester) async {
    final book = textbookFixture();
    final other = textbookFixture(
      id: List.filled(64, 'b').join(),
      title: '另一课本',
    );
    final repo = TextbookRepository();
    await tester.runAsync(() async {
      await repo.addIfAbsent(book);
      await repo.addIfAbsent(other);
      await repo.markOpened('child', other.pdfSha256);
    });
    String? opened;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
            body: SingleChildScrollView(child: TextbookResumeSection()),
          ),
        ),
        GoRoute(
          path: AppRoutes.textbookDetail,
          builder: (_, state) {
            opened = state.pathParameters['id'];
            return const Scaffold(body: Text('原课本详情'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          textbookPathProvider(book.pdfSha256)
              .overrideWith((ref) async => null),
          textbookPathProvider(other.pdfSha256)
              .overrideWith((ref) async => '/other.pdf'),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('继续读'), findsNothing);
    await tester.runAsync(() async {
      await repo.markOpened('default', book.pdfSha256);
      await repo.savePage('default', book, 2);
    });
    await tester.pumpAndSettle();
    expect(find.text('继续读《${book.title}》'), findsOneWidget);
    expect(find.textContaining('PDF 第 2 / 3 页'), findsOneWidget);
    expect(find.textContaining('课本文件缺失'), findsOneWidget);
    await tester.tap(find.text('继续读《${book.title}》'));
    await tester.pumpAndSettle();
    expect(opened, book.pdfSha256);
    router.pop();
    await tester.pumpAndSettle();
    ProfileScope.switchTo('child');
    await tester.pumpAndSettle();
    expect(find.text('继续读《另一课本》'), findsOneWidget);
    expect(find.textContaining('PDF 第 1 / 3 页'), findsOneWidget);
    await tester.runAsync(() => repo.delete(other.pdfSha256));
    await tester.pumpAndSettle();
    expect(find.textContaining('继续读'), findsNothing);
    ProfileScope.reset();
    await tester.pumpAndSettle();
    expect(find.text('继续读《${book.title}》'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await drainHiveWritesForTesting(tester);
  });

  testWidgets('损坏记录显示重试，原值保留', (tester) async {
    const key = '${TextbookRepository.recentKeyPrefix}default';
    await tester.runAsync(() => HiveBoxes.settings.put(key, 42));
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: TextbookResumeSection())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('最近阅读暂时无法读取'), findsOneWidget);
    expect(HiveBoxes.settings.get(key), 42);
    await tester.runAsync(() => HiveBoxes.settings.delete(key));
    await tester.pumpAndSettle();
    expect(find.text('最近阅读暂时无法读取'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
