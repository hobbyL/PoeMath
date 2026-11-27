import '../../../integration_test/support/math_operation_flow_suite.dart';
import '../../helpers/hive_test_helper.dart';

void main() => defineMathOperationFlowTests(
  setUpStorage: setUpHiveForTesting,
  tearDownStorage: tearDownHiveForTesting,
);
