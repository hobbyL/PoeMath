import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/features/chinese/expression/picture_story_history_page.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';

import '../../../helpers/picture_story_fixture.dart';

void main() {
  for (final count in [500, 2000]) {
    testWidgets('$count 条历史首屏挂载有界，旋转、滚至末尾、详情返回保留位置', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prompt = pictureStoryFixture(id: 'long-history');
      final records = List.generate(
        count,
        (index) => PictureStoryPracticeRecord(
          id: 'record-$index',
          profileId: 'default',
          promptId: prompt.id,
          promptVersion: 1,
          startedAt: DateTime(2026, 11, 8).subtract(Duration(minutes: index)),
          status: 'completed',
          segmentsJson: '[]',
          answerText: '第 $index 条表达。我看见小朋友在草地上放风筝。',
        ),
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => PictureStoryHistoryPage(
              promptId: count == 2000 ? prompt.id : null,
            ),
          ),
          GoRoute(
            path: AppRoutes.pictureStoryRecordDetail,
            builder: (context, state) => Scaffold(
              appBar: AppBar(title: Text(state.pathParameters['id']!)),
              body: const Text('历史详情目的页'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pictureStoryHistoryProvider.overrideWithValue(records),
            pictureStoryPromptHistoryProvider(prompt.id)
                .overrideWithValue(records),
            pictureStoryPromptVersionProvider.overrideWith(
              (ref, key) => prompt,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      int mountedCards() => find.byType(AppTile).evaluate().length;
      expect(mountedCards(), inInclusiveRange(1, 36));
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(5000);
      await tester.pumpAndSettle();
      final visible = find
          .byType(AppTile)
          .evaluate()
          .where((element) {
            final box = element.renderObject as RenderBox;
            final y = box.localToGlobal(Offset.zero).dy;
            return y > kToolbarHeight && y < 600;
          })
          .first
          .widget
          .key;
      tester.view.physicalSize = const Size(1100, 700);
      await tester.pumpAndSettle();
      expect(find.byKey(visible!), findsOneWidget);
      expect(mountedCards(), lessThanOrEqualTo(60));
      final last = find.byKey(
        ValueKey('picture-story-record-record-${count - 1}'),
      );
      for (var i = 0; i < 30 && last.evaluate().isEmpty; i++) {
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
      }
      expect(last, findsOneWidget);
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      final position = scroll.offset;
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(find.text('历史详情目的页'), findsOneWidget);
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(position, 1));
      expect(last, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
