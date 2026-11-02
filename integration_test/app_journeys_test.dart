// Android-first end-to-end journeys. Run locally with:
// flutter test integration_test/app_journeys_test.dart -d <android-device-id>
//   --dart-define=POEMATH_INTEGRATION_TEST=true --no-uninstall

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'package:poemath/core/constants/app_constants.dart';
import 'package:poemath/core/constants/hive_keys.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/hive/hive_registrar.dart';
import 'package:poemath/data/repositories/poem_repository.dart';

import 'support/app_journey_suite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  defineAppJourneyTests(
    setUpStorage: _setUpIntegrationStorage,
    tearDownStorage: HiveBoxes.close,
    directoryProvider: () async {
      final support = await getApplicationSupportDirectory();
      return Directory('${support.path}/integration_test');
    },
  );
}

Future<void> _setUpIntegrationStorage() async {
  expect(
    (await PackageInfo.fromPlatform()).packageName,
    'com.poemath.app.integration',
    reason: '必须加 --dart-define=POEMATH_INTEGRATION_TEST=true 隔离测试包',
  );
  // Keep device runs out of the normal application Hive directory. The
  // journey suite clears its boxes before every test and must never erase a
  // developer's regular local data.
  await Hive.initFlutter('integration_test');
  registerHiveAdapters();
  await HiveBoxes.init();
  await Future.wait<int>([
    HiveBoxes.poems.clear(),
    HiveBoxes.authors.clear(),
    HiveBoxes.formulas.clear(),
    HiveBoxes.poemProgress.clear(),
    HiveBoxes.poemFavorites.clear(),
    HiveBoxes.reviewSchedules.clear(),
    HiveBoxes.mathMistakes.clear(),
    HiveBoxes.mathSessions.clear(),
    HiveBoxes.formulaFavorites.clear(),
    HiveBoxes.achievements.clear(),
    HiveBoxes.checkIns.clear(),
    HiveBoxes.userStats.clear(),
    HiveBoxes.challengeRecords.clear(),
    HiveBoxes.settings.clear(),
    HiveBoxes.meta.clear(),
    HiveBoxes.learningActivities.clear(),
    HiveBoxes.llmProblems.clear(),
    HiveBoxes.conversations.clear(),
    HiveBoxes.messages.clear(),
  ]);
  await HiveBoxes.meta.put(
    HiveKeys.metaDataVersion,
    AppConstants.dataVersion,
  );
  await HiveBoxes.settings.put('has_onboarded', true);
  await HiveBoxes.meta.put('content_revision', AppConstants.contentRevision);
  PoemRepository.resetIndices();
}
