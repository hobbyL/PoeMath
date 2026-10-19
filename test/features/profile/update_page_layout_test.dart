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
  _StubUpdateClient(this.latest, {this.history = const []});

  final AppUpdateInfo latest;
  final List<AppVersionHistoryEntry> history;

  @override
  Future<AppUpdateInfo> fetchLatest() async => latest;

  @override
  Future<List<AppVersionHistoryEntry>> fetchHistory() async => history;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('本用例只触发 fetchLatest / fetchHistory');
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
  List<AppVersionHistoryEntry> history = const [],
  Size surface = const Size(800, 1600),
}) async {
  // 默认给足高度：历史卡片展开后条目不少，默认 800x600 会把下方内容挤出
  // 渲染范围，`find` 就找不到了。
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: UpdatePage(
        updateClient: _StubUpdateClient(latest, history: history),
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

  // ---------- 版本历史 ----------

  List<AppVersionHistoryEntry> historyOf(int count) => [
        for (var i = 0; i < count; i++)
          AppVersionHistoryEntry(
            versionName: '0.0.${11 - i}',
            versionCode: 11 - i,
            tagName: 'v0.0.${11 - i}',
            notes: '第 ${11 - i} 版说明。',
          ),
      ];

  testWidgets('无版本历史时不渲染该卡片', (tester) async {
    await _pump(tester, currentVersion: '0.0.10', latest: _latest());

    expect(find.text('版本历史'), findsNothing);
  });

  testWidgets('历史超过 3 条时默认只显示 3 条，并可展开全部', (tester) async {
    await _pump(
      tester,
      currentVersion: '0.0.10',
      latest: _latest(),
      history: historyOf(5),
    );

    expect(find.text('版本历史'), findsOneWidget);
    // 折叠态：前 3 版可见，第 4 版不可见。
    expect(find.text('V0.0.11'), findsOneWidget);
    expect(find.text('V0.0.9'), findsOneWidget);
    expect(find.text('V0.0.8'), findsNothing);
    expect(find.text('查看全部 5 个版本'), findsOneWidget);

    await tester.tap(find.text('查看全部 5 个版本'));
    await tester.pumpAndSettle();

    // `find` 只匹配已渲染节点，展开后的条目落在首屏之下；把测试画布调高
    // 让整卡一次渲染完，比滚动断言更稳（滚动需要指定 scrollable，且
    // 内容高度随卡片数变化，容易脆）。
    expect(find.text('V0.0.8'), findsOneWidget);
    expect(find.text('V0.0.7'), findsOneWidget);
    // 展开后入口变为「收起」。
    expect(find.text('收起'), findsOneWidget);
  });

  testWidgets('历史不超过 3 条时不显示展开入口', (tester) async {
    await _pump(
      tester,
      currentVersion: '0.0.10',
      latest: _latest(),
      history: historyOf(2),
    );

    expect(find.text('V0.0.11'), findsOneWidget);
    expect(find.text('V0.0.10'), findsOneWidget);
    expect(find.textContaining('查看全部'), findsNothing);
  });

  testWidgets('标出当前安装的版本', (tester) async {
    await _pump(
      tester,
      currentVersion: '0.0.10',
      latest: _latest(),
      history: historyOf(3),
    );

    // 第三条才是当前版本（0.0.10）。
    expect(find.text('当前版本'), findsOneWidget);
  });

  testWidgets('该版无 notes 时给出说明而非留白', (tester) async {
    await _pump(
      tester,
      currentVersion: '0.0.10',
      latest: _latest(),
      history: [
        const AppVersionHistoryEntry(
          versionName: '0.0.11',
          versionCode: 11,
          tagName: 'v0.0.11',
          notes: '',
        ),
      ],
    );

    expect(find.text('本版无面向用户的变更。'), findsOneWidget);
  });
}
