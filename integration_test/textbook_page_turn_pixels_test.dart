import 'package:integration_test/integration_test.dart';

import '../test/features/textbook/textbook_page_turn_test.dart' as page_turn;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  page_turn.main();
}
