import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/repositories/profile_nickname_repository.dart';
import 'package:poemath/features/profile/providers/profile_nickname_providers.dart';
import 'package:poemath/features/profile/widgets/profile_nickname_button.dart';

import '../../helpers/hive_test_helper.dart';

class _ControlledRepository extends ProfileNicknameRepository {
  int calls = 0;
  bool fail = false;
  Completer<void>? pending;

  @override
  Future<void> save(String profileId, String name) async {
    calls++;
    if (fail) throw StateError('save failed');
    await pending?.future;
    await super.save(profileId, name);
  }
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
  });
  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForTesting();
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    ProfileNicknameRepository? repository,
    double scale = 1,
  }) async {
    final container = ProviderContainer(
      overrides: [
        if (repository != null)
          profileNicknameRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final theme = AppTheme.resolve(
      subject: AppSubject.poem,
      brightness: Brightness.light,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: ProfileNicknameButton(
                foreground: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
    return container;
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('profile-nickname-edit')));
    await tester.pumpAndSettle();
  }

  Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 80 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(ready(), isTrue);
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('默认昵称可点开编辑，空输入提示，取消保留原值', (tester) async {
    final container = await pump(tester);
    expect(find.text('小小学习家'), findsOneWidget);
    await open(tester);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('请输入昵称'), findsOneWidget);
    expect(ProfileNicknameRepository().read('default'), isNull);
    await tester.enterText(find.byType(TextField), '不保存的昵称');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('小小学习家'), findsOneWidget);
    expect(ProfileNicknameRepository().read('default'), isNull);
    await dispose(tester, container);
  });

  testWidgets('保存去除首尾空格并立即更新，重新打开预填已保存昵称', (tester) async {
    final container = await pump(tester);
    await open(tester);
    await tester.enterText(find.byType(TextField), '  小月亮  ');
    await tester.runAsync(() => tester.tap(find.text('保存')));
    await waitFor(tester, () => find.byType(AlertDialog).evaluate().isEmpty);
    expect(find.text('小月亮'), findsOneWidget);
    expect(ProfileNicknameRepository().read('default'), '小月亮');
    await open(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '小月亮',
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await dispose(tester, container);
  });

  testWidgets('保存失败保留输入并能重试，保存期间重复点击和返回不重复写入', (tester) async {
    final repository = _ControlledRepository()..fail = true;
    final container = await pump(tester, repository: repository);
    await open(tester);
    await tester.enterText(find.byType(TextField), '小星星');
    await tester.runAsync(() => tester.tap(find.text('保存')));
    await waitFor(tester, () => find.text('保存失败，请重试').evaluate().isNotEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '小星星',
    );
    expect(repository.read('default'), isNull);
    repository.fail = false;
    repository.pending = Completer<void>();
    await tester.runAsync(() async {
      await tester.tap(find.text('保存'));
      await tester.tap(find.text('保存'));
    });
    await tester.pump();
    expect(repository.calls, 2);
    expect(find.text('保存中…'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    repository.pending!.complete();
    await waitFor(tester, () => find.byType(AlertDialog).evaluate().isEmpty);
    expect(repository.read('default'), '小星星');
    expect(find.text('小星星'), findsOneWidget);
    await dispose(tester, container);
  });

  testWidgets('编辑期间切换档案写回原档案，外部恢复及时刷新可见昵称', (tester) async {
    final container = await pump(tester);
    await open(tester);
    await tester.enterText(find.byType(TextField), '原档案昵称');
    ProfileScope.switchTo('child-b');
    await tester.pump();
    await tester.runAsync(() => tester.tap(find.text('保存')));
    await waitFor(tester, () => find.byType(AlertDialog).evaluate().isEmpty);
    final repository = ProfileNicknameRepository();
    expect(repository.read('default'), '原档案昵称');
    expect(repository.read('child-b'), isNull);
    expect(find.text('小小学习家'), findsOneWidget);
    await tester.runAsync(() => repository.save('child-b', '恢复的昵称'));
    await waitFor(tester, () => find.text('恢复的昵称').evaluate().isNotEmpty);
    expect(find.text('恢复的昵称'), findsOneWidget);
    await dispose(tester, container);
  });

  testWidgets('窄屏大字号与键盘下编辑框仍能输入和取消', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.reset);
    final container = await pump(tester, scale: 2);
    await open(tester);
    await tester.enterText(find.byType(TextField), '小月亮');
    expect(tester.takeException(), isNull);
    expect(find.text('取消').hitTestable(), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(ProfileNicknameRepository().read('default'), isNull);
    await dispose(tester, container);
  });
}
