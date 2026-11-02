// Run the same navigation and persistence assertions as the Android CI job.
// Fresh Hive and support directories keep host runs independent of device data.
import 'dart:io';

import '../../integration_test/support/app_journey_suite.dart';
import '../helpers/hive_test_helper.dart';

void main() {
  late Directory directory;
  defineAppJourneyTests(
    setUpStorage: () async {
      await setUpHiveForTesting();
      directory = await Directory.systemTemp.createTemp('app_journeys_');
    },
    tearDownStorage: () async {
      await tearDownHiveForWidgetTesting();
      await directory.delete(recursive: true);
    },
    directoryProvider: () async => directory,
  );
}
