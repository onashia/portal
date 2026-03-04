import 'package:flutter_test/flutter_test.dart';
import 'package:portal/constants/app_constants.dart';

const _productionRelayBootstrapUrl =
    'https://portal-relay-assist.me-3aa.workers.dev/relay/bootstrap';

void main() {
  test('relay bootstrap URL uses production default or explicit override', () {
    const expectedOverride = String.fromEnvironment(
      'TEST_EXPECTED_RELAY_URL',
      defaultValue: '',
    );

    final expected = expectedOverride.isNotEmpty
        ? expectedOverride
        : _productionRelayBootstrapUrl;

    expect(AppConstants.relayBootstrapUrl, expected);
  });
}
