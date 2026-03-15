import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/portal_api_request_runner.dart';
import 'api_call_counter.dart';
import 'api_rate_limit_provider.dart';

final portalApiRequestRunnerProvider = Provider<PortalApiRequestRunner>((ref) {
  final coordinator = ref.read(apiRateLimitCoordinatorProvider);
  final counter = ref.read(apiCallCounterProvider.notifier);
  return PortalApiRequestRunner(
    coordinator: coordinator,
    recordApiCall: counter.incrementApiCall,
    recordThrottledSkip: counter.incrementThrottledSkip,
  );
});
