// fvm flutter test integration_test/speech_recognition_settings_test.dart
// -d emulator-5554 --dart-define=POEMATH_INTEGRATION_TEST=true --no-uninstall
// 独立包、临时 Hive 和合成凭据，仅验证设置流程，不启动录音或云请求。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/widgets/page_animation_scope.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/profile/speech_recognition_settings_page.dart';

import '../test/helpers/hive_test_helper.dart';
import '../test/helpers/parent_access_test_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android 语音模式设置保存、清空和重进', (tester) async {
    expect(
      (await PackageInfo.fromPlatform()).packageName,
      'com.poemath.app.integration',
    );
    await setUpHiveForTesting();
    await unlockParentForTesting();
    final settings = SettingsRepository();
    final capture = GlobalKey();

    Future<void> open() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
          child: RepaintBoundary(
            key: capture,
            child: MaterialApp(
              theme: AppTheme.resolve(
                subject: AppSubject.poem,
                brightness: Brightness.light,
              ),
              home: const PageAnimationScope(
                enabled: false,
                child: SpeechRecognitionSettingsPage(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tap(Finder target) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        target,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(target.hitTestable());
      await tester.pumpAndSettle();
    }

    Future<void> save() async {
      await tap(find.widgetWithText(FilledButton, '保存设置'));
      final button = find.widgetWithText(FilledButton, '保存设置');
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (tester.widget<FilledButton>(button).onPressed != null) return;
      }
      fail('设置保存没有完成');
    }

    Future<void> screenshot(String name) async {
      await tester.ensureVisible(find.byType(Switch));
      await tester.pumpAndSettle();
      final boundary =
          capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final rendered = await boundary.toImage(pixelRatio: 2);
      final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
      await File('${(await getTemporaryDirectory()).path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      rendered.dispose();
    }

    try {
      await open();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      await tester.enterText(
        find.widgetWithText(TextField, 'SecretId (AK)'),
        'AKID-test',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'SecretKey (SK)'),
        'SK-test',
      );
      await tap(find.text('高级设置：手动填写 APPID'));
      await tester.enterText(
        find.widgetWithText(TextField, 'APPID'),
        '1250000000',
      );
      await tester.pump();
      await tap(find.byType(Switch));
      await save();
      expect(
        (await settings.loadSpeechRecognitionSettings()).preferRealtime,
        isTrue,
      );
      await screenshot('speech-realtime-on');

      final appIdField = find.widgetWithText(TextField, 'APPID');
      await tap(appIdField);
      await tester.enterText(appIdField, '');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'APPID'))
            .controller!
            .text,
        '',
      );
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      await save();
      expect((await settings.readTencentAsrCredentials())?.appId, '');
      expect(
        (await settings.loadSpeechRecognitionSettings()).preferRealtime,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await open();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      await screenshot('speech-realtime-cleared');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      lockParentForTesting();
      await tearDownHiveForTesting();
    }
  });
}
