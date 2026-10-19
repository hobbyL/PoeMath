// test/features/profile/update_page_layout_test.dart
//
// 更新页布局：无「版本信息」卡；版本区间并入「更新内容」标题。
//
// 背景：原先版本号单独占一张「版本信息」卡（当前版本 / 最新版本 /
// 安装包大小 / 发布通道），与「更新内容」卡重复展示且占据首屏。现只保留
// 最必要的一段 —— 用户在「更新内容」标题处即可看到版本变化。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/update/android_update_installer.dart';
import 'package:poemath/core/services/update/update_client.dart';
import 'package:poemath/core/services/update/update_models.dart';
import 'package:poemath/features/profile/update_page.dart';

/// 直接给出最新版本信息，不走 HTTP。
class _StubUpdateClient implements UpdateClient {
  _StubUpdateClient(this.latest);

  final AppUpdateInfo latest;

  @override
  Future<AppUpdateInfo> fetchLatest() async => latest;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('本用例只触发 fetchLatest');
}

/// 直接给出当前版本，不走平台通道。
class _StubInstaller implements AndroidUpdateInstaller {
  _StubInstaller(this.current);

  final AppVersionInfo current;

  @override
  Future<AppVersionInfo> getCurrentVersion() async => current;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('本用例只触发 getCurrentVersion');
}

AppUpdateInfo _latest({
  String versionName = '0.0.11',
  String notes = '修复若干问题。',
}) {
  return AppUpdateInfo(
    packageName: 'com.poemath.app',
    versionName: versionName,
    versionCode: 11,
    tagName: 'v$versionName',
    channel: 'stable',
    apkUrl: 'https://example.com/app.apk',
    apkSha256: 'a' * 64,
    apkSize: 1024,
    mandatory: false,
    notes: notes,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required String currentVersion,
  required AppUpdateInfo latest,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: UpdatePage(
        updateClient: _StubUpdateClient(latest),
        updateInstaller: _StubInstaller(
          AppVersionInfo(
            packageName: 'com.poemath.app',
            versionName: currentVersion,
            versionCode: 10,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('不再展示「版本信息」卡片', (tester) async {
    await _pump(tester, currentVersion: '0.0.10', latest: _latest());

    expect(find.text('版本信息'), findsNothing);
    expect(find.text('当前版本'), findsNothing);
    expect(find.text('最新版本'), findsNothing);
    expect(find.text('安装包大小'), findsNothing);
    expect(find.text('发布通道'), findsNothing);
  });

  testWidgets('更新内容标题带版本区间', (tester) async {
    await _pump(tester, currentVersion: '0.0.10', latest: _latest());

    expect(find.text('更新内容 V0.0.10 → V0.0.11'), findsOneWidget);
    // 正文仍在标题下方。
    expect(find.text('修复若干问题。'), findsOneWidget);
  });

  testWidgets('版本号缺失时标题退回纯「更新内容」', (tester) async {
    // 当前版本读不出（如平台通道异常）时不该渲染「V → V0.0.11」这种半截文案。
    await _pump(tester, currentVersion: '', latest: _latest());

    expect(find.text('更新内容'), findsOneWidget);
    expect(find.textContaining('→'), findsNothing);
  });
}
