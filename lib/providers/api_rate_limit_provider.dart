import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_rate_limit_coordinator.dart';

final apiRateLimitCoordinatorProvider = Provider<ApiRateLimitCoordinator>((
  ref,
) {
  return ApiRateLimitCoordinator();
});
