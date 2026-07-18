// test/features/poem/widgets/poem_card_test.dart
//
// PoemCard 组件 Widget 测试。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/features/poem/widgets/poem_card.dart';

Poem _makePoem({
  String id = 'test-001',
  String title = '静夜思',
  String author = '李白',
  String dynasty = '唐',
  String content = '床前明月光，\n疑是地上霜。\n举头望明月，\n低头思故乡。',
  List<String> tags = const ['思乡'],
  bool isRequired = false,
}) {
  return Poem(
    id: id,
    title: title,
    author: author,
    dynasty: dynasty,
    content: content,
    pinyin: '',
    layer: 'core',
    tags: tags,
    isRequired: isRequired,
  );
}

void main() {
  Widget buildApp({
    required Poem poem,
    VoidCallback? onTap,
    bool isFavorite = false,
    LearningStatus? learningStatus,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PoemCard(
          poem: poem,
          onTap: onTap,
          isFavorite: isFavorite,
          learningStatus: learningStatus,
        ),
      ),
    );
  }

  group('PoemCard', () {
    testWidgets('显示诗题', (tester) async {
      final poem = _makePoem(title: '春晓');
      await tester.pumpWidget(buildApp(poem: poem));

      expect(find.text('春晓'), findsOneWidget);
    });

    testWidgets('显示作者和朝代', (tester) async {
      final poem = _makePoem(author: '杜甫', dynasty: '唐');
      await tester.pumpWidget(buildApp(poem: poem));

      expect(find.text('唐 · 杜甫'), findsOneWidget);
    });

    testWidgets('显示首句', (tester) async {
      final poem = _makePoem(
        content: '白日依山尽，\n黄河入海流。\n欲穷千里目，\n更上一层楼。',
      );
      await tester.pumpWidget(buildApp(poem: poem));

      // _firstLine 返回前两行
      expect(find.textContaining('白日依山尽'), findsOneWidget);
      expect(find.textContaining('黄河入海流'), findsOneWidget);
    });

    testWidgets('点击回调触发', (tester) async {
      var tapped = false;
      final poem = _makePoem();
      await tester.pumpWidget(
        buildApp(poem: poem, onTap: () => tapped = true),
      );

      await tester.tap(find.byType(PoemCard));
      expect(tapped, isTrue);
    });

    testWidgets('收藏标记显示红心图标', (tester) async {
      final poem = _makePoem();
      await tester.pumpWidget(
        buildApp(poem: poem, isFavorite: true),
      );

      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('未收藏时不显示红心图标', (tester) async {
      final poem = _makePoem();
      await tester.pumpWidget(
        buildApp(poem: poem, isFavorite: false),
      );

      expect(find.byIcon(Icons.favorite), findsNothing);
    });

    testWidgets('必背标签显示', (tester) async {
      final poem = _makePoem(isRequired: true);
      await tester.pumpWidget(buildApp(poem: poem));

      expect(find.text('必背'), findsOneWidget);
    });

    testWidgets('标签显示', (tester) async {
      final poem = _makePoem(tags: ['思乡', '写景']);
      await tester.pumpWidget(buildApp(poem: poem));

      expect(find.text('思乡'), findsOneWidget);
      expect(find.text('写景'), findsOneWidget);
    });

    testWidgets('已掌握状态显示丝带', (tester) async {
      final poem = _makePoem();
      await tester.pumpWidget(
        buildApp(
          poem: poem,
          learningStatus: LearningStatus.mastered,
        ),
      );

      expect(find.text('已掌握'), findsOneWidget);
    });

    testWidgets('学习中状态显示丝带', (tester) async {
      final poem = _makePoem();
      await tester.pumpWidget(
        buildApp(
          poem: poem,
          learningStatus: LearningStatus.learning,
        ),
      );

      expect(find.text('学习中'), findsOneWidget);
    });

    testWidgets('复习中状态显示丝带', (tester) async {
      final poem = _makePoem();
      await tester.pumpWidget(
        buildApp(
          poem: poem,
          learningStatus: LearningStatus.reviewing,
        ),
      );

      expect(find.text('复习中'), findsOneWidget);
    });

    testWidgets('未开始状态不显示丝带', (tester) async {
      final poem = _makePoem();
      await tester.pumpWidget(
        buildApp(
          poem: poem,
          learningStatus: LearningStatus.notStarted,
        ),
      );

      expect(find.text('已掌握'), findsNothing);
      expect(find.text('学习中'), findsNothing);
      expect(find.text('复习中'), findsNothing);
    });
  });
}
