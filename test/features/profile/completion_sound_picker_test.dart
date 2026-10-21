import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/domain/completion_sound.dart';
import 'package:poemath/domain/answer_feedback_sound.dart';
import 'package:poemath/features/profile/settings_page.dart';
import 'package:poemath/features/profile/widgets/completion_sound_picker.dart';

import '../../helpers/hive_test_helper.dart';

class _PreviewSound extends SoundService {
  _PreviewSound() : super(SettingsRepository());
  final played = <CompletionSound>[];
  final answers = <(AnswerFeedbackSound, bool)>[];
  bool succeeds = true;
  bool disposed = false;

  @override
  Future<bool> previewCompletion(CompletionSound sound) async {
    played.add(sound);
    return succeeds;
  }

  @override
  Future<bool> previewAnswerFeedback(AnswerFeedbackSound sound) async {
    answers.addAll([(sound, true), (sound, false)]);
    return succeeds;
  }

  @override
  void dispose() => disposed = true;
}

class _ControlledSettings extends SettingsRepository {
  CompletionSound selected = CompletionSound.ensemble;
  final release = Completer<void>();
  int writes = 0;
  bool fail = false;
  AnswerFeedbackSound answer = AnswerFeedbackSound.classic;

  @override
  AnswerFeedbackSound get answerFeedbackSound => answer;

  @override
  Future<void> setAnswerFeedbackSound(AnswerFeedbackSound sound) async {
    writes++;
    await release.future;
    if (fail) throw StateError('存储不可用');
    answer = sound;
  }

  @override
  CompletionSound get completionSound => selected;

  @override
  Future<void> setCompletionSound(CompletionSound sound) async {
    writes++;
    await release.future;
    if (fail) throw StateError('存储不可用');
    selected = sound;
  }
}

Finder _radio(CompletionSound sound) => find.byWidgetPredicate(
      (widget) => widget is Radio<CompletionSound> && widget.value == sound,
    );

Future<void> _mount(
  WidgetTester tester,
  ProviderContainer container,
  _PreviewSound preview,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: CompletionSoundPicker(previewService: preview)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _answerRadio(AnswerFeedbackSound sound) => find.byWidgetPredicate(
      (widget) => widget is Radio<AnswerFeedbackSound> && widget.value == sound,
    );

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  testWidgets('四种声音可保存，试听不改选择或音效开关，关闭释放播放器', (tester) async {
    final settings = SettingsRepository();
    await tester.runAsync(() => settings.setSoundEnabled(false));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final preview = _PreviewSound();
    await _mount(tester, container, preview);
    for (final sound in AnswerFeedbackSound.values) {
      await _tapVisible(tester, find.byTooltip('试听${sound.label}'));
      await tester.pumpAndSettle();
    }
    expect(preview.answers, [
      (AnswerFeedbackSound.classic, true),
      (AnswerFeedbackSound.classic, false),
      (AnswerFeedbackSound.childVoice, true),
      (AnswerFeedbackSound.childVoice, false),
    ]);
    expect(settings.answerFeedbackSound, AnswerFeedbackSound.classic);
    await tester.ensureVisible(_answerRadio(AnswerFeedbackSound.childVoice));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(_answerRadio(AnswerFeedbackSound.childVoice));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(settings.answerFeedbackSound, AnswerFeedbackSound.childVoice);
    expect(settings.completionSound, CompletionSound.ensemble);
    for (final sound in CompletionSound.values) {
      await _tapVisible(tester, find.byTooltip('试听${sound.label}'));
      await tester.pumpAndSettle();
    }
    expect(preview.played, CompletionSound.values);
    expect(settings.completionSound, CompletionSound.ensemble);
    expect(settings.soundEnabled, isFalse);
    for (final sound in CompletionSound.values) {
      await tester.ensureVisible(_radio(sound));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(_radio(sound));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(settings.completionSound, sound);
      expect(settings.answerFeedbackSound, AnswerFeedbackSound.childVoice);
      expect(
        tester
            .widget<RadioGroup<CompletionSound>>(
              find.byType(RadioGroup<CompletionSound>),
            )
            .groupValue,
        sound,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(preview.disposed, isTrue);
  });

  testWidgets('保存未完成时拦截连续选择，失败提示且可重试', (tester) async {
    final settings = _ControlledSettings()..fail = true;
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);
    await _mount(tester, container, _PreviewSound());
    await _tapVisible(tester, _answerRadio(AnswerFeedbackSound.childVoice));
    await _tapVisible(tester, _radio(CompletionSound.pizzicato));
    expect(settings.writes, 1);
    expect(settings.selected, CompletionSound.ensemble);
    expect(settings.answer, AnswerFeedbackSound.classic);
    settings.release.complete();
    await tester.pumpAndSettle();
    expect(find.text('保存失败，请重试'), findsOneWidget);
    expect(settings.selected, CompletionSound.ensemble);
    settings.fail = false;
    await _tapVisible(tester, _answerRadio(AnswerFeedbackSound.childVoice));
    await tester.pumpAndSettle();
    expect(settings.writes, 2);
    expect(settings.answer, AnswerFeedbackSound.childVoice);
    expect(settings.selected, CompletionSound.ensemble);
    expect(find.text('保存失败，请重试'), findsNothing);
  });

  testWidgets('试听失败给出提示，窄屏大字号可滚动无溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(() async {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.binding.setSurfaceSize(null);
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final preview = _PreviewSound()..succeeds = false;
    await _mount(tester, container, preview);
    await _tapVisible(tester, find.byTooltip('试听童趣语音'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法试听，请重试'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('试听过关小合奏'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置入口打开选择面板，关闭重开保持选择', (tester) async {
    final settings = SettingsRepository();
    await tester
        .runAsync(() => settings.setCompletionSound(CompletionSound.steelDrum));
    await tester.runAsync(
      () => settings.setAnswerFeedbackSound(AnswerFeedbackSound.childVoice),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('外观与反馈'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('练习音效'));
    await tester.pumpAndSettle();
    expect(find.byType(CompletionSoundPicker), findsOneWidget);
    expect(
      tester
          .widget<RadioGroup<AnswerFeedbackSound>>(
            find.byType(RadioGroup<AnswerFeedbackSound>),
          )
          .groupValue,
      AnswerFeedbackSound.childVoice,
    );
    expect(
      tester
          .widget<RadioGroup<CompletionSound>>(
            find.byType(RadioGroup<CompletionSound>),
          )
          .groupValue,
      CompletionSound.steelDrum,
    );
    await tester.ensureVisible(_radio(CompletionSound.arcade));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(_radio(CompletionSound.arcade));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await Navigator.of(
      tester.element(find.byType(CompletionSoundPicker)),
    ).maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(CompletionSoundPicker), findsNothing);
    expect(find.textContaining('经典电玩'), findsOneWidget);
    await tester.tap(find.text('练习音效'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RadioGroup<CompletionSound>>(
            find.byType(RadioGroup<CompletionSound>),
          )
          .groupValue,
      CompletionSound.arcade,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
