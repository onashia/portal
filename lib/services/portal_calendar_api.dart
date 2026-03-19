import 'package:vrchat_dart/vrchat_dart.dart';

import 'api_rate_limit_coordinator.dart';
import 'portal_api_request_runner.dart';

class PortalCalendarApi {
  PortalCalendarApi(this._api, this._runner);

  final VrchatDart _api;
  final PortalApiRequestRunner _runner;

  Future<List<CalendarEvent>> getGroupCalendarEvents({
    required String groupId,
    required int n,
  }) {
    return _runner.run<List<CalendarEvent>>(
      lane: ApiRequestLane.calendar,
      request: (extra) async {
        final response = await _api.rawApi
            .getCalendarApi()
            .getGroupCalendarEvents(groupId: groupId, n: n, extra: extra);
        return response.data?.results ?? const <CalendarEvent>[];
      },
    );
  }
}
