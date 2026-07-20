import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/profile/tts_settings_page.dart';

class _MockTtsService extends Mock implements TtsService {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  testWidgets('音色加载失败后退出加载状态并可重试', (tester) async {
    final tts = _MockTtsService();
    final settings = _MockSettingsRepository();
    var loadAttempts = 0;

    when(() => settings.ttsVoice).thenReturn(null);
    when(() => settings.ttsSpeed).thenReturn(0.5);
    when(() => tts.stop()).thenAnswer((_) async {});
    when(() => tts.getChineseVoices()).thenAnswer((_) async {
      loadAttempts++;
      if (loadAttempts == 1) {
        throw const TtsException('系统音色不可用');
      }
      return const <Map<String, String>>[
        <String, String>{'name': 'zh-cn', 'locale': 'zh-CN'},
      ];
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          ttsServiceProvider.overrideWithValue(tts),
        ],
        child: const MaterialApp(home: TtsSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('音色加载失败，请检查系统语音服务'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);

    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();

    expect(find.text('音色加载失败，请检查系统语音服务'), findsNothing);
    expect(find.text('系统默认'), findsOneWidget);
    expect(find.text('普通话语音'), findsOneWidget);
    expect(loadAttempts, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
