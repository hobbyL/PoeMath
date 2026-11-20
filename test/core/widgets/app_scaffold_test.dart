import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/widgets/app_scaffold.dart';
import 'package:poemath/core/widgets/pine_ink_surface.dart';

void main() {
  testWidgets('页面底图保留原生正文约束、安全区和键盘避让', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    for (final size in [const Size(320, 800), const Size(914, 411)]) {
      tester.view.physicalSize = size;
      for (final keyboard in [0.0, 180.0]) {
        final layouts = <(BoxConstraints, Rect, Rect)>[];
        for (final decorated in [false, true]) {
          late BoxConstraints bodyConstraints;
          final body = LayoutBuilder(
            builder: (context, constraints) {
              bodyConstraints = constraints;
              return SafeArea(
                child: ListView.builder(
                  itemCount: 20,
                  itemExtent: 64,
                  itemBuilder: (context, index) =>
                      TextButton(onPressed: () {}, child: Text('学习内容 $index')),
                ),
              );
            },
          );
          final bar = AppBar(title: const Text('详情'));
          const bottom = SafeArea(
            child: SizedBox(height: 48, child: Center(child: Text('底部操作'))),
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.resolve(
                subject: AppSubject.poem,
                brightness: Brightness.light,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.fromLTRB(12, 24, 12, 24),
                  viewPadding: const EdgeInsets.fromLTRB(12, 24, 12, 24),
                  viewInsets: EdgeInsets.only(bottom: keyboard),
                ),
                child: child!,
              ),
              home: decorated
                  ? AppScaffold(
                      appBar: bar,
                      bottomNavigationBar: bottom,
                      body: body,
                    )
                  : Scaffold(
                      appBar: bar,
                      bottomNavigationBar: bottom,
                      body: body,
                    ),
            ),
          );
          await tester.pumpAndSettle();
          layouts.add((
            bodyConstraints,
            tester.getRect(find.text('学习内容 0')),
            tester.getRect(find.text('底部操作')),
          ));
          expect(tester.takeException(), isNull);
        }
        expect(
          (layouts.last.$1.smallest, layouts.last.$1.biggest),
          (layouts.first.$1.smallest, layouts.first.$1.biggest),
          reason: '$size / keyboard $keyboard',
        );
        expect(layouts.last.$2, layouts.first.$2);
        expect(layouts.last.$3, layouts.first.$3);
      }
    }
  });

  testWidgets('切换四套主题和明暗时保留输入、滚动位置及点击', (tester) async {
    const content = _Editor();
    var taps = 0;
    _EditorState? initialState;
    for (final preset in [
      AppSubject.poem,
      ...AppSubject.values,
      AppSubject.poem,
    ]) {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.resolve(subject: preset, brightness: brightness),
            home: AppScaffold(
              backgroundScene: PineInkScene.study,
              floatingActionButton: FloatingActionButton(
                onPressed: () => taps++,
                child: const Icon(Icons.check),
              ),
              body: content,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final editor = tester.state<_EditorState>(find.byType(_Editor));
        if (initialState == null) {
          initialState = editor;
          await tester.enterText(find.byType(TextField), '正在写的学习笔记');
          editor.scroll.jumpTo(240);
          await tester.pump();
        }
        expect(editor, same(initialState));
        expect(editor.text.text, '正在写的学习笔记');
        expect(editor.scroll.offset, 240);
        expect(
          find.byType(Image),
          preset == AppSubject.poem ? findsOneWidget : findsNothing,
        );
        final before = taps;
        await tester.tap(find.byType(FloatingActionButton));
        expect(taps, before + 1);
        expect(tester.takeException(), isNull);
      }
    }
  });
}

class _Editor extends StatefulWidget {
  const _Editor();

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final text = TextEditingController();
  final scroll = ScrollController();

  @override
  void dispose() {
    text.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(controller: text),
      Expanded(
        child: ListView.builder(
          controller: scroll,
          itemCount: 40,
          itemExtent: 64,
          itemBuilder: (context, index) => Text('学习记录 $index'),
        ),
      ),
    ],
  );
}
