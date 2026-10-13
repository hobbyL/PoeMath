// test/core/services/haptic_service_test.dart
//
// 触觉反馈服务：主调用成功时不得追加兜底震动（原实现无条件补一次，
// 每次反馈震动两次）；主调用失败时才兜底一次；开关关闭时零平台调用。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/haptic_service.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> calls;

  /// 拦截 SystemChannels.platform 上的 HapticFeedback.vibrate 调用，
  /// 记录其 arguments（即具体反馈类型）。[failTypes] 内的类型抛异常，
  /// 模拟平台不支持该反馈。
  void mockHaptics({Set<String> failTypes = const <String>{}}) {
    calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method != 'HapticFeedback.vibrate') return null;
      final type = call.arguments as String? ?? 'vibrate';
      calls.add(type);
      if (failTypes.contains(type)) {
        throw PlatformException(code: 'unsupported', message: type);
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
  }

  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  Future<HapticService> createService({bool enabled = true}) async {
    final settings = SettingsRepository();
    await settings.setHapticEnabled(enabled);
    return HapticService(settings);
  }

  test('平台支持时每级反馈只触发一次平台调用', () async {
    mockHaptics();
    final service = await createService();

    await service.light();
    expect(calls, <String>['HapticFeedbackType.lightImpact']);

    calls.clear();
    await service.medium();
    expect(calls, <String>['HapticFeedbackType.mediumImpact']);

    calls.clear();
    await service.heavy();
    expect(calls, <String>['HapticFeedbackType.heavyImpact']);

    calls.clear();
    await service.selection();
    expect(calls, <String>['HapticFeedbackType.selectionClick']);
  });

  test('主调用失败时才兜底一次', () async {
    mockHaptics(
      failTypes: <String>{
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.heavyImpact',
      },
    );
    final service = await createService();

    await service.light();
    expect(calls, <String>[
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.selectionClick',
    ]);

    calls.clear();
    await service.medium();
    expect(calls, <String>['HapticFeedbackType.mediumImpact', 'vibrate']);

    calls.clear();
    await service.heavy();
    expect(calls, <String>['HapticFeedbackType.heavyImpact', 'vibrate']);
  });

  test('主调用与兜底都失败时不抛出', () async {
    mockHaptics(
      failTypes: <String>{'HapticFeedbackType.mediumImpact', 'vibrate'},
    );
    final service = await createService();

    await expectLater(service.medium(), completes);
    expect(calls, <String>['HapticFeedbackType.mediumImpact', 'vibrate']);
  });

  test('开关关闭时零平台调用', () async {
    mockHaptics();
    final service = await createService(enabled: false);

    await service.light();
    await service.medium();
    await service.heavy();
    await service.selection();

    expect(calls, isEmpty);
  });
}
