// fvm flutter test integration_test/math_operation_flow_test.dart -d emulator-5554
//   --dart-define=POEMATH_INTEGRATION_TEST=true --no-uninstall
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../test/helpers/hive_test_helper.dart';
import 'support/math_operation_flow_suite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  defineMathOperationFlowTests(
    setUpStorage: () async {
      expect(
        (await PackageInfo.fromPlatform()).packageName,
        'com.poemath.app.integration',
        reason: '必须使用隔离的集成测试包',
      );
      await setUpHiveForTesting();
    },
    tearDownStorage: tearDownHiveForTesting,
  );
}
