// 自有正文与独立缓存，不初始化或修改正常应用的学习数据。
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/tts/narration_audio_cache.dart';
import 'package:poemath/core/services/tts/narration_player.dart';
import 'package:poemath/core/services/tts/system_tts_file_synthesizer.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/textbook_lesson_content.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/textbook_lesson_content_page.dart';
import 'package:poemath/features/textbook/widgets/textbook_course_content.dart';
import '../test/helpers/narration_fakes.dart';
import '../test/helpers/textbook_course_fixture.dart';

class _CountingSynth implements SystemTtsFileSynthesizer {
  final delegate = AndroidSystemTtsFileSynthesizer();
  final texts = <String>[];
  @override
  Future<String> describeVoice(Map<String, String>? voice, double speed) =>
      delegate.describeVoice(voice, speed);
  @override
  Future<Uint8List> synthesize({
    required int sessionId,
    required String text,
    required Map<String, String>? voice,
    required double speed,
  }) {
    texts.add(text);
    return delegate.synthesize(
        sessionId: sessionId, text: text, voice: voice, speed: speed,);
  }

  @override
  Future<void> cancelSession(int sessionId) =>
      delegate.cancelSession(sessionId);
  @override
  Future<void> dispose() => delegate.dispose();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('真实系统合成：前瞻、同点暂停、缓存、高亮与退出停止', (tester) async {
    final directory =
        await Directory.systemTemp.createTemp('narration_acceptance_');
    final cache = NarrationAudioCache(directoryProvider: () async => directory);
    final synth = _CountingSynth();
    final players = <AudioPlayer>[];
    final service = TtsService(
      NarrationSettings(),
      flutterTts: NarrationEngine(),
      fileSynthesizer: synth,
      narrationPlayerFactory: () {
        final player = AudioPlayer();
        players.add(player);
        return AudioplayersNarrationPlayer(player: player);
      },
    );
    final raw = courseFixture();
    final lesson = (raw['lessons'] as List).single as Map;
    lesson['paragraphs'] = [
      courseFixtureText(
        'acceptance-paragraph',
        '清晨的阳光照进窗户，小朋友打开课本，看见一片蓝蓝的天空，白云慢慢地飘过。'
            '大家走出教室，一起观察校园里的花草，听小鸟唱歌，感受春天温暖的风。'
          '老师请每个孩子说说自己的发现，然后把今天看到的美好景色写下来，分享给朋友。'
          '午后的图书角很安静，孩子们找到喜欢的故事书，认真阅读，再交流故事里的趣事。'
          '放学之后，我们沿着小路走回家，看看路边新长出的嫩芽，听听树叶沙沙的声音。'
          '晚上大家和家人讲述校园生活，收拾好第二天的书包，带着快乐的心情进入梦乡。',
        null,
      ),
    ];
    lesson['recitations'] = <Object>[];
    (lesson['coverage'] as Map)['recitations'] = 'notApplicable';
    Widget page() => ProviderScope(
          overrides: [
            ttsServiceProvider.overrideWithValue(service),
            textbookFileServiceProvider.overrideWithValue(
                TextbookFileService(narrationAudioCache: cache),),
            textbookCourseProvider(courseFixtureHash)
                .overrideWith((_) async => TextbookCoursePack.fromJson(raw)),
          ],
          child: MaterialApp(
            home: TextbookLessonContentPage(
              bookId: courseFixtureHash,
              section: TextbookContentSection.reading,
              pages: const [2],
            ),
          ),
        );
    try {
      final identity = await synth.describeVoice(null, 0.5);
      debugPrint('NARRATION_ACCEPTANCE engine=$identity');
      final wav = await synth.delegate.synthesize(
          sessionId: -1, text: '你好，这是本机语音测试。', voice: null, speed: 0.5,);
      debugPrint('NARRATION_ACCEPTANCE wavBytes=${wav.length}');
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      final wait = Stopwatch()..start();
      await tester.tap(find.byTooltip('朗读课文'));
      await until(
          tester,
          () =>
              players.isNotEmpty && players.last.state == PlayerState.playing,);
      debugPrint(
          'NARRATION_ACCEPTANCE firstReadyMs=${wait.elapsedMilliseconds}',);
      expect(
          tester
              .widget<TextbookCourseParagraphsContent>(
                  find.byType(TextbookCourseParagraphsContent),)
              .activeRanges,
          isNotEmpty,);
      await until(tester, () => synth.texts.length >= 2);
      await tester.pump(const Duration(milliseconds: 800));
      final native = players.last;
      await tester.tap(find.byTooltip('暂停朗读'));
      await until(tester, () => native.state == PlayerState.paused);
      final paused = (await native.getCurrentPosition())!;
      await tester.pump(const Duration(milliseconds: 650));
      final still = (await native.getCurrentPosition())!;
      expect((still - paused).inMilliseconds.abs(), lessThan(80));
      await tester.tap(find.byTooltip('继续朗读'));
      await until(tester, () => native.state == PlayerState.playing);
      await tester.pump(const Duration(milliseconds: 750));
      final continued = (await native.getCurrentPosition())!;
      expect(
          continued, greaterThan(paused + const Duration(milliseconds: 300)),);
      debugPrint(
          'NARRATION_ACCEPTANCE pauseMs=${paused.inMilliseconds} stillMs=${still.inMilliseconds} resumedMs=${continued.inMilliseconds} generated=${synth.texts.length}',);
      await tester.pumpWidget(const SizedBox());
      await until(tester, () => native.state == PlayerState.disposed);
      expect(service.isSpeaking, false);
      final firstText = synth.texts.first;
      final calls = synth.texts.where((t) => t == firstText).length;
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('朗读课文'));
      await until(tester, () => players.last.state == PlayerState.playing);
      expect(synth.texts.where((t) => t == firstText).length, calls);
      await tester.tap(find.byTooltip('暂停朗读'));
      await until(tester, () => players.last.state == PlayerState.paused);
      await tester.pumpWidget(const SizedBox());
      await until(tester, () => players.last.state == PlayerState.disposed);
      expect(service.isSpeaking, false);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await service.stop();
      service.dispose();
      await directory.delete(recursive: true);
    }
  });
}

Future<void> until(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 600; i++) {
    if (condition()) return;
    if (find.byTooltip('重试朗读').evaluate().isNotEmpty) {
      final messages = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .join(' / ');
      throw StateError('教材朗读失败：$messages');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  throw StateError('教材语音未在30秒内进入预期状态');
}
