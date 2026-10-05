import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/update/android_update_installer.dart';
import 'package:poemath/core/services/update/update_client.dart';
import 'package:poemath/core/services/update/update_models.dart';
import 'package:poemath/features/shell/update_dialog.dart';

/// 可控的更新客户端 fake：绕过真实网络与文件 I/O（testWidgets 的
/// FakeAsync 环境下 dart:io 完成事件无法推进），仅驱动状态机流转。
///
/// 下载固定耗时 10ms（fake clock）：首个 pump 可断言 downloading 中间态，
/// pumpAndSettle 推进时钟后完成；期间取消令牌触发则按取消语义抛出。
class _FakeUpdateClient extends UpdateClient {
  _FakeUpdateClient({required this.digest})
      : super(updateUrl: 'https://updates.example.com/latest.json');

  /// sha256Of 返回的摘要（与 apkSha256 比对）。
  final String digest;

  int downloadCount = 0;

  @override
  Future<File> downloadApk(
    AppUpdateInfo update, {
    void Function(int received, int? total)? onProgress,
    UpdateDownloadCancelToken? cancelToken,
  }) async {
    downloadCount++;
    onProgress?.call(2, 4);
    onProgress?.call(4, 4);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    cancelToken?.throwIfCancelled();
    return File('/tmp/poemath-fake-update.apk');
  }

  @override
  Future<String> sha256Of(File file) async => digest;
}

AppUpdateInfo _update() {
  return AppUpdateInfo(
    packageName: 'com.poemath.app',
    versionName: '2.0.0',
    versionCode: 200,
    tagName: 'v2.0.0',
    channel: 'stable',
    apkUrl: 'https://updates.example.com/poemath.apk',
    apkSha256: 'a' * 64,
    apkSize: 4,
    mandatory: false,
    notes: '修复若干问题，优化体验。',
  );
}

AppVersionInfo _current() {
  return const AppVersionInfo(
    packageName: 'com.poemath.app',
    versionName: '1.0.0',
    versionCode: 100,
  );
}

const _testChannel = MethodChannel('poemath.test/update_dialog');

/// 注册 fake 安装器通道，返回按序记录的方法调用列表。
List<String> _installChannelHandler({required bool canInstall}) {
  final calls = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_testChannel, (call) async {
    calls.add(call.method);
    return switch (call.method) {
      'inspectApk' => <String, Object?>{
          'packageName': 'com.poemath.app',
          'versionName': '2.0.0',
          'versionCode': 200,
        },
      'canRequestPackageInstalls' => canInstall,
      _ => null,
    };
  });
  return calls;
}

/// 打开弹窗并完成入场动画，返回 showUpdateDialog 的 Future。
Future<Future<bool?>?> _openDialog(
  WidgetTester tester, {
  required UpdateClient client,
  required AndroidUpdateInstaller installer,
}) async {
  Future<bool?>? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () {
                result = showUpdateDialog(
                  context: context,
                  update: _update(),
                  current: _current(),
                  client: client,
                  installer: installer,
                );
              },
              child: const Text('打开弹窗'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开弹窗'));
  await tester.pumpAndSettle();
  return result;
}

AndroidUpdateInstaller _installer() {
  return AndroidUpdateInstaller(
    channel: _testChannel,
    isAndroid: true,
  );
}

void main() {
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_testChannel, null);
  });

  testWidgets('available 态展示版本信息、更新说明与双按钮', (tester) async {
    _installChannelHandler(canInstall: true);
    final client = _FakeUpdateClient(digest: 'a' * 64);

    await _openDialog(tester, client: client, installer: _installer());

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('当前版本'), findsOneWidget);
    expect(find.text('v1.0.0'), findsOneWidget);
    expect(find.text('v2.0.0'), findsOneWidget);
    expect(find.text('修复若干问题，优化体验。'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('下载更新'), findsOneWidget);
    expect(client.downloadCount, 0);
  });

  testWidgets('下载 → 校验 → 就绪完整链路', (tester) async {
    final calls = _installChannelHandler(canInstall: true);
    final client = _FakeUpdateClient(digest: 'a' * 64);

    await _openDialog(tester, client: client, installer: _installer());

    await tester.tap(find.text('下载更新'));
    await tester.pump();
    expect(find.text('正在下载'), findsOneWidget);
    expect(find.textContaining('已下载'), findsOneWidget);

    // 推进 fake clock 越过下载耗时，链路继续到就绪。
    await tester.pumpAndSettle();

    expect(find.text('可以安装'), findsOneWidget);
    expect(find.text('立即安装'), findsOneWidget);
    expect(find.text('安装包已下载并校验完成。'), findsOneWidget);
    // 校验链：inspectApk 在就绪前被调用。
    expect(calls, contains('inspectApk'));
  });

  testWidgets('取消下载回到可下载状态', (tester) async {
    _installChannelHandler(canInstall: true);
    final client = _FakeUpdateClient(digest: 'a' * 64);

    await _openDialog(tester, client: client, installer: _installer());

    await tester.tap(find.text('下载更新'));
    await tester.pump();
    expect(find.text('正在下载'), findsOneWidget);

    await tester.tap(find.text('取消下载'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('下载已取消。'), findsOneWidget);
    expect(find.text('下载更新'), findsOneWidget);
    expect(client.downloadCount, 1);
  });

  testWidgets('SHA256 不匹配时进入错误态并阻止安装', (tester) async {
    final calls = _installChannelHandler(canInstall: true);
    final client = _FakeUpdateClient(digest: 'b' * 64);

    await _openDialog(tester, client: client, installer: _installer());

    await tester.tap(find.text('下载更新'));
    await tester.pumpAndSettle();

    expect(find.text('更新失败'), findsOneWidget);
    expect(find.textContaining('安装包校验失败'), findsOneWidget);
    expect(find.text('重试下载'), findsOneWidget);
    // 摘要不匹配时不再触碰安装器（inspectApk 未达）。
    expect(calls, isEmpty);
  });

  testWidgets('未开始下载时点取消关闭弹窗且返回 false', (tester) async {
    _installChannelHandler(canInstall: true);
    final client = _FakeUpdateClient(digest: 'a' * 64);

    final result = await _openDialog(
      tester,
      client: client,
      installer: _installer(),
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsNothing);
    expect(await result, isFalse);
  });

  testWidgets('下载中点击 barrier 不关闭弹窗', (tester) async {
    _installChannelHandler(canInstall: true);
    final client = _FakeUpdateClient(digest: 'a' * 64);

    await _openDialog(tester, client: client, installer: _installer());

    await tester.tap(find.text('下载更新'));
    await tester.pump();
    expect(find.text('正在下载'), findsOneWidget);

    // 点击弹窗外的 barrier 区域。
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();

    expect(find.text('正在下载'), findsOneWidget);

    // 收尾：取消下载让挂起的 fake 正常结束，避免悬空异步。
    await tester.tap(find.text('取消下载'));
    await tester.pumpAndSettle();
  });

  testWidgets('就绪后立即安装调起系统安装器并回到就绪文案', (tester) async {
    final calls = _installChannelHandler(canInstall: true);
    final client = _FakeUpdateClient(digest: 'a' * 64);

    await _openDialog(tester, client: client, installer: _installer());

    await tester.tap(find.text('下载更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即安装'));
    await tester.pumpAndSettle();

    expect(
      find.text('已打开系统安装器，请按系统提示完成安装。'),
      findsOneWidget,
    );
    expect(find.text('可以安装'), findsOneWidget);
    expect(
      calls,
      containsAllInOrder([
        'inspectApk',
        'canRequestPackageInstalls',
        'installApk',
      ]),
    );
  });

  testWidgets('缺少安装权限时进入权限引导分支', (tester) async {
    final calls = _installChannelHandler(canInstall: false);
    final client = _FakeUpdateClient(digest: 'a' * 64);

    await _openDialog(tester, client: client, installer: _installer());

    await tester.tap(find.text('下载更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即安装'));
    await tester.pumpAndSettle();

    expect(find.text('需要安装权限'), findsOneWidget);
    expect(find.text('打开权限设置'), findsOneWidget);
    expect(find.text('继续安装'), findsOneWidget);
    expect(calls, isNot(contains('installApk')));
  });

  // 回归：权限引导态必须可退出，否则未授权用户被锁死在
  // 「继续安装→仍无权限→回到引导」循环，唯一出路只剩杀应用。
  testWidgets('权限引导态可暂不安装并关闭弹窗（曾下载 → 返回 true）', (tester) async {
    _installChannelHandler(canInstall: false);
    final client = _FakeUpdateClient(digest: 'a' * 64);

    final dialogFuture = await _openDialog(
      tester,
      client: client,
      installer: _installer(),
    );

    await tester.tap(find.text('下载更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即安装'));
    await tester.pumpAndSettle();
    expect(find.text('需要安装权限'), findsOneWidget);

    await tester.tap(find.text('暂不安装'));
    await tester.pumpAndSettle();

    // 弹窗已关闭；曾进入下载 → true（下次前台恢复可再提醒）。
    expect(find.text('需要安装权限'), findsNothing);
    expect(await dialogFuture, isTrue);
  });
}
