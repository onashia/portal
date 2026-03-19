import 'package:dio/dio.dart' as dio;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/services/api_rate_limit_coordinator.dart';
import 'package:portal/services/portal_api_request_runner.dart';
import 'package:portal/services/portal_calendar_api.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

class _MockVrchatDart extends Mock implements VrchatDart {}

class _MockVrchatRawApi extends Mock implements VrchatDartGenerated {}

class _MockCalendarApi extends Mock implements CalendarApi {}

void main() {
  test('routes calendar requests through runner lane metadata', () async {
    final api = _MockVrchatDart();
    final rawApi = _MockVrchatRawApi();
    final calendarApi = _MockCalendarApi();
    final recordedLanes = <ApiRequestLane?>[];
    final runner = PortalApiRequestRunner(
      coordinator: ApiRateLimitCoordinator(),
      recordApiCall: ({lane}) => recordedLanes.add(lane),
      recordThrottledSkip: ({lane}) {},
    );
    final service = PortalCalendarApi(api, runner);

    when(() => api.rawApi).thenReturn(rawApi);
    when(() => rawApi.getCalendarApi()).thenReturn(calendarApi);
    when(
      () => calendarApi.getGroupCalendarEvents(
        groupId: 'grp_alpha',
        n: 60,
        extra: any(named: 'extra'),
      ),
    ).thenAnswer(
      (_) async => dio.Response<PaginatedCalendarEventList>(
        requestOptions: dio.RequestOptions(path: '/calendar/groups/grp_alpha'),
        statusCode: 200,
        data: PaginatedCalendarEventList(results: const <CalendarEvent>[]),
      ),
    );

    await service.getGroupCalendarEvents(groupId: 'grp_alpha', n: 60);

    expect(recordedLanes, [ApiRequestLane.calendar]);
    final extra =
        verify(
              () => calendarApi.getGroupCalendarEvents(
                groupId: 'grp_alpha',
                n: 60,
                extra: captureAny(named: 'extra'),
              ),
            ).captured.single
            as Map<String, dynamic>?;
    expect(
      apiRequestLaneFromExtraValue(extra?[portalApiLaneExtraKey]),
      ApiRequestLane.calendar,
    );
  });
}
