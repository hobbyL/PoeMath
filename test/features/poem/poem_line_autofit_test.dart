// test/features/poem/poem_line_autofit_test.dart
//
// 诗句一行自适应的页面级验证：详情页窄屏单行缩放 / 宽屏不缩放，
// 学习页与跟读页的当前句由 AutoFitLine 包裹（缩放契约由组件测试钉死）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/poem/poem_detail_page.dart';
import 'package:poemath/features/poem/poem_recite_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

class _MockTtsService extends Mock implements TtsService {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

const _poemId = 'autofit-test-poem';

// 16 字长句：固有宽度（16 × ~26px）在 320dp 窄屏下必然超宽。
final _longLinePoem = Poem(
  id: _poemId,
  title: '春江花月夜（节选）',
  author: '张若虚',
  dynasty: '唐',
  content: '春江潮水连海平，海上明月共潮生。',
  pinyin: '',
  layer: 'core',
);

RenderBox _lineBox(WidgetTester tester, String line) =>
    tester.renderObject<RenderBox>(find.text(line));

RenderBox _fittedBoxOf(WidgetTester tester, String line) =>
    tester.renderObject<RenderBox>(
      find.ancestor(of: find.text(line), matching: find.byType(FittedBox)).first,
    );

Future<void> _pumpDetailPage(WidgetTester tester) async {
  final tts = _MockTtsService();
  final settings = _MockSettingsRepository();
  when(() => tts.stop()).thenAnswer((_) async {});
  when(() => settings.pinyinVisible).thenReturn(false);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        ttsServiceProvider.overrideWithValue(tts),
        poemByIdProvider(_poemId).overrideWith((ref) => _longLinePoem),
        isFavoriteProvider(_poemId).overrideWith((ref) => false),
        poemProgressProvider(_poemId).overrideWith((ref) => null),
      ],
      child: MaterialApp(
        // 挂应用真实主题，诗句走 PoemThemeExt.poemContent（24/1.8）。
        theme: AppTheme.resolve(
          subject: AppSubject.poem,
          brightness: Brightness.light,
        ),
        home: const PoemDetailPage(poemId: _poemId),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('详情页窄屏：长句保持单行并整行缩小', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpDetailPage(tester);

    const line = '春江潮水连海平，海上明月共潮生。';
    final lineBox = _lineBox(tester, line);
    final fittedBox = _fittedBoxOf(tester, line);

    // 单行：高度 == fontSize(24) × height(1.8)，换行会翻倍。
    expect(lineBox.size.height, closeTo(24 * 1.8, 1.0));
    // Text 保持固有宽度（>320，未被压缩换行），外框缩进可用宽度。
    expect(lineBox.size.width, greaterThan(300));
    expect(fittedBox.size.width, lessThan(lineBox.size.width));
    expect(fittedBox.size.width, lessThanOrEqualTo(320));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('详情页宽屏：长句保持原尺寸不缩不放', (tester) async {
    await _pumpDetailPage(tester);

    const line = '春江潮水连海平，海上明月共潮生。';
    final lineBox = _lineBox(tester, line);
    final fittedBox = _fittedBoxOf(tester, line);

    // 缩放比例为 1：外框 == 固有尺寸，宽屏下字号不变。
    expect(fittedBox.size.width, closeTo(lineBox.size.width, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('学习页：当前句填字行由 AutoFitLine 包裹', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          poemByIdProvider(_poemId).overrideWith((ref) => _longLinePoem),
        ],
        child: const MaterialApp(home: PoemRecitePage(poemId: _poemId)),
      ),
    );
    await tester.pump();

    // 当前句是 Wrap（逐字填空），整行被 AutoFitLine 包住保证单行缩小。
    expect(
      find.descendant(of: find.byType(AutoFitLine), matching: find.byType(Wrap)),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
