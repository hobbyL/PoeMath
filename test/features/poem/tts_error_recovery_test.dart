import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_speech_recognition_service.dart';
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

const _verifiedSettings = SpeechRecognitionSettingsState(
  hasCredentials: true,
  isVerified: true,
);

void main() {
  late _MockTtsService tts;
  late _MockSpeechRecognitionService speech;

  setUp(() {
    tts = _MockTtsService();
    speech = _MockSpeechRecognitionService();
    when(() => tts.stop()).thenAnswer((_) async {});
    // 回调携带会话身份后页面读取该令牌判断回调归属（任务 R3）。
    when(() => tts.currentSessionId).thenReturn(1);
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
        onReady: any(named: 'onReady'),
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
    await tester.pump(const Duration(milliseconds: 400));

    // 朗读入口已改为正文区域点击（AppBar 播放按钮已移除）。
    await tester.tap(find.text('床前明月光，'));
    await tester.pump();

    // 失败路径：遮罩解除 + SnackBar 提示（R2：TtsException 文案透传）。
    expect(find.text('语音合成中…'), findsNothing);
    expect(find.text('朗读失败：引擎不可用'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('跟读范读失败后恢复听一听按钮并提示', (tester) async {
    when(() => tts.speak(any<String>())).thenThrow(const TtsException('引擎不可用'));
    final settings = _MockSettingsRepository();
    when(() => settings.loadSpeechRecognitionSettings())
        .thenAnswer((_) async => _verifiedSettings);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
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
    // R2：TtsException 文案透传（范读失败：引擎不可用）。
    expect(find.text('范读失败：引擎不可用'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('跟读范读云端全跳句失败：SnackBar 透传云端文案而非系统引擎误导（AC2）', (tester) async {
    // 云端全跳句（合成成功但播放均失败）时服务上抛的面向用户文案；
    // 页面必须透传——显示「请检查系统语音服务」会把云端播放失败
    // 误导为系统引擎问题（缺陷 2）。
    when(() => tts.speak(any<String>()))
        .thenThrow(const TtsException('云端音频播放失败，请稍后重试'));
    final settings = _MockSettingsRepository();
    when(() => settings.loadSpeechRecognitionSettings())
        .thenAnswer((_) async => _verifiedSettings);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
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

    expect(find.text('范读失败：云端音频播放失败，请稍后重试'), findsOneWidget);
    expect(find.textContaining('请检查系统语音服务'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('开始跟读前停止范读失败时保持空闲并提示', (tester) async {
    when(() => tts.stop()).thenAnswer(
      (_) async => throw const TtsException('停止失败'),
    );
    final settings = _MockSettingsRepository();
    when(() => settings.loadSpeechRecognitionSettings())
        .thenAnswer((_) async => _verifiedSettings);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
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
    await tester.pump();

    await tester.tap(find.text('读一读'));
    await tester.pump();

    expect(find.text('读一读'), findsOneWidget);
    expect(find.text('无法开始跟读，请稍后重试'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
