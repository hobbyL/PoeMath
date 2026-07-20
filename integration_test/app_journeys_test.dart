// Android-first end-to-end journeys. Run locally with:
// flutter test integration_test/app_journeys_test.dart -d <android-device-id>

import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';

import 'package:poemath/core/constants/app_constants.dart';
import 'package:poemath/core/constants/hive_keys.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/hive/hive_registrar.dart';

import 'support/app_journey_suite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  defineAppJourneyTests(
    setUpStorage: _setUpIntegrationStorage,
    tearDownStorage: HiveBoxes.close,
  );
}

Future<void> _setUpIntegrationStorage() async {
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
  ]);
  await HiveBoxes.meta.put(
    HiveKeys.metaDataVersion,
    AppConstants.dataVersion,
  );
  await HiveBoxes.settings.put('has_onboarded', true);
}
