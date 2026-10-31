import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:poemath/core/services/update/android_update_installer.dart';
import 'package:poemath/core/services/update/update_models.dart';

// 合成 APK 通过 dart-define-from-file 提供，测试只运行在独立 integration 包。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('真实 APK 签名读取及原生签名、包名、路径拒绝', (tester) async {
    expect(const bool.fromEnvironment('POEMATH_INTEGRATION_TEST'), isTrue);
    final installer = AndroidUpdateInstaller();
    final version = await installer.getCurrentVersion();
    expect(version.packageName, 'com.poemath.app.integration');
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    final cache = await getTemporaryDirectory();
    final allowed = await Directory('${cache.path}/poemath_update').create();
    final prefix =
        'signature_acceptance_${DateTime.now().microsecondsSinceEpoch}';
    final files = <File>[];
    addTearDown(() async {
      for (final file in files) {
        if (await file.exists()) await file.delete();
      }
    });
    Future<File> fixture(
      String name,
      String encoded, {
      bool inScope = true,
    }) async {
      expect(encoded, isNotEmpty, reason: '缺少合成 APK 定义：$name');
      final root = inScope ? allowed : cache;
      final file = File('${root.path}/${prefix}_$name.apk');
      files.add(file);
      await file.writeAsBytes(base64Decode(encoded), flush: true);
      return file;
    }

    const sameApk = String.fromEnvironment('AUDIT_SAME_APK');
    final same = await fixture('same', sameApk);
    final different = await fixture(
      'different',
      const String.fromEnvironment('AUDIT_DIFFERENT_APK'),
    );
    final wrongPackage = await fixture(
      'package',
      const String.fromEnvironment('AUDIT_PACKAGE_APK'),
    );
    final unsigned = await fixture(
      'unsigned',
      const String.fromEnvironment('AUDIT_UNSIGNED_APK'),
    );
    final outside = await fixture('outside', sameApk, inScope: false);
    final invalid =
        await fixture('invalid', base64Encode(utf8.encode('not apk')));

    final installed = await installer.getInstalledSignatureSha256();
    final matching = await installer.inspectApkSignature(same.path);
    final foreign = await installer.inspectApkSignature(different.path);
    expect(installed, isNotEmpty);
    expect(installed.every(RegExp(r'^[0-9a-f]{64}$').hasMatch), isTrue);
    expect(matching, unorderedEquals(installed));
    expect(foreign, isNotEmpty);
    expect(foreign!.toSet().intersection(installed.toSet()), isEmpty);
    expect(
      apkSignatureError(installed: installed, incoming: matching!),
      isNull,
    );
    expect(await installer.inspectApkSignature(invalid.path), isNull);

    const channel = MethodChannel('com.poemath.app/app_update');
    Future<void> rejects(File file, String code) async {
      await expectLater(
        channel.invokeMethod<void>('installApk', {'path': file.path}),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
      );
    }

    await rejects(different, 'APK_SIGNATURE_MISMATCH');
    await rejects(wrongPackage, 'APK_PACKAGE_MISMATCH');
    await rejects(outside, 'APK_PATH_NOT_ALLOWED');
    await rejects(unsigned, 'APK_SIGNATURE_UNAVAILABLE');
    await rejects(invalid, 'APK_UNREADABLE');
  });
}
