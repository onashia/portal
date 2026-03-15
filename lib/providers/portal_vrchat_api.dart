import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/portal_calendar_api.dart';
import '../services/portal_file_api.dart';
import 'auth_provider.dart';
import 'portal_api_request_runner_provider.dart';

final portalCalendarApiProvider = Provider<PortalCalendarApi>((ref) {
  final api = ref.read(vrchatApiProvider);
  final runner = ref.read(portalApiRequestRunnerProvider);
  return PortalCalendarApi(api, runner);
});

final portalFileApiProvider = Provider<PortalFileApi>((ref) {
  final api = ref.read(vrchatApiProvider);
  final runner = ref.read(portalApiRequestRunnerProvider);
  return PortalFileApi(api, runner);
});
