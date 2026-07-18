// test/features/poem/poem_recite_mode_page_test.dart
//
// 背诵模式选择页 Widget 测试。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/data/models/poem.dart';
import 'package:poemath/features/poem/poem_recite_mode_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

Poem _makePoem({
  String id = 'test-001',
  String title = '静夜思',
  String author = '李白',
  String dynasty = '唐',
  String content = '床前明月光，\n疑是地上霜。\n举头望明月，\n低头思故乡。',
  int? grade = 1,
  int difficulty = 2,
  List<String> tags = const ['思乡'],
}) {
  return Poem(
    id: id,
    title: title,
    author: author,
    dynasty: dynasty,
    content: content,
    pinyin: '',
    layer: 'core',
    grade: grade,
    difficulty: difficulty,
    tags: tags,
  );
}

void main() {
  group('PoemReciteModePage', () {
    Widget buildApp({
      required String poemId,
      Poem? poem,
    }) {
      final testPoem = poem ?? _makePoem(id: poemId);

      return ProviderScope(
        overrides: [
          poemByIdProvider(poemId).overrideWith((ref) => testPoem),
        ],
        child: MaterialApp(
          home: PoemReciteModePage(poemId: poemId),
        ),
      );
    }

    testWidgets('显示 3 种模式卡片', (tester) async {
      await tester.pumpWidget(buildApp(poemId: 'test-001'));
      await tester.pump();

      expect(find.text('渐进背诵'), findsOneWidget);
      expect(find.text('填空测试'), findsOneWidget);
      expect(find.text('选择题'), findsOneWidget);
    });

    testWidgets('显示诗词标题', (tester) async {
      await tester.pumpWidget(
        buildApp(
          poemId: 'test-001',
          poem: _makePoem(title: '春晓'),
        ),
      );
      await tester.pump();

      expect(find.text('春晓'), findsOneWidget);
    });

    testWidgets('显示作者和朝代', (tester) async {
      await tester.pumpWidget(
        buildApp(
          poemId: 'test-001',
          poem: _makePoem(author: '孟浩然', dynasty: '唐'),
        ),
      );
      await tester.pump();

      expect(find.text('〔唐〕孟浩然'), findsOneWidget);
    });

    testWidgets('显示年级标签', (tester) async {
      await tester.pumpWidget(
        buildApp(
          poemId: 'test-001',
          poem: _makePoem(grade: 3),
        ),
      );
      await tester.pump();

      expect(find.text('3年级'), findsOneWidget);
    });

    testWidgets('显示难度星标', (tester) async {
      await tester.pumpWidget(
        buildApp(
          poemId: 'test-001',
          poem: _makePoem(difficulty: 3),
        ),
      );
      await tester.pump();

      expect(find.text('难度 ★★★'), findsOneWidget);
    });

    testWidgets('显示主题标签', (tester) async {
      await tester.pumpWidget(
        buildApp(
          poemId: 'test-001',
          poem: _makePoem(tags: ['送别']),
        ),
      );
      await tester.pump();

      expect(find.text('送别'), findsOneWidget);
    });

    testWidgets('显示诗文预览折叠区', (tester) async {
      await tester.pumpWidget(buildApp(poemId: 'test-001'));
      await tester.pump();

      expect(find.text('诗文预览'), findsOneWidget);
    });

    testWidgets('显示学习贴士', (tester) async {
      await tester.pumpWidget(buildApp(poemId: 'test-001'));
      await tester.pump();

      expect(
        find.textContaining('建议先用「渐进背诵」打基础'),
        findsOneWidget,
      );
    });

    testWidgets('诗词未找到时显示提示', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            poemByIdProvider('nonexistent').overrideWith((ref) => null),
          ],
          child: const MaterialApp(
            home: PoemReciteModePage(poemId: 'nonexistent'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('诗词未找到'), findsOneWidget);
    });

    testWidgets('展开诗文预览显示诗词内容', (tester) async {
      final poem = _makePoem(
        content: '白日依山尽，\n黄河入海流。',
      );
      await tester.pumpWidget(
        buildApp(poemId: 'test-001', poem: poem),
      );
      await tester.pump();

      // 初始折叠状态，内容不可见
      expect(find.text('白日依山尽，\n黄河入海流。'), findsNothing);

      // 点击展开
      await tester.tap(find.text('诗文预览'));
      await tester.pumpAndSettle();

      // 展开后内容可见
      expect(find.text('白日依山尽，\n黄河入海流。'), findsOneWidget);
    });
  });
}
