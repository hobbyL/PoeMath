// test/features/profile/backup_passphrase_dialog_test.dart
//
// 备份口令对话框交互测试：输入（留空跳过）、设置（两遍确认）、清除。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/features/profile/widgets/backup_passphrase_dialog.dart';

void main() {
  /// 打开对话框并返回结果容器；对话框关闭后 `value` 即为返回值。
  Future<ValueNotifier<String?>> pumpAndOpen(
    WidgetTester tester,
    Future<String?> Function(BuildContext context) opener,
  ) async {
    final result = ValueNotifier<String?>(null);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result.value = await opener(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  Future<void> fillField(
    WidgetTester tester,
    String label,
    String text,
  ) async {
    await tester.enterText(find.widgetWithText(TextField, label), text);
    await tester.pump();
  }

  group('输入对话框（恢复/下载用）', () {
    testWidgets('输入口令确定，返回该口令', (tester) async {
      final result = await pumpAndOpen(
        tester,
        showBackupPassphraseInputDialog,
      );
      await fillField(tester, '备份加密口令', '我的口令');
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();
      await tester.pump();
      expect(result.value, '我的口令');
    });

    testWidgets('留空确定，返回空字符串（跳过凭据）', (tester) async {
      final result = await pumpAndOpen(
        tester,
        showBackupPassphraseInputDialog,
      );
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();
      await tester.pump();
      expect(result.value, '');
    });

    testWidgets('取消返回 null', (tester) async {
      final result = await pumpAndOpen(
        tester,
        showBackupPassphraseInputDialog,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pump();
      expect(result.value, isNull);
    });
  });

  group('设置对话框', () {
    testWidgets('两遍一致保存，返回新口令', (tester) async {
      final result = await pumpAndOpen(
        tester,
        (context) =>
            showBackupPassphraseSetupDialog(context, hasExisting: false),
      );
      await fillField(tester, '口令', '新口令');
      await fillField(tester, '再次输入确认', '新口令');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.pump();
      expect(result.value, '新口令');
    });

    testWidgets('两次输入不一致提示且不关闭', (tester) async {
      final result = await pumpAndOpen(
        tester,
        (context) =>
            showBackupPassphraseSetupDialog(context, hasExisting: false),
      );
      await fillField(tester, '口令', '第一次');
      await fillField(tester, '再次输入确认', '第二次');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(find.text('两次输入不一致'), findsOneWidget);
      expect(result.value, isNull); // 对话框未关闭

      // 改为一致后可保存
      await fillField(tester, '再次输入确认', '第一次');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.pump();
      expect(result.value, '第一次');
    });

    testWidgets('空口令提示不能为空', (tester) async {
      final result = await pumpAndOpen(
        tester,
        (context) =>
            showBackupPassphraseSetupDialog(context, hasExisting: true),
      );
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(
        find.text('口令不能为空（如需清除请点「清除口令」）'),
        findsOneWidget,
      );
      expect(result.value, isNull);
    });

    testWidgets('已设口令时提供清除入口，确认后返回空字符串', (tester) async {
      final result = await pumpAndOpen(
        tester,
        (context) =>
            showBackupPassphraseSetupDialog(context, hasExisting: true),
      );
      expect(find.text('清除口令'), findsOneWidget);

      await tester.tap(find.text('清除口令'));
      await tester.pumpAndSettle();
      // 二次确认
      await tester.tap(find.text('清除'));
      await tester.pumpAndSettle();
      await tester.pump();
      expect(result.value, '');
    });

    testWidgets('未设口令时无清除入口', (tester) async {
      await pumpAndOpen(
        tester,
        (context) =>
            showBackupPassphraseSetupDialog(context, hasExisting: false),
      );
      expect(find.text('清除口令'), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });
  });
}
