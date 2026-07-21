import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/speech/hybrid_speech_recognition_service.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/poem/poem_detail_page.dart';
import 'package:poemath/features/poem/poem_read_along_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

class _MockTtsService extends Mock implements TtsService {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockSpeechRecognitionService extends Mock
    implements SpeechRecognitionService {}

const _poemId = 'tts-test-poem';

final _poem = Poem(
  id: _poemId,
  title: '静夜思',
  author: '李白',
  dynasty: '唐',
  content: '床前明月光，\n疑是地上霜。',
  pinyin: '',
  layer: 'core',
);

void main() {
  late _MockTtsService tts;
  late _MockSpeechRecognitionService speech;

  setUp(() {
    tts = _MockTtsService();
    speech = _MockSpeechRecognitionService();
    when(() => tts.stop()).thenAnswer((_) async {});
    when(() => speech.initialize()).thenAnswer((_) async {});
    when(() => speech.cancel()).thenAnswer((_) async {});
  });

  testWidgets('诗词详情朗读失败后恢复朗读按钮并提示', (tester) async {
    final settings = _MockSettingsRepository();
    when(() => settings.pinyinVisible).thenReturn(true);
    when(
      () => tts.speakLines(
        any<List<String>>(),
        onLineStart: any(named: 'onLineStart'),
      ),
    ).thenThrow(const TtsException('引擎不可用'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          ttsServiceProvider.overrideWithValue(tts),
          poemByIdProvider(_poemId).overrideWith((ref) => _poem),
          isFavoriteProvider(_poemId).overrideWith((ref) => false),
          poemProgressProvider(_poemId).overrideWith((ref) => null),
        ],
        child: const MaterialApp(
          home: PoemDetailPage(poemId: _poemId),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('朗读全文'));
    await tester.pump();

    expect(find.byTooltip('朗读全文'), findsOneWidget);
    expect(find.byTooltip('停止朗读'), findsNothing);
    expect(find.text('朗读失败，请检查系统语音服务后重试'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('跟读范读失败后恢复听一听按钮并提示', (tester) async {
    when(() => tts.speak(any<String>())).thenThrow(const TtsException('引擎不可用'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ttsServiceProvider.overrideWithValue(tts),
          poemByIdProvider(_poemId).overrideWith((ref) => _poem),
        ],
        child: MaterialApp(
          home: PoemReadAlongPage(
            poemId: _poemId,
            speechRecognitionService: speech,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('听一听'));
    await tester.pump();

    expect(find.text('听一听'), findsOneWidget);
    expect(find.text('停止播放'), findsNothing);
    expect(find.text('范读失败，请检查系统语音服务后重试'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('开始跟读前停止范读失败时保持空闲并提示', (tester) async {
    when(() => tts.stop()).thenAnswer(
      (_) async => throw const TtsException('停止失败'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ttsServiceProvider.overrideWithValue(tts),
          poemByIdProvider(_poemId).overrideWith((ref) => _poem),
        ],
        child: MaterialApp(
          home: PoemReadAlongPage(
            poemId: _poemId,
            speechRecognitionService: speech,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('读一读'));
    await tester.pump();

    expect(find.text('读一读'), findsOneWidget);
    expect(find.text('无法开始跟读，请稍后重试'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
