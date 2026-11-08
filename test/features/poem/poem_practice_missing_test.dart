import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/poem/poem_dictation_page.dart';
import 'package:poemath/features/poem/poem_recite_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

import '../../helpers/hive_test_helper.dart';

class _Tts extends Mock implements TtsService {}

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);
  for (final recite in [true, false]) {
    for (final missing in [true, false]) {
      testWidgets('${recite ? '背诵' : '听写'} ${missing ? '缺失' : '空正文'}停止加载并能返回', (
        tester,
      ) async {
        final tts = _Tts();
        when(() => tts.stop()).thenAnswer((_) async {});
        when(() => tts.currentSessionId).thenReturn(0);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ttsServiceProvider.overrideWithValue(tts),
              poemByIdProvider('missing').overrideWithValue(
                missing
                    ? null
                    : Poem(
                        id: 'missing',
                        title: '空正文',
                        author: '',
                        dynasty: '',
                        content: ' \n ',
                        pinyin: '',
                        layer: 'core',
                        grade: 1,
                      ),
              ),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => recite
                            ? const PoemRecitePage(poemId: 'missing')
                            : const PoemDictationPage(poemId: 'missing'),
                      ),
                    ),
                    child: const Text('进入练习'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('进入练习'));
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text(missing ? '未找到这首诗词' : '暂无可练习的诗句'), findsOneWidget);
        await tester.tap(find.text('返回选择诗词'));
        await tester.pumpAndSettle();
        expect(find.text('进入练习'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
